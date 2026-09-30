defmodule TermUI.Widget.Menu do
  @moduledoc """
  A pure menu with nested data and an explicit open path.

  `open_path` contains submenu IDs from the root to the active submenu. Right
  or Enter opens the current submenu. Left closes one submenu. Escape closes
  one submenu, or dismisses the root menu when no submenu is open.

  The `:variant` option changes the selected-item style. Use `:plain`, `:line`,
  or `:filled`. Use `fit_overlay/3` and `fit_submenu/3` when the parent places
  a menu relative to terminal edges.
  """

  @behaviour TermUI.Widget

  alias TermUI.{Event, Style}
  alias TermUI.Widget.Helpers

  @type item :: %{
          required(:id) => term(),
          required(:label) => String.t(),
          required(:kind) => :action | :submenu | :separator,
          required(:children) => [item()],
          optional(:disabled) => boolean(),
          optional(:separator) => boolean(),
          optional(:icon) => String.t() | nil,
          optional(:shortcut) => String.t() | nil,
          optional(:message) => term()
        }
  @type entry :: {item(), [term()], non_neg_integer(), non_neg_integer()}
  @type t :: %__MODULE__{
          items: [item()],
          cursor: non_neg_integer(),
          open_path: [term()],
          title: String.t() | nil,
          visible: boolean(),
          orientation: :vertical | :horizontal,
          variant: :plain | :line | :filled
        }

  defstruct items: [],
            cursor: 0,
            open_path: [],
            title: nil,
            visible: true,
            orientation: :vertical,
            variant: :plain

  @doc "Creates one menu action."
  @spec action(term(), iodata(), keyword()) :: item()
  def action(id, label, opts \\ []) do
    %{
      id: id,
      label: IO.iodata_to_binary(label),
      kind: :action,
      children: [],
      disabled: Keyword.get(opts, :disabled, false),
      separator: false,
      icon: Keyword.get(opts, :icon),
      shortcut:
        opts
        |> Keyword.get(:shortcut, Keyword.get(opts, :hotkey))
        |> normalize_decoration(),
      message: Keyword.get(opts, :message, {:selected, id})
    }
  end

  @doc "Creates one submenu with recursively normalized children."
  @spec submenu(term(), iodata(), [item() | term()], keyword()) :: item()
  def submenu(id, label, children, opts \\ []) when is_list(children) do
    %{
      id: id,
      label: IO.iodata_to_binary(label),
      kind: :submenu,
      children: Enum.map(children, &normalize_item/1),
      disabled: Keyword.get(opts, :disabled, false),
      separator: false,
      icon: Keyword.get(opts, :icon),
      shortcut:
        opts
        |> Keyword.get(:shortcut, Keyword.get(opts, :hotkey))
        |> normalize_decoration(),
      message: nil
    }
  end

  @doc "Creates one separator."
  @spec separator() :: item()
  def separator do
    %{
      id: make_ref(),
      label: "",
      kind: :separator,
      children: [],
      disabled: true,
      separator: true,
      icon: nil,
      shortcut: nil,
      message: nil
    }
  end

  @impl true
  def init(opts) do
    items = opts |> Keyword.get(:items, []) |> Enum.map(&normalize_item/1)

    %__MODULE__{
      items: items,
      cursor: first_enabled(items),
      title: Keyword.get(opts, :title),
      visible: Keyword.get(opts, :visible, true),
      orientation: Keyword.get(opts, :orientation, :vertical),
      variant: Keyword.get(opts, :variant, :plain)
    }
  end

  @impl true
  def update(_event, %{visible: false} = state), do: {state, []}

  def update(%Event.Key{key: :up}, %{open_path: [_first | _rest]} = state),
    do: move(state, -1)

  def update(%Event.Key{key: :down}, %{open_path: [_first | _rest]} = state),
    do: move(state, 1)

  def update(%Event.Key{key: :up}, %{orientation: :vertical} = state), do: move(state, -1)
  def update(%Event.Key{key: :down}, %{orientation: :vertical} = state), do: move(state, 1)

  def update(%Event.Key{key: :left}, %{open_path: [_first | _rest]} = state),
    do: {close_submenu(state), []}

  def update(%Event.Key{key: :right}, state) do
    case current(state) do
      %{kind: :submenu} -> open_current(state)
      _item when state.orientation == :horizontal and state.open_path == [] -> move(state, 1)
      _item -> {state, []}
    end
  end

  def update(%Event.Key{key: :left}, %{orientation: :horizontal} = state), do: move(state, -1)

  def update(%Event.Key{key: :down}, %{orientation: :horizontal} = state) do
    case current(state) do
      %{kind: :submenu} -> open_current(state)
      _item -> {state, []}
    end
  end

  def update(%Event.Key{key: :home}, state),
    do: {%{state | cursor: first_enabled(level_items(state))}, []}

  def update(%Event.Key{key: :end}, state),
    do: {%{state | cursor: last_enabled(level_items(state))}, []}

  def update(%Event.Key{key: key}, state) when key in [:enter, :space], do: activate(state)
  def update(%Event.Text{text: " "}, state), do: activate(state)

  def update(%Event.Key{key: :escape}, %{open_path: [_first | _rest]} = state),
    do: {close_submenu(state), []}

  def update(%Event.Key{key: :escape}, state),
    do: {%{state | visible: false, open_path: []}, [:dismissed]}

  def update(_event, state), do: {state, []}

  @impl true
  def mouse(_event, %{visible: false} = state, _dimensions), do: {state, []}

  def mouse(%Event.Mouse{action: action, button: :left, x: x, y: y}, state, dimensions)
      when action in [:press, :release] do
    state
    |> entry_at({x, y}, dimensions)
    |> mouse_entry(state, action)
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(%{visible: false}, dimensions), do: Helpers.frame([], dimensions)

  def view(state, {width, height} = dimensions) do
    cursor_style = cursor_style(state.variant)
    disabled_style = Style.new(fg: :bright_black)
    separator_style = Style.new(fg: :bright_black)
    inner_width = max(width - 2, 1)

    rows =
      case state.orientation do
        :vertical ->
          Enum.map(
            visible_entries(state),
            &render_vertical_entry(
              &1,
              state,
              inner_width,
              cursor_style,
              disabled_style,
              separator_style
            )
          )

        :horizontal ->
          [
            state.items
            |> Enum.with_index()
            |> Enum.flat_map(
              &render_horizontal_item(
                &1,
                state,
                cursor_style,
                disabled_style,
                separator_style
              )
            )
            |> Enum.drop(-1)
          ] ++
            Enum.map(
              descendant_entries(state),
              &render_vertical_entry(
                &1,
                state,
                inner_width,
                cursor_style,
                disabled_style,
                separator_style
              )
            )
      end

    rows = Helpers.border(rows, dimensions, title: state.title)
    Helpers.frame(Enum.take(rows, height), dimensions)
  end

  @doc "Shows the menu."
  @spec show(t()) :: t()
  def show(state), do: %{state | visible: true}

  @doc "Hides the menu and closes every submenu."
  @spec hide(t()) :: t()
  def hide(state), do: %{state | visible: false, open_path: []}

  @doc "Returns the current action or submenu in the active menu level."
  @spec current(t()) :: item() | nil
  def current(state), do: Enum.at(level_items(state), state.cursor)

  @doc "Returns the open submenu IDs from the root to the active level."
  @spec open_path(t()) :: [term()]
  def open_path(state), do: state.open_path

  @doc "Opens the current submenu when it has an enabled child."
  @spec open_submenu(t()) :: t()
  def open_submenu(state) do
    case open_current(state) do
      {state, _messages} -> state
    end
  end

  @doc "Closes the deepest submenu and restores focus to its parent item."
  @spec close_submenu(t()) :: t()
  def close_submenu(%{open_path: []} = state), do: state

  def close_submenu(state) do
    closed_id = List.last(state.open_path)
    parent_path = Enum.drop(state.open_path, -1)
    parent_items = level_items(state, parent_path)
    cursor = Enum.find_index(parent_items, &(&1.id == closed_id)) || first_enabled(parent_items)
    %{state | open_path: parent_path, cursor: cursor}
  end

  @doc "Closes every submenu but keeps the root menu visible."
  @spec close_all(t()) :: t()
  def close_all(state), do: %{state | open_path: [], cursor: first_enabled(state.items)}

  @doc "Fits one overlay rectangle inside terminal dimensions."
  @spec fit_overlay(
          {integer(), integer()},
          {non_neg_integer(), non_neg_integer()},
          {non_neg_integer(), non_neg_integer()}
        ) :: TermUI.Layout.rect()
  def fit_overlay({x, y} = position, {width, height} = dimensions, terminal_dimensions) do
    validate_position!(position)
    validate_dimensions!(dimensions)
    validate_dimensions!(terminal_dimensions)
    {terminal_width, terminal_height} = terminal_dimensions
    clipped_width = min(width, terminal_width)
    clipped_height = min(height, terminal_height)
    fitted_x = Helpers.clamp(x, 0, max(terminal_width - clipped_width, 0))
    fitted_y = Helpers.clamp(y, 0, max(terminal_height - clipped_height, 0))
    {fitted_x, fitted_y, clipped_width, clipped_height}
  end

  @doc "Places a submenu to the right, or to the left when the right edge is full."
  @spec fit_submenu(
          TermUI.Layout.rect(),
          {non_neg_integer(), non_neg_integer()},
          {non_neg_integer(), non_neg_integer()}
        ) :: TermUI.Layout.rect()
  def fit_submenu(
        {parent_x, parent_y, parent_width, _parent_height},
        {width, height},
        {terminal_width, _terminal_height} = terminal_dimensions
      ) do
    right_x = parent_x + parent_width

    requested_x =
      cond do
        right_x + width <= terminal_width -> right_x
        parent_x - width >= 0 -> parent_x - width
        true -> right_x
      end

    fit_overlay({requested_x, parent_y}, {width, height}, terminal_dimensions)
  end

  defp activate(state) do
    case current(state) do
      %{kind: :submenu} -> open_current(state)
      %{disabled: false, separator: false, message: message} -> {state, [message]}
      _other -> {state, []}
    end
  end

  defp open_current(state) do
    case current(state) do
      %{kind: :submenu, disabled: false, children: children, id: id} when children != [] ->
        {%{state | open_path: state.open_path ++ [id], cursor: first_enabled(children)}, []}

      _item ->
        {state, []}
    end
  end

  defp move(%{items: []} = state, _delta), do: {state, []}

  defp move(state, delta) do
    items = level_items(state)
    count = length(items)

    cursor =
      1..max(count, 1)
      |> Enum.reduce_while(state.cursor, fn step, _cursor ->
        candidate = rem(state.cursor + delta * step + count * step, count)

        if enabled?(Enum.at(items, candidate)),
          do: {:halt, candidate},
          else: {:cont, state.cursor}
      end)

    {%{state | cursor: cursor}, []}
  end

  defp enabled?(%{disabled: false, separator: false}), do: true
  defp enabled?(_item), do: false
  defp first_enabled(items), do: Enum.find_index(items, &enabled?/1) || 0

  defp last_enabled(items) do
    items
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(0, fn {item, index} -> if enabled?(item), do: index end)
  end

  defp level_items(state), do: level_items(state, state.open_path)
  defp level_items(state, []), do: state.items

  defp level_items(state, path) do
    Enum.reduce_while(path, state.items, fn id, items ->
      case Enum.find(items, &(&1.id == id and &1.kind == :submenu)) do
        nil -> {:halt, []}
        item -> {:cont, item.children}
      end
    end)
  end

  defp visible_entries(state), do: visible_entries(state.items, [], state.open_path, 0)

  defp visible_entries(items, path, open_path, depth) do
    items
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} ->
      entry = {item, path, index, depth}
      child_path = path ++ [item.id]

      if item.kind == :submenu and List.starts_with?(open_path, child_path),
        do: [entry | visible_entries(item.children, child_path, open_path, depth + 1)],
        else: [entry]
    end)
  end

  defp descendant_entries(state) do
    state
    |> visible_entries()
    |> Enum.reject(fn {_item, path, _index, _depth} -> path == [] end)
  end

  defp render_vertical_entry(
         {%{separator: true}, _path, _index, depth},
         _state,
         width,
         _cursor_style,
         _disabled_style,
         separator_style
       ) do
    indent = String.duplicate("  ", depth)
    line = indent <> String.duplicate("─", max(width - Helpers.text_width(indent), 0))
    [{Helpers.align(line, width, :left), separator_style}]
  end

  defp render_vertical_entry(
         {item, path, index, depth},
         state,
         width,
         cursor_style,
         disabled_style,
         _separator_style
       ) do
    shortcut = if item.shortcut, do: " " <> item.shortcut, else: ""
    prefix = String.duplicate("  ", depth) <> item_prefix(item, path, state.open_path)
    label_width = max(width - Helpers.text_width(shortcut) - Helpers.text_width(prefix), 1)
    text = prefix <> Helpers.align(item.label, label_width, :left) <> shortcut

    style =
      cond do
        item.disabled -> disabled_style
        path == state.open_path and index == state.cursor -> cursor_style
        true -> Style.new()
      end

    [{text, style}]
  end

  defp render_horizontal_item(
         {%{separator: true}, _index},
         _state,
         _cursor_style,
         _disabled_style,
         separator_style
       ),
       do: [{"│", separator_style}, " "]

  defp render_horizontal_item(
         {item, index},
         state,
         cursor_style,
         disabled_style,
         _separator_style
       ) do
    style =
      cond do
        item.disabled -> disabled_style
        state.open_path == [] and index == state.cursor -> cursor_style
        List.first(state.open_path) == item.id -> cursor_style
        true -> Style.new()
      end

    [{horizontal_item_text(item, [], state.open_path), style}, "  "]
  end

  defp item_prefix(%{kind: :submenu} = item, path, open_path) do
    marker = if List.starts_with?(open_path, path ++ [item.id]), do: "▾ ", else: "▸ "
    marker <> icon_prefix(item)
  end

  defp item_prefix(item, _path, _open_path), do: "  " <> icon_prefix(item)

  defp icon_prefix(item) do
    case Map.get(item, :icon) do
      nil -> ""
      "" -> ""
      icon -> to_string(icon) <> " "
    end
  end

  defp horizontal_item_text(%{separator: true}, _path, _open_path), do: "│"

  defp horizontal_item_text(item, path, open_path) do
    shortcut = if item.shortcut, do: " " <> item.shortcut, else: ""
    " " <> horizontal_prefix(item, path, open_path) <> item.label <> shortcut <> " "
  end

  defp horizontal_prefix(%{kind: :submenu} = item, path, open_path),
    do: item_prefix(item, path, open_path)

  defp horizontal_prefix(item, _path, _open_path), do: icon_prefix(item)

  defp mouse_entry(
         {%{disabled: false, separator: false}, path, index, _depth},
         state,
         :release
       ) do
    activate(%{state | open_path: path, cursor: index})
  end

  defp mouse_entry(
         {%{disabled: false, separator: false}, path, index, _depth},
         state,
         :press
       ),
       do: {%{state | open_path: path, cursor: index}, []}

  defp mouse_entry(_entry, state, _action), do: {state, []}

  defp entry_at(state, {x, y}, {width, height}) do
    border_offset = if width > 1 and height > 1, do: 1, else: 0

    if inside_menu?(x, y, width, height, border_offset),
      do: entry_at_position(state, x, y, border_offset),
      else: nil
  end

  defp inside_menu?(x, y, width, height, border_offset),
    do:
      x >= border_offset and x < width - border_offset and y >= border_offset and
        y < height - border_offset

  defp entry_at_position(%{orientation: :horizontal} = state, x, border_offset, border_offset),
    do: horizontal_entry_at(state.items, x - border_offset, state.open_path)

  defp entry_at_position(%{orientation: :horizontal} = state, _x, y, border_offset),
    do: Enum.at(descendant_entries(state), y - border_offset - 1)

  defp entry_at_position(state, _x, y, border_offset),
    do: Enum.at(visible_entries(state), y - border_offset)

  defp horizontal_entry_at(items, x, open_path) when x >= 0 do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:after, 0}, fn {item, index}, {:after, start} ->
      finish = start + Helpers.text_width(horizontal_item_text(item, [], open_path))

      if x >= start and x < finish,
        do: {:halt, {item, [], index, 0}},
        else: {:cont, {:after, finish + horizontal_item_gap(item)}}
    end)
    |> case do
      {:after, _position} -> nil
      entry -> entry
    end
  end

  defp horizontal_entry_at(_items, _x, _open_path), do: nil
  defp horizontal_item_gap(%{separator: true}), do: 1
  defp horizontal_item_gap(_item), do: 2

  defp normalize_item(%{separator: true}), do: separator()

  defp normalize_item(%{kind: :action, id: _id, label: label} = item),
    do: action(item.id, label, Map.to_list(Map.drop(item, [:id, :label, :kind, :children])))

  defp normalize_item(%{kind: :submenu, id: id, label: label, children: children} = item),
    do: submenu(id, label, children, Map.to_list(Map.drop(item, [:id, :label, :children, :kind])))

  defp normalize_item(%{id: id, label: label, children: children} = item)
       when is_list(children) do
    submenu(id, label, children, Map.to_list(Map.drop(item, [:id, :label, :children, :kind])))
  end

  defp normalize_item(%{id: _id, label: label} = item),
    do: action(item.id, label, Map.to_list(Map.drop(item, [:id, :label, :kind, :children])))

  defp normalize_item({id, label}), do: action(id, label)
  defp normalize_item(label), do: action(label, label)

  defp cursor_style(:plain), do: Style.new(attrs: [:reverse])
  defp cursor_style(:line), do: Style.new(fg: :cyan, attrs: [:bold, :underline])
  defp cursor_style(:filled), do: Style.new(fg: :black, bg: :cyan, attrs: [:bold])

  defp normalize_decoration(nil), do: nil
  defp normalize_decoration(value) when is_list(value), do: IO.iodata_to_binary(value)
  defp normalize_decoration(value), do: to_string(value)

  defp validate_position!({x, y}) when is_integer(x) and is_integer(y), do: :ok

  defp validate_position!(position),
    do: raise(ArgumentError, "invalid menu position: #{inspect(position)}")

  defp validate_dimensions!({width, height})
       when is_integer(width) and width >= 0 and is_integer(height) and height >= 0,
       do: :ok

  defp validate_dimensions!(dimensions),
    do: raise(ArgumentError, "invalid menu dimensions: #{inspect(dimensions)}")
end
