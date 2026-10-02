defmodule TermUI.Widget.TextArea do
  @moduledoc """
  A pure multiline Unicode text editor with automatic cursor scrolling.

  `init/1` accepts `:value`, `:placeholder`, `:max_length`, and
  `:selection_style`. Text and paste events replace the selected grapheme
  range. Ctrl+Enter emits `{:submit, value}`. Other edits emit
  `{:changed, value}`.

  Shift with navigation keys changes the selection. Ctrl+A selects all text.
  Ctrl+C returns `{:copy, text}`. Ctrl+X also removes the selection. Mouse
  press and drag use zero-based local coordinates from `mouse/3`.

  Alt+Backspace (Option+Delete on macOS) removes trailing spaces and the
  preceding word on the current line. It preserves line breaks. An active
  selection is removed first.
  """

  @behaviour TermUI.Widget

  alias TermUI.{DisplayWidth, Event, Frame, Selection, Style}
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
    if :ctrl in modifiers,
      do: {%{state | selection: Selection.select_all(state.selection, state.value)}, []},
      else: {state, []}
  end

  def update(%Event.Key{key: "c", modifiers: modifiers}, state) do
    if :ctrl in modifiers, do: copy_selection(state), else: {state, []}
  end

  def update(%Event.Key{key: "x", modifiers: modifiers}, state) do
    if :ctrl in modifiers, do: cut_selection(state), else: {state, []}
  end

  def update(%Event.Key{key: :enter, modifiers: modifiers}, state) do
    if :ctrl in modifiers, do: {state, [{:submit, state.value}]}, else: insert(state, "\n")
  end

  def update(%Event.Key{key: :left, modifiers: modifiers}, state),
    do: horizontal(state, -1, modifiers)

  def update(%Event.Key{key: :right, modifiers: modifiers}, state),
    do: horizontal(state, 1, modifiers)

  def update(%Event.Key{key: :home, modifiers: modifiers}, state),
    do: navigate(state, line_start(state), modifiers)

  def update(%Event.Key{key: :end, modifiers: modifiers}, state),
    do: navigate(state, line_end(state), modifiers)

  def update(%Event.Key{key: :up, modifiers: modifiers}, state),
    do: navigate(state, vertical(state, -1), modifiers)

  def update(%Event.Key{key: :down, modifiers: modifiers}, state),
    do: navigate(state, vertical(state, 1), modifiers)

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
      state.cursor < count(state.value) -> delete_at_cursor(state)
      true -> {state, []}
    end
  end

  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, height}) do
    text =
      if state.value == "" and state.placeholder != "", do: state.placeholder, else: state.value

    rows = Frame.wrap(text, width)
    layout = text_layout(state.value, width)
    {cursor_column, cursor_row} = Map.fetch!(layout.cursors, state.cursor)
    rows = rows ++ List.duplicate("", max(cursor_row - length(rows), 0))
    offset = max(cursor_row - height, 0)
    visible = Enum.slice(rows, offset, height)

    visible
    |> Frame.from_rows(width, height, cursor: {cursor_column, cursor_row - offset})
    |> apply_selection(state, layout, offset)
  end

  @impl true
  def mouse(%Event.Mouse{action: :press, button: :left, modifiers: modifiers} = event, state, {
        width,
        height
      }) do
    position = cursor_at(state, width, height, event.x, event.y)

    selection =
      if :shift in modifiers and Selection.active?(state.selection),
        do: Selection.extend(state.selection, position),
        else: Selection.start(state.selection, position)

    {%{state | cursor: position, selection: selection}, []}
  end

  def mouse(%Event.Mouse{action: :drag, button: :left} = event, state, {width, height}) do
    position = cursor_at(state, width, height, event.x, event.y)

    selection =
      if Selection.active?(state.selection),
        do: Selection.extend(state.selection, position),
        else: state.selection |> Selection.start(state.cursor) |> Selection.extend(position)

    {%{state | cursor: position, selection: selection}, []}
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @doc "Returns the current value."
  @spec value(t()) :: String.t()
  def value(state), do: state.value

  @doc "Replaces the current value and moves the cursor to the end."
  @spec set_value(t(), String.t()) :: t()
  def set_value(state, value),
    do: %{state | value: value, cursor: count(value), selection: Selection.clear(state.selection)}

  defp insert(state, text) do
    inserted =
      text
      |> String.replace("\r\n", "\n")
      |> String.replace("\r", "\n")
      |> String.replace("\t", "  ")
      |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u, "")

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
    target = Helpers.clamp(target, 0, count(state.value))

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

    if start == state.cursor do
      {state, []}
    else
      {before, rest} = String.split_at(state.value, start)
      {_deleted, after_cursor} = String.split_at(rest, state.cursor - start)
      changed(%{state | value: before <> after_cursor, cursor: start})
    end
  end

  defp delete_at_cursor(state) do
    value = state.value |> String.graphemes() |> List.delete_at(state.cursor) |> Enum.join()
    changed(%{state | value: value})
  end

  defp changed(state) do
    state = %{state | cursor: min(state.cursor, String.length(state.value))}
    {state, [{:changed, state.value}]}
  end

  defp count(text), do: text |> String.graphemes() |> length()
  defp limit(graphemes, :infinity), do: graphemes
  defp limit(graphemes, maximum), do: Enum.take(graphemes, maximum)

  defp line_start(state) do
    before = Enum.take(String.graphemes(state.value), state.cursor)

    case Enum.find_index(Enum.reverse(before), &(&1 == "\n")) do
      nil -> 0
      distance -> state.cursor - distance
    end
  end

  defp line_end(state) do
    after_cursor = Enum.drop(String.graphemes(state.value), state.cursor)

    case Enum.find_index(after_cursor, &(&1 == "\n")) do
      nil -> count(state.value)
      distance -> state.cursor + distance
    end
  end

  defp vertical(state, delta) do
    lines = String.split(state.value, "\n", trim: false)
    before = Enum.take(String.graphemes(state.value), state.cursor) |> Enum.join()
    row = before |> String.split("\n", trim: false) |> length() |> Kernel.-(1)

    column =
      before |> String.split("\n", trim: false) |> List.last() |> String.graphemes() |> length()

    target_row = Helpers.clamp(row + delta, 0, length(lines) - 1)
    prefix = lines |> Enum.take(target_row) |> Enum.map(&(count(&1) + 1)) |> Enum.sum()
    prefix + min(column, lines |> Enum.at(target_row) |> count())
  end

  defp text_layout(text, width) do
    text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reduce(
      %{cursors: %{0 => {1, 1}}, cells: [], column: 1, row: 1, soft_wrapped: false},
      fn
        {"\n", index}, layout ->
          next_row = if layout.soft_wrapped, do: layout.row, else: layout.row + 1
          next = {1, next_row}

          %{
            layout
            | cursors: Map.put(layout.cursors, index + 1, next),
              column: 1,
              row: next_row,
              soft_wrapped: false
          }

        {grapheme, index}, layout ->
          grapheme_width = max(DisplayWidth.width(grapheme), 1)

          {column, row} =
            if layout.column > 1 and layout.column - 1 + grapheme_width > width,
              do: {1, layout.row + 1},
              else: {layout.column, layout.row}

          next =
            if column + grapheme_width > width,
              do: {1, row + 1},
              else: {column + grapheme_width, row}

          %{
            layout
            | cursors: Map.put(layout.cursors, index + 1, next),
              cells: [{index, grapheme, column, row} | layout.cells],
              column: elem(next, 0),
              row: elem(next, 1),
              soft_wrapped: elem(next, 1) > row
          }
      end
    )
    |> Map.update!(:cells, &Enum.reverse/1)
  end

  defp apply_selection(frame, state, layout, offset) do
    if Selection.empty?(state.selection) do
      frame
    else
      Enum.reduce(layout.cells, frame, &put_selected_cell(&1, &2, state, offset))
    end
  end

  defp put_selected_cell({index, grapheme, column, row}, frame, state, offset) do
    visible_row = row - offset

    if Selection.contains?(state.selection, index) and visible_row >= 1 and
         visible_row <= frame.height do
      Frame.put_cell(
        frame,
        visible_row,
        column,
        Style.to_cell(state.selection_style, grapheme)
      )
    else
      frame
    end
  end

  defp cursor_at(state, width, height, x, y) do
    layout = text_layout(state.value, width)
    {_cursor_column, cursor_row} = Map.fetch!(layout.cursors, state.cursor)
    offset = max(cursor_row - height, 0)
    target_row = offset + max(y, 0) + 1
    target_column = max(x, 0) + 1

    points =
      layout.cursors
      |> Enum.filter(fn {_index, {_column, row}} -> row == target_row end)

    case points do
      [] ->
        if target_row <= 1, do: 0, else: count(state.value)

      candidates ->
        candidates
        |> Enum.min_by(fn {index, {column, _row}} -> {abs(column - target_column), index} end)
        |> elem(0)
    end
  end
end
