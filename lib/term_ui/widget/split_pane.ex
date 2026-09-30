defmodule TermUI.Widget.SplitPane do
  @moduledoc """
  A pure two-pane or multi-pane frame composition widget.

  The original `:first`, `:second`, and `:ratio` options remain supported.
  `:panes` accepts named pane data for larger layouts. Collapse state, weights,
  separator focus, and mouse drag all remain in the returned widget value.
  """

  @behaviour TermUI.Widget

  alias TermUI.{Event, Frame, Style}
  alias TermUI.Widget.Helpers

  @state_version 1

  @type content ::
          Frame.t()
          | [Frame.row()]
          | String.t()
          | {module(), term()}
          | (TermUI.Widget.dimensions() -> Frame.t())
  @type pane :: %{required(:id) => term(), required(:content) => content()}
  @type layout_entry :: %{
          id: term(),
          index: non_neg_integer(),
          start: non_neg_integer(),
          size: non_neg_integer(),
          cross_size: pos_integer(),
          content: content()
        }
  @type separator :: %{
          index: non_neg_integer(),
          position: non_neg_integer(),
          before_index: non_neg_integer(),
          after_index: non_neg_integer()
        }
  @type layout :: %{panes: [layout_entry()], separators: [separator()]}
  @type serialized_state :: %{
          version: 1,
          mode: :legacy | :multi,
          pane_ids: [term()],
          direction: :horizontal | :vertical,
          ratios: [float()],
          collapsed: [term()],
          focused_separator: non_neg_integer(),
          min_size: pos_integer(),
          keyboard_resize: boolean()
        }
  @type restore_error :: :invalid_state | :pane_mismatch | {:unsupported_version, term()}

  @type t :: %__MODULE__{
          first: content(),
          second: content(),
          direction: :horizontal | :vertical,
          ratio: float(),
          dragging: boolean(),
          panes: [pane()],
          ratios: [float()],
          collapsed: [term()],
          drag_separator: non_neg_integer() | nil,
          focused_separator: non_neg_integer(),
          min_size: pos_integer(),
          legacy: boolean(),
          keyboard_resize: boolean()
        }

  defstruct first: [],
            second: [],
            direction: :horizontal,
            ratio: 0.5,
            dragging: false,
            panes: [],
            ratios: [],
            collapsed: [],
            drag_separator: nil,
            focused_separator: 0,
            min_size: 1,
            legacy: true,
            keyboard_resize: false

  @impl true
  def init(opts) do
    first = Keyword.get(opts, :first, [])
    second = Keyword.get(opts, :second, [])
    legacy = not Keyword.has_key?(opts, :panes)

    panes =
      if legacy,
        do: [%{id: :first, content: first}, %{id: :second, content: second}],
        else: normalize_panes(Keyword.fetch!(opts, :panes))

    ratio = opts |> Keyword.get(:ratio, 0.5) |> max(0.1) |> min(0.9)

    ratios =
      if legacy,
        do: [ratio, 1.0 - ratio],
        else: normalize_ratios(Keyword.get(opts, :ratios), length(panes))

    collapsed = initial_collapsed(panes, Keyword.get(opts, :collapsed, []))

    %__MODULE__{
      first: first,
      second: second,
      direction: Keyword.get(opts, :direction, :horizontal),
      ratio: ratio,
      panes: Enum.map(panes, &Map.delete(&1, :collapsed)),
      ratios: ratios,
      collapsed: collapsed,
      min_size: max(Keyword.get(opts, :min_size, 1), 1),
      legacy: legacy,
      keyboard_resize: Keyword.get(opts, :keyboard_resize, not legacy)
    }
  end

  @impl true
  def update(%Event.Key{key: key}, %{keyboard_resize: true} = state) when key in [:left, :up],
    do: resize_focused(state, -0.05)

  def update(%Event.Key{key: key}, %{keyboard_resize: true} = state) when key in [:right, :down],
    do: resize_focused(state, 0.05)

  def update(%Event.Key{key: :tab, modifiers: modifiers}, %{keyboard_resize: true} = state) do
    count = max(visible_count(state) - 1, 0)

    if count == 0 do
      {state, []}
    else
      delta = if :shift in modifiers, do: -1, else: 1
      focused = rem(state.focused_separator + delta + count, count)
      {%{state | focused_separator: focused}, [{:separator_focused, focused}]}
    end
  end

  def update(_event, state), do: {state, []}

  @impl true
  def mouse(%Event.Mouse{action: :press, button: :left} = event, state, dimensions) do
    case separator_at(state, event, dimensions) do
      nil ->
        {state, []}

      separator ->
        {%{
           state
           | dragging: true,
             drag_separator: separator.index,
             focused_separator: separator.index
         }, []}
    end
  end

  def mouse(
        %Event.Mouse{action: :drag, button: :left} = event,
        %{dragging: true, drag_separator: separator_index} = state,
        dimensions
      ) do
    resize_to_pointer(state, separator_index, event, dimensions)
  end

  def mouse(%Event.Mouse{action: :release, button: :left}, state, _dimensions),
    do: {%{state | dragging: false, drag_separator: nil}, []}

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {width, height} = dimensions) do
    %{panes: panes, separators: separators} = layout(state, dimensions)
    separator_style = Style.new(fg: :bright_black)

    base =
      Enum.reduce(separators, Frame.new(width, height), fn separator, frame ->
        draw_separator(frame, state.direction, separator.position, separator_style)
      end)

    Enum.reduce(panes, base, fn pane, frame ->
      if pane.size <= 0 do
        frame
      else
        {pane_width, pane_height, column, row} = pane_geometry(state.direction, pane)

        child =
          pane.content
          |> resolve({pane_width, pane_height})
          |> fit_frame({pane_width, pane_height})

        Frame.overlay(frame, child, column, row)
      end
    end)
  end

  @doc "Returns measured pane and separator positions for the supplied dimensions."
  @spec layout(t(), TermUI.Widget.dimensions()) :: layout()
  def layout(state, {width, height}) when width > 0 and height > 0 do
    cross_size = if state.direction == :horizontal, do: height, else: width
    main_size = if state.direction == :horizontal, do: width, else: height

    visible =
      state.panes
      |> Enum.with_index()
      |> Enum.reject(fn {pane, _index} -> pane.id in state.collapsed end)

    separator_count = max(length(visible) - 1, 0)
    available = max(main_size - separator_count, 0)

    weights =
      Enum.map(visible, fn {_pane, index} -> Enum.at(effective_ratios(state), index, 1.0) end)

    sizes = allocate_sizes(weights, available, state.min_size)

    {panes, separators, _start} =
      visible
      |> Enum.zip(sizes)
      |> Enum.with_index()
      |> Enum.reduce(
        {[], [], 0},
        fn {{{pane, index}, size}, visible_index}, {panes, separators, start} ->
          entry = %{
            id: pane.id,
            index: index,
            start: start,
            size: size,
            cross_size: cross_size,
            content: pane_content(state, pane)
          }

          if visible_index < length(visible) - 1 do
            {_next_pane, next_index} = Enum.at(visible, visible_index + 1)

            separator = %{
              index: visible_index,
              position: start + size,
              before_index: index,
              after_index: next_index
            }

            {panes ++ [entry], separators ++ [separator], start + size + 1}
          else
            {panes ++ [entry], separators, start + size}
          end
        end
      )

    %{panes: panes, separators: separators}
  end

  @doc "Collapses a named pane."
  @spec collapse(t(), term()) :: t()
  def collapse(state, id) do
    if Enum.any?(state.panes, &(&1.id == id)),
      do: %{state | collapsed: Enum.uniq(state.collapsed ++ [id])},
      else: state
  end

  @doc "Expands a named pane."
  @spec expand(t(), term()) :: t()
  def expand(state, id), do: %{state | collapsed: List.delete(state.collapsed, id)}

  @doc "Toggles a named pane's collapse state."
  @spec toggle(t(), term()) :: t()
  def toggle(state, id),
    do: if(collapsed?(state, id), do: expand(state, id), else: collapse(state, id))

  @doc "Returns true when a named pane is collapsed."
  @spec collapsed?(t(), term()) :: boolean()
  def collapsed?(state, id), do: id in state.collapsed

  @doc "Replaces content for a named pane."
  @spec put_pane(t(), term(), content()) :: t()
  def put_pane(state, id, content) do
    panes =
      Enum.map(state.panes, fn pane ->
        if pane.id == id, do: %{pane | content: content}, else: pane
      end)

    case id do
      :first when state.legacy -> %{state | panes: panes, first: content}
      :second when state.legacy -> %{state | panes: panes, second: content}
      _other -> %{state | panes: panes}
    end
  end

  @doc "Moves keyboard resize focus to a zero-based visible separator."
  @spec focus_separator(t(), non_neg_integer()) :: t()
  def focus_separator(state, index) do
    maximum = max(visible_count(state) - 2, 0)
    %{state | focused_separator: Helpers.clamp(index, 0, maximum)}
  end

  @doc """
  Returns the versioned pure layout state for application-owned storage.

  Pane content and transient drag state are intentionally not included.
  """
  @spec serialize(t()) :: serialized_state()
  def serialize(state) do
    %{
      version: @state_version,
      mode: if(state.legacy, do: :legacy, else: :multi),
      pane_ids: Enum.map(state.panes, & &1.id),
      direction: state.direction,
      ratios: effective_ratios(state),
      collapsed: state.collapsed,
      focused_separator: state.focused_separator,
      min_size: state.min_size,
      keyboard_resize: state.keyboard_resize
    }
  end

  @doc """
  Validates and restores versioned layout state into the current panes.

  The ordered pane IDs and legacy or multi-pane mode must match. Content stays
  in the current widget value. Unknown versions and invalid values return an
  error without changing that value.
  """
  @spec restore(t(), term()) :: {:ok, t()} | {:error, restore_error()}
  def restore(state, %{version: @state_version} = serialized) do
    with {:ok, fields} <- validate_serialized(state, serialized) do
      {:ok, apply_serialized(state, fields)}
    end
  end

  def restore(_state, %{version: version}), do: {:error, {:unsupported_version, version}}
  def restore(_state, _invalid), do: {:error, :invalid_state}

  defp validate_serialized(
         state,
         %{
           mode: mode,
           pane_ids: pane_ids,
           direction: direction,
           ratios: ratios,
           collapsed: collapsed,
           focused_separator: focused_separator,
           min_size: min_size,
           keyboard_resize: keyboard_resize
         }
       ) do
    with :ok <- validate_mode(state, mode),
         :ok <- validate_pane_ids(state, pane_ids),
         :ok <- validate_direction(direction),
         {:ok, ratios} <- validate_saved_ratios(ratios, length(state.panes), mode),
         :ok <- validate_collapsed(collapsed, pane_ids),
         :ok <- validate_focused_separator(focused_separator, length(state.panes)),
         :ok <- validate_min_size(min_size),
         :ok <- validate_keyboard_resize(keyboard_resize) do
      {:ok,
       %{
         direction: direction,
         ratios: ratios,
         collapsed: collapsed,
         focused_separator: focused_separator,
         min_size: min_size,
         keyboard_resize: keyboard_resize
       }}
    end
  end

  defp validate_serialized(_state, _invalid), do: {:error, :invalid_state}

  defp apply_serialized(state, fields) do
    state =
      %{
        state
        | direction: fields.direction,
          ratios: fields.ratios,
          collapsed: fields.collapsed,
          focused_separator: fields.focused_separator,
          min_size: fields.min_size,
          keyboard_resize: fields.keyboard_resize,
          dragging: false,
          drag_separator: nil
      }

    if state.legacy do
      [before, after_pane] = fields.ratios
      %{state | ratio: before / (before + after_pane)}
    else
      state
    end
  end

  defp validate_mode(%{legacy: legacy}, mode) do
    if mode == if(legacy, do: :legacy, else: :multi),
      do: :ok,
      else: {:error, :pane_mismatch}
  end

  defp validate_pane_ids(state, pane_ids) when is_list(pane_ids) do
    if pane_ids == Enum.map(state.panes, & &1.id),
      do: :ok,
      else: {:error, :pane_mismatch}
  end

  defp validate_pane_ids(_state, _invalid), do: {:error, :invalid_state}

  defp validate_direction(direction) when direction in [:horizontal, :vertical], do: :ok
  defp validate_direction(_invalid), do: {:error, :invalid_state}

  defp validate_saved_ratios(ratios, count, mode)
       when is_list(ratios) and length(ratios) == count do
    if Enum.all?(ratios, &(is_number(&1) and &1 > 0)) do
      validate_saved_ratio_mode(Enum.map(ratios, &(&1 * 1.0)), mode)
    else
      {:error, :invalid_state}
    end
  end

  defp validate_saved_ratios(_ratios, _count, _mode), do: {:error, :invalid_state}

  defp validate_saved_ratio_mode([before, after_pane] = ratios, :legacy) do
    share = before / (before + after_pane)
    if share >= 0.1 and share <= 0.9, do: {:ok, ratios}, else: {:error, :invalid_state}
  end

  defp validate_saved_ratio_mode(ratios, :multi), do: {:ok, ratios}
  defp validate_saved_ratio_mode(_ratios, _invalid), do: {:error, :invalid_state}

  defp validate_collapsed(collapsed, pane_ids) when is_list(collapsed) do
    valid_ids = MapSet.new(pane_ids)

    if collapsed == Enum.uniq(collapsed) and Enum.all?(collapsed, &MapSet.member?(valid_ids, &1)),
      do: :ok,
      else: {:error, :invalid_state}
  end

  defp validate_collapsed(_collapsed, _pane_ids), do: {:error, :invalid_state}

  defp validate_focused_separator(index, pane_count)
       when is_integer(index) and index >= 0 and index <= max(pane_count - 2, 0),
       do: :ok

  defp validate_focused_separator(_index, _pane_count), do: {:error, :invalid_state}

  defp validate_min_size(min_size) when is_integer(min_size) and min_size > 0, do: :ok
  defp validate_min_size(_invalid), do: {:error, :invalid_state}

  defp validate_keyboard_resize(value) when is_boolean(value), do: :ok
  defp validate_keyboard_resize(_invalid), do: {:error, :invalid_state}

  defp resize_to_pointer(state, separator_index, event, dimensions) do
    current_layout = layout(state, dimensions)

    case Enum.at(current_layout.separators, separator_index) do
      nil ->
        {state, []}

      separator ->
        before = Enum.find(current_layout.panes, &(&1.index == separator.before_index))
        after_pane = Enum.find(current_layout.panes, &(&1.index == separator.after_index))
        pointer = if state.direction == :horizontal, do: event.x, else: event.y
        pair_size = before.size + after_pane.size
        minimum = min(state.min_size, max(div(pair_size, 2), 1))

        before_size =
          Helpers.clamp(
            pointer - before.start,
            minimum,
            max(pair_size - minimum, minimum)
          )

        state =
          set_pair_share(
            state,
            before.index,
            after_pane.index,
            before_size / max(pair_size, 1)
          )

        {state, [{:resized, resize_message(state, separator_index)}]}
    end
  end

  defp resize_focused(state, delta) do
    visible =
      state.panes
      |> Enum.with_index()
      |> Enum.reject(fn {pane, _index} -> pane.id in state.collapsed end)

    case Enum.at(Enum.chunk_every(visible, 2, 1, :discard), state.focused_separator) do
      [{_before, before_index}, {_after, after_index}] ->
        weights = effective_ratios(state)
        pair = Enum.at(weights, before_index, 0.5) + Enum.at(weights, after_index, 0.5)
        share = Enum.at(weights, before_index, 0.5) / max(pair, 0.0001)
        state = set_pair_share(state, before_index, after_index, share + delta)
        {state, [{:resized, resize_message(state, state.focused_separator)}]}

      _other ->
        {state, []}
    end
  end

  defp set_pair_share(state, before_index, after_index, share) do
    share = share |> max(0.1) |> min(0.9)
    ratios = effective_ratios(state)
    pair = Enum.at(ratios, before_index, 0.5) + Enum.at(ratios, after_index, 0.5)

    ratios =
      ratios
      |> List.replace_at(before_index, pair * share)
      |> List.replace_at(after_index, pair * (1.0 - share))

    if state.legacy,
      do: %{state | ratios: ratios, ratio: share},
      else: %{state | ratios: ratios}
  end

  defp resize_message(%{legacy: true} = state, _separator_index), do: state.ratio

  defp resize_message(state, separator_index),
    do: %{separator: separator_index, ratios: state.ratios}

  defp pane_content(%{legacy: true} = state, %{id: :first}), do: state.first
  defp pane_content(%{legacy: true} = state, %{id: :second}), do: state.second
  defp pane_content(_state, pane), do: pane.content

  defp effective_ratios(%{legacy: true, ratio: ratio}), do: [ratio, 1.0 - ratio]
  defp effective_ratios(state), do: state.ratios

  defp separator_at(state, event, dimensions) do
    pointer = if state.direction == :horizontal, do: event.x, else: event.y
    Enum.find(layout(state, dimensions).separators, &(&1.position == pointer))
  end

  defp draw_separator(frame, :horizontal, position, style) do
    cell = Style.to_cell(style, "│")
    Enum.reduce(1..frame.height, frame, &Frame.put_cell(&2, &1, position + 1, cell))
  end

  defp draw_separator(frame, :vertical, position, style),
    do: Frame.put_row(frame, position + 1, [{String.duplicate("─", frame.width), style}])

  defp pane_geometry(:horizontal, pane),
    do: {pane.size, pane.cross_size, pane.start + 1, 1}

  defp pane_geometry(:vertical, pane),
    do: {pane.cross_size, pane.size, 1, pane.start + 1}

  defp resolve(%Frame{} = frame, _dimensions), do: frame

  defp resolve({module, widget_state}, dimensions),
    do: TermUI.Widget.view(module, widget_state, dimensions)

  defp resolve(fun, dimensions) when is_function(fun, 1), do: fun.(dimensions)

  defp resolve(content, {width, height}) when is_binary(content),
    do: Frame.from_rows(String.split(content, "\n", trim: false), width, height)

  defp resolve(rows, {width, height}) when is_list(rows),
    do: Frame.from_rows(rows, width, height)

  defp fit_frame(%Frame{width: width, height: height} = frame, {width, height}), do: frame

  defp fit_frame(%Frame{} = frame, {width, height}) do
    cursor = clipped_cursor(frame.cursor, {width, height})
    Frame.new(width, height, cells: frame.cells, cursor: cursor)
  end

  defp clipped_cursor({column, row} = cursor, {width, height})
       when column <= width and row <= height,
       do: cursor

  defp clipped_cursor(_cursor, _dimensions), do: nil

  defp normalize_panes(panes) do
    normalized =
      panes
      |> Enum.with_index()
      |> Enum.map(fn
        {%{id: _id, content: _content} = pane, _index} -> pane
        {{id, content}, _index} -> %{id: id, content: content}
        {content, index} -> %{id: index, content: content}
      end)

    ids = Enum.map(normalized, & &1.id)

    if length(ids) == length(Enum.uniq(ids)),
      do: normalized,
      else: raise(ArgumentError, "pane ids must be unique")
  end

  defp initial_collapsed(panes, collapsed) do
    pane_collapsed = for %{id: id, collapsed: true} <- panes, do: id
    valid_ids = MapSet.new(Enum.map(panes, & &1.id))

    (pane_collapsed ++ List.wrap(collapsed))
    |> Enum.uniq()
    |> Enum.filter(&MapSet.member?(valid_ids, &1))
  end

  defp normalize_ratios(nil, count), do: List.duplicate(1.0, count)

  defp normalize_ratios(ratios, count) when is_list(ratios) and length(ratios) == count do
    if Enum.all?(ratios, &(is_number(&1) and &1 > 0)),
      do: Enum.map(ratios, &(&1 * 1.0)),
      else: raise(ArgumentError, "pane ratios must be positive numbers")
  end

  defp normalize_ratios(_ratios, count),
    do: raise(ArgumentError, "pane ratios must contain one value for each of the #{count} panes")

  defp allocate_sizes([], _available, _minimum), do: []

  defp allocate_sizes(weights, available, minimum) do
    count = length(weights)

    base =
      if available >= count * minimum,
        do: List.duplicate(minimum, count),
        else: List.duplicate(0, count)

    remaining = max(available - Enum.sum(base), 0)
    total = Enum.sum(weights)
    raw = Enum.map(weights, &(&1 / max(total, 0.0001) * remaining))
    floors = Enum.map(raw, &floor/1)
    extra = remaining - Enum.sum(floors)

    order =
      raw
      |> Enum.with_index()
      |> Enum.sort_by(fn {value, index} -> {-(value - floor(value)), index} end)
      |> Enum.take(extra)
      |> Enum.map(&elem(&1, 1))
      |> MapSet.new()

    base
    |> Enum.zip(floors)
    |> Enum.with_index()
    |> Enum.map(fn {{base_size, floor_size}, index} ->
      base_size + floor_size + if(MapSet.member?(order, index), do: 1, else: 0)
    end)
  end

  defp visible_count(state), do: Enum.count(state.panes, &(&1.id not in state.collapsed))
end
