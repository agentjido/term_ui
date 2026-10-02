defmodule TermUI.Widget.TextInput do
  @moduledoc """
  A pure, single-line text input widget.

  The parent application owns the returned state and calls `update/2` for
  normalized terminal events. The update result is `{state, messages}`.
  Changes emit `{:changed, value}` and Enter emits `{:submit, value}`.

  `init/1` accepts `:value`, `:placeholder`, `:max_length`, and
  `:selection_style`. `view/2` returns a one-row frame with a visible cursor.
  `row/2` returns plain fitted text and its one-based cursor column.
  `row_spans/2` retains selection styles for manual composition.

  Shift with Left, Right, Home, or End changes the selection. Ctrl+A selects
  all text. Ctrl+C returns `{:copy, text}`. Ctrl+X also removes the selection
  and returns `{:changed, value}`. Mouse press and drag use zero-based local
  columns from `mouse/3`.

  Alt+Backspace (Option+Delete on macOS) removes trailing spaces and the
  preceding word. An active selection is removed first.

  ## Example

      input = TermUI.Widget.TextInput.init(placeholder: "Name", max_length: 80)
      {input, messages} = TermUI.Widget.TextInput.update(event, input)
      frame = TermUI.Widget.TextInput.view(input, {40, 1})
  """

  @behaviour TermUI.Widget

  alias TermUI.{Cell, Event, Frame, Selection, Style}
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          value: String.t(),
          cursor: non_neg_integer(),
          placeholder: String.t(),
          max_length: pos_integer() | :infinity,
          selection: Selection.t(),
          selection_style: Style.t()
        }

  defstruct value: "",
            cursor: 0,
            placeholder: "",
            max_length: :infinity,
            selection: %Selection{},
            selection_style: %Style{attrs: MapSet.new([:reverse])}

  @impl true
  def init(opts) do
    value = Keyword.get(opts, :value, "")

    %__MODULE__{
      value: value,
      cursor: length(String.graphemes(value)),
      placeholder: Keyword.get(opts, :placeholder, ""),
      max_length: Keyword.get(opts, :max_length, :infinity),
      selection_style: Keyword.get(opts, :selection_style, Style.new(attrs: [:reverse]))
    }
  end

  @impl true
  def update(%Event.Text{text: text}, state), do: insert(state, text)
  def update(%Event.Paste{content: text}, state), do: insert(state, text)

  def update(%Event.Key{key: "a", modifiers: modifiers}, state) do
    if :ctrl in modifiers do
      selection = Selection.select_all(state.selection, state.value)
      {%{state | selection: selection, cursor: selection.head}, []}
    else
      {state, []}
    end
  end

  def update(%Event.Key{key: "c", modifiers: modifiers}, state) do
    if :ctrl in modifiers, do: copy_selection(state), else: {state, []}
  end

  def update(%Event.Key{key: "x", modifiers: modifiers}, state) do
    if :ctrl in modifiers, do: cut_selection(state), else: {state, []}
  end

  def update(%Event.Key{key: :left, modifiers: modifiers}, state),
    do: horizontal(state, -1, modifiers)

  def update(%Event.Key{key: :right, modifiers: modifiers}, state),
    do: horizontal(state, 1, modifiers)

  def update(%Event.Key{key: :home, modifiers: modifiers}, state),
    do: navigate(state, 0, modifiers)

  def update(%Event.Key{key: :end, modifiers: modifiers}, state),
    do: navigate(state, grapheme_count(state.value), modifiers)

  def update(%Event.Key{key: :backspace, modifiers: modifiers}, state) do
    cond do
      not Selection.empty?(state.selection) -> delete_selection(state)
      state.cursor == 0 -> {state, []}
      true -> delete_before_cursor(state, modifiers)
    end
  end

  def update(%Event.Key{key: :delete}, state) do
    cond do
      not Selection.empty?(state.selection) -> delete_selection(state)
      state.cursor < grapheme_count(state.value) -> delete_at_cursor(state)
      true -> {state, []}
    end
  end

  def update(%Event.Key{key: :enter}, state), do: {state, [{:submit, state.value}]}
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, height}) when width > 0 and height > 0 do
    {content, cursor_column} = row_spans(state, width)
    Frame.from_rows([content], width, height, cursor: {cursor_column, 1})
  end

  @impl true
  def mouse(%Event.Mouse{action: :press, button: :left, x: x, modifiers: modifiers}, state, {
        width,
        _height
      }) do
    position = cursor_at(state, width, x)

    selection =
      if :shift in modifiers and Selection.active?(state.selection),
        do: Selection.extend(state.selection, position),
        else: state.selection |> Selection.start(position)

    {%{state | cursor: position, selection: selection}, []}
  end

  def mouse(%Event.Mouse{action: :drag, button: :left, x: x}, state, {width, _height}) do
    position = cursor_at(state, width, x)

    selection =
      if Selection.active?(state.selection),
        do: Selection.extend(state.selection, position),
        else: state.selection |> Selection.start(state.cursor) |> Selection.extend(position)

    {%{state | cursor: position, selection: selection}, []}
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @doc "Returns the fitted row and its one-based cursor column."
  @spec row(t(), pos_integer()) :: {String.t(), pos_integer()}
  def row(state, width) when is_integer(width) and width > 0 do
    layout = row_layout(state, width)
    {Frame.fit(layout.text, width), layout.cursor_column}
  end

  @doc "Returns styled fitted content and its one-based cursor column."
  @spec row_spans(t(), pos_integer()) :: {Frame.row(), pos_integer()}
  def row_spans(state, width) when is_integer(width) and width > 0 do
    layout = row_layout(state, width)

    content =
      if state.value == "" do
        layout.text
      else
        Enum.map(layout.entries, fn {grapheme, index} ->
          {grapheme, style_at(state, index)}
        end)
      end

    {content, layout.cursor_column}
  end

  defp insert(state, text) do
    inserted = text |> String.replace(~r/[\x00-\x1F\x7F]/u, "")

    selection =
      if Selection.empty?(state.selection),
        do: Selection.start(state.selection, state.cursor),
        else: state.selection

    {value, cursor, selection} = Selection.replace(selection, state.value, inserted)
    graphemes = value |> String.graphemes() |> limit(state.max_length)

    changed(%{
      state
      | value: Enum.join(graphemes),
        cursor: min(cursor, length(graphemes)),
        selection: selection
    })
  end

  defp horizontal(state, delta, modifiers) do
    target =
      if :shift not in modifiers and not Selection.empty?(state.selection) do
        {start, finish} = Selection.range(state.selection)
        if delta < 0, do: start, else: finish
      else
        state.cursor + delta
      end

    navigate(state, target, modifiers)
  end

  defp navigate(state, target, modifiers) do
    target = Helpers.clamp(target, 0, grapheme_count(state.value))

    selection =
      if :shift in modifiers do
        if Selection.active?(state.selection),
          do: Selection.extend(state.selection, target),
          else: state.selection |> Selection.start(state.cursor) |> Selection.extend(target)
      else
        Selection.clear(state.selection)
      end

    {%{state | cursor: target, selection: selection}, []}
  end

  defp copy_selection(state) do
    if Selection.empty?(state.selection),
      do: {state, []},
      else: {state, [{:copy, Selection.extract(state.selection, state.value)}]}
  end

  defp cut_selection(state) do
    if Selection.empty?(state.selection) do
      {state, []}
    else
      copied = Selection.extract(state.selection, state.value)
      {value, cursor, selection} = Selection.replace(state.selection, state.value, "")
      state = %{state | value: value, cursor: cursor, selection: selection}
      {state, [{:copy, copied}, {:changed, value}]}
    end
  end

  defp delete_selection(state) do
    {value, cursor, selection} = Selection.replace(state.selection, state.value, "")
    changed(%{state | value: value, cursor: cursor, selection: selection})
  end

  defp delete_before_cursor(state, modifiers) do
    start =
      if :alt in modifiers,
        do: Helpers.previous_word_start(state.value, state.cursor),
        else: state.cursor - 1

    {before, rest} = String.split_at(state.value, start)
    {_deleted, after_cursor} = String.split_at(rest, state.cursor - start)
    changed(%{state | value: before <> after_cursor, cursor: start})
  end

  defp delete_at_cursor(state) do
    value = state.value |> String.graphemes() |> List.delete_at(state.cursor) |> Enum.join()
    changed(%{state | value: value})
  end

  defp changed(state) do
    state = %{
      state
      | cursor: min(state.cursor, String.length(state.value)),
        selection: Selection.clear(state.selection)
    }

    {state, [{:changed, state.value}]}
  end

  defp grapheme_count(text), do: text |> String.graphemes() |> length()
  defp limit(graphemes, :infinity), do: graphemes

  defp limit(graphemes, count) when is_integer(count) and count > 0,
    do: Enum.take(graphemes, count)

  defp visible_before_cursor(graphemes, width) do
    Enum.reduce_while(Enum.reverse(graphemes), {[], 0}, fn grapheme, {visible, used} ->
      grapheme_width = Cell.width(Cell.new(grapheme))

      if used + grapheme_width <= width do
        {:cont, {[grapheme | visible], used + grapheme_width}}
      else
        {:halt, {visible, used}}
      end
    end)
  end

  defp take_width(graphemes, width) do
    graphemes
    |> Enum.reduce_while({[], 0}, fn grapheme, {visible, used} ->
      grapheme_width = Cell.width(Cell.new(grapheme))

      if used + grapheme_width <= width do
        {:cont, {[grapheme | visible], used + grapheme_width}}
      else
        {:halt, {visible, used}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp row_layout(%{value: ""} = state, width) do
    %{text: Frame.fit(state.placeholder, width), entries: [], cursor_column: 1, start: 0}
  end

  defp row_layout(state, width) do
    {before, after_cursor} = Enum.split(String.graphemes(state.value), state.cursor)
    {visible_before, before_width} = visible_before_cursor(before, width - 1)
    room = max(width - before_width, 0)
    visible_after = take_width(after_cursor, room)
    start = state.cursor - length(visible_before)
    visible = visible_before ++ visible_after

    %{
      text: Enum.join(visible),
      entries: Enum.with_index(visible, start),
      cursor_column: min(before_width + 1, width),
      start: start
    }
  end

  defp cursor_at(state, width, x) do
    layout = row_layout(state, width)
    x = Helpers.clamp(x, 0, width - 1)

    layout.entries
    |> Enum.reduce_while({layout.start, 0}, fn {grapheme, index}, {_position, column} ->
      grapheme_width = Cell.width(Cell.new(grapheme))

      if x < column + grapheme_width do
        {:halt, position_in_grapheme(index, grapheme_width, x - column)}
      else
        {:cont, {index + 1, column + grapheme_width}}
      end
    end)
    |> case do
      {position, _column} -> position
      position -> position
    end
  end

  defp style_at(state, index) do
    if Selection.contains?(state.selection, index),
      do: state.selection_style,
      else: Style.new()
  end

  defp position_in_grapheme(index, width, offset) when width > 1 and offset >= div(width, 2),
    do: index + 1

  defp position_in_grapheme(index, _width, _offset), do: index
end
