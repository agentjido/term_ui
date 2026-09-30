defmodule TermUI.Widget.Table do
  @moduledoc """
  A pure table with sorting, filtering, scrolling, and row selection.

  The parent owns the complete table state. Sorting and filtering run only
  when the parent changes that state. `view/2` only converts state to a frame.

  ## Row identity

  Selection uses row identities, not row positions. Pass `:row_id` as a map
  key, a list or tuple index, or a one-argument function when rows can change:

      Table.init(rows: users, columns: columns, row_id: :id)
      Table.init(rows: rows, columns: columns, row_id: & &1.account_id)

  Each row identity must be unique. It must also stay the same when the row
  moves, its other values change, or a filter hides it. If `:row_id` is not
  set, the complete row value is its identity. That default is suitable only
  for unique rows whose values do not change.

  ## Selection

  `:selection_mode` can be `:none`, `:single`, or `:multiple`. `:multi` is an
  accepted alias for `:multiple`. Enter selects the cursor row. Space toggles
  it in multiple mode. A left-button release applies the same selection rule.
  """

  @behaviour TermUI.Widget

  alias TermUI.{Event, Style}
  alias TermUI.Widget.Helpers
  alias TermUI.Widget.Table.Column

  # Styled table spans contain MapSet's opaque representation through Style.t().
  @dialyzer {:nowarn_function, view: 2, render_cells: 4, set_selection: 2, clear_selection: 1}

  @type selection_mode :: :none | :single | :multiple
  @type sort_direction :: :asc | :desc | nil
  @type row_id_resolver :: nil | term() | (term() -> term())
  @type row_filter :: nil | (term() -> as_boolean(term()))

  @type t :: %__MODULE__{
          columns: [Column.t()],
          rows: [term()],
          display_rows: [term()],
          cursor: non_neg_integer(),
          offset: non_neg_integer(),
          page_size: pos_integer(),
          show_header: boolean(),
          row_id: row_id_resolver(),
          selection_mode: selection_mode(),
          selected: MapSet.t(term()),
          sort_column: term() | nil,
          sort_direction: sort_direction(),
          filter: row_filter()
        }

  defstruct columns: [],
            rows: [],
            display_rows: [],
            cursor: 0,
            offset: 0,
            page_size: 10,
            show_header: true,
            row_id: nil,
            selection_mode: :single,
            selected: MapSet.new(),
            sort_column: nil,
            sort_direction: nil,
            filter: nil

  @impl true
  def init(opts) do
    state = %__MODULE__{
      columns: opts |> Keyword.get(:columns, []) |> Enum.map(&normalize_column/1),
      rows: Keyword.get(opts, :rows, []),
      page_size: max(Keyword.get(opts, :page_size, 10), 1),
      show_header: Keyword.get(opts, :show_header, true),
      row_id: Keyword.get(opts, :row_id),
      selection_mode: opts |> Keyword.get(:selection_mode, :single) |> normalize_selection_mode(),
      filter: Keyword.get(opts, :filter)
    }

    validate_filter!(state.filter)
    ensure_unique_identities!(state)
    refresh_display(state, nil)
  end

  @impl true
  def update(%Event.Key{key: :up}, state), do: move(state, -1)
  def update(%Event.Key{key: :down}, state), do: move(state, 1)
  def update(%Event.Key{key: :home}, state), do: move_to(state, 0)
  def update(%Event.Key{key: :end}, state), do: move_to(state, length(state.display_rows) - 1)
  def update(%Event.Key{key: :page_up}, state), do: move(state, -state.page_size)
  def update(%Event.Key{key: :page_down}, state), do: move(state, state.page_size)
  def update(%Event.Key{key: :enter}, state), do: select_cursor(state)

  def update(%Event.Text{text: " "}, %{selection_mode: :multiple} = state),
    do: select_cursor(state)

  def update(_event, state), do: {state, []}

  @impl true
  def mouse(%Event.Mouse{action: action, button: :left, y: y}, state, {_width, height})
      when action in [:press, :release] do
    header_height = if state.show_header, do: 1, else: 0
    body_height = max(height - header_height, 0)
    offset = visible_offset(state.cursor, state.offset, body_height)
    index = offset + y - header_height

    if y >= header_height and y < height and index < length(state.display_rows) do
      state = %{state | cursor: index, offset: offset}

      if action == :release, do: select_cursor(state), else: {state, []}
    else
      {state, []}
    end
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {width, height} = dimensions) do
    widths = column_widths(state.columns, width)
    header_height = if state.show_header, do: 1, else: 0
    body_height = max(height - header_height, 0)
    offset = visible_offset(state.cursor, state.offset, body_height)
    header_style = Style.new(fg: :cyan, attrs: [:bold, :underline])
    cursor_style = Style.new(attrs: [:reverse])
    selected_style = Style.new(fg: :cyan, attrs: [:bold])

    header =
      if state.show_header,
        do: [render_cells(header_values(state), state.columns, widths, header_style)],
        else: []

    body =
      state.display_rows
      |> Enum.slice(offset, body_height)
      |> Enum.with_index(offset)
      |> Enum.map(fn {row, index} ->
        values = Enum.map(state.columns, &cell_value(row, &1.key))

        style =
          cond do
            index == state.cursor -> cursor_style
            MapSet.member?(state.selected, row_identity(state, row)) -> selected_style
            true -> Style.new()
          end

        render_cells(values, state.columns, widths, style)
      end)

    Helpers.frame(header ++ body, dimensions)
  end

  @doc "Replaces all rows and keeps selection for identities that still exist."
  @spec set_rows(t(), [term()]) :: t()
  def set_rows(state, rows) when is_list(rows) do
    cursor_id = cursor_identity(state)
    state = %{state | rows: rows}
    ensure_unique_identities!(state)
    valid_ids = rows |> Enum.map(&row_identity(state, &1)) |> MapSet.new()
    state = %{state | selected: MapSet.intersection(state.selected, valid_ids)}
    refresh_display(state, cursor_id)
  end

  @doc "Sets or clears the row filter and keeps hidden row selections."
  @spec set_filter(t(), row_filter()) :: t()
  def set_filter(state, filter) do
    validate_filter!(filter)
    refresh_display(%{state | filter: filter}, cursor_identity(state))
  end

  @doc "Sorts by a column. A nil direction restores source row order."
  @spec sort_by(t(), term(), sort_direction()) :: t()
  def sort_by(state, _column, nil) do
    refresh_display(%{state | sort_column: nil, sort_direction: nil}, cursor_identity(state))
  end

  def sort_by(state, column, direction) when direction in [:asc, :desc] do
    refresh_display(
      %{state | sort_column: column, sort_direction: direction},
      cursor_identity(state)
    )
  end

  @doc "Cycles a column through ascending, descending, and source order."
  @spec toggle_sort(t(), term()) :: t()
  def toggle_sort(state, column) do
    case {state.sort_column, state.sort_direction} do
      {^column, :asc} -> sort_by(state, column, :desc)
      {^column, :desc} -> sort_by(state, column, nil)
      _other -> sort_by(state, column, :asc)
    end
  end

  @doc "Returns rows after the current filter and sort are applied."
  @spec display_rows(t()) :: [term()]
  def display_rows(state), do: state.display_rows

  @doc "Returns selected identities."
  @spec selected_ids(t()) :: MapSet.t(term())
  def selected_ids(state), do: state.selected

  @doc "Returns selected rows in source order, including rows hidden by a filter."
  @spec selected_rows(t()) :: [term()]
  def selected_rows(state) do
    Enum.filter(state.rows, &MapSet.member?(state.selected, row_identity(state, &1)))
  end

  @doc "Sets selected identities and removes identities that are not in the table."
  @spec set_selection(t(), Enumerable.t()) :: t()
  def set_selection(state, identities) do
    valid_ids = state.rows |> Enum.map(&row_identity(state, &1)) |> MapSet.new()
    selected = identities |> MapSet.new() |> MapSet.intersection(valid_ids)

    selected =
      case state.selection_mode do
        :none -> MapSet.new()
        :single -> selected |> Enum.take(1) |> MapSet.new()
        :multiple -> selected
      end

    %{state | selected: selected}
  end

  @doc "Clears the selection."
  @spec clear_selection(t()) :: t()
  def clear_selection(state), do: %{state | selected: MapSet.new()}

  defp select_cursor(%{selection_mode: :none} = state), do: {state, []}

  defp select_cursor(state) do
    case Enum.at(state.display_rows, state.cursor) do
      nil ->
        {state, []}

      row ->
        identity = row_identity(state, row)

        case state.selection_mode do
          :single ->
            {%{state | selected: MapSet.new([identity])}, [{:selected, row}]}

          :multiple ->
            selected = toggle_identity(state.selected, identity)
            state = %{state | selected: selected}
            {state, [{:selection_changed, selected_rows(state)}]}
        end
    end
  end

  defp toggle_identity(selected, identity) do
    if MapSet.member?(selected, identity),
      do: MapSet.delete(selected, identity),
      else: MapSet.put(selected, identity)
  end

  defp move(state, delta), do: move_to(state, state.cursor + delta)

  defp move_to(state, cursor) do
    cursor = Helpers.clamp(cursor, 0, max(length(state.display_rows) - 1, 0))
    offset = visible_offset(cursor, state.offset, state.page_size)
    {%{state | cursor: cursor, offset: offset}, []}
  end

  defp refresh_display(state, cursor_id) do
    display_rows =
      state.rows
      |> filter_rows(state.filter)
      |> sort_rows(state.sort_column, state.sort_direction)

    cursor = cursor_for(display_rows, state, cursor_id)
    max_offset = max(length(display_rows) - state.page_size, 0)
    offset = state.offset |> min(max_offset) |> visible_offset_for(cursor, state.page_size)
    %{state | display_rows: display_rows, cursor: cursor, offset: offset}
  end

  defp filter_rows(rows, nil), do: rows
  defp filter_rows(rows, filter), do: Enum.filter(rows, filter)

  defp sort_rows(rows, _column, nil), do: rows

  defp sort_rows(rows, column, direction) do
    rows
    |> Enum.with_index()
    |> Enum.sort(fn {left, left_index}, {right, right_index} ->
      left_value = cell_value(left, column)
      right_value = cell_value(right, column)

      case direction do
        :asc ->
          left_value < right_value or (left_value == right_value and left_index <= right_index)

        :desc ->
          left_value > right_value or (left_value == right_value and left_index <= right_index)
      end
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp cursor_for([], _state, _cursor_id), do: 0
  defp cursor_for(rows, state, nil), do: min(state.cursor, length(rows) - 1)

  defp cursor_for(rows, state, cursor_id) do
    Enum.find_index(rows, &(row_identity(state, &1) == cursor_id)) ||
      min(state.cursor, length(rows) - 1)
  end

  defp cursor_identity(state) do
    case Enum.at(state.display_rows, state.cursor) do
      nil -> nil
      row -> row_identity(state, row)
    end
  end

  defp row_identity(%{row_id: nil}, row), do: row
  defp row_identity(%{row_id: resolver}, row) when is_function(resolver, 1), do: resolver.(row)
  defp row_identity(%{row_id: key}, row), do: cell_value(row, key)

  defp ensure_unique_identities!(state) do
    identities = Enum.map(state.rows, &row_identity(state, &1))

    if MapSet.size(MapSet.new(identities)) != length(identities) do
      raise ArgumentError, "table row identities must be unique"
    end
  end

  defp validate_filter!(nil), do: :ok
  defp validate_filter!(filter) when is_function(filter, 1), do: :ok

  defp validate_filter!(_filter),
    do: raise(ArgumentError, "table filter must be a function of arity 1")

  defp normalize_selection_mode(:multi), do: :multiple
  defp normalize_selection_mode(mode) when mode in [:none, :single, :multiple], do: mode

  defp normalize_selection_mode(mode) do
    raise ArgumentError,
          "table selection_mode must be :none, :single, :multiple, or :multi; got: #{inspect(mode)}"
  end

  defp visible_offset(_cursor, offset, 0), do: offset
  defp visible_offset(cursor, offset, _height) when cursor < offset, do: cursor

  defp visible_offset(cursor, offset, height) when cursor >= offset + height,
    do: cursor - height + 1

  defp visible_offset(_cursor, offset, _height), do: offset

  defp visible_offset_for(offset, cursor, height), do: visible_offset(cursor, offset, height)

  defp header_values(state) do
    Enum.map(state.columns, fn column ->
      case {state.sort_column == column.key, state.sort_direction} do
        {true, :asc} -> column.label <> " ↑"
        {true, :desc} -> column.label <> " ↓"
        _other -> column.label
      end
    end)
  end

  defp render_cells(values, columns, widths, style) do
    values
    |> Enum.zip(columns)
    |> Enum.zip(widths)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{{value, column}, cell_width}, index} ->
      separator = if index == length(widths) - 1, do: "", else: " │ "

      [
        {Helpers.align(display_value(value), cell_width, column.align), style},
        {separator, Style.new(fg: :bright_black)}
      ]
    end)
  end

  defp column_widths(columns, width) do
    separators = max(length(columns) - 1, 0) * 3
    available = max(width - separators, length(columns))

    fixed =
      Enum.reduce(columns, 0, fn
        %{width: column_width}, sum when is_integer(column_width) -> sum + column_width
        _, sum -> sum
      end)

    automatic = Enum.count(columns, &(&1.width == :auto))

    auto_width =
      if automatic > 0, do: max(div(max(available - fixed, automatic), automatic), 1), else: 1

    Enum.map(columns, fn %{width: column_width} ->
      if is_integer(column_width), do: column_width, else: auto_width
    end)
  end

  defp cell_value(row, key) when is_map(row) do
    case Map.fetch(row, key) do
      {:ok, value} -> value
      :error -> string_key_value(row, key)
    end
  end

  defp cell_value(row, key) when is_list(row) and is_integer(key), do: Enum.at(row, key)

  defp cell_value(row, key)
       when is_tuple(row) and is_integer(key) and key >= 0 and key < tuple_size(row),
       do: elem(row, key)

  defp cell_value(_row, _key), do: nil

  defp string_key_value(row, key) when is_atom(key) or is_integer(key) or is_binary(key),
    do: Map.get(row, to_string(key))

  defp string_key_value(_row, _key), do: nil

  defp display_value(nil), do: ""

  defp display_value(value) do
    if String.Chars.impl_for(value), do: to_string(value), else: inspect(value)
  end

  defp normalize_column(%Column{} = column), do: column
  defp normalize_column({key, label}), do: Column.new(key, label)
  defp normalize_column(key), do: Column.new(key, to_string(key))
end
