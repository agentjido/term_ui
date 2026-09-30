defmodule TermUI.Widget.DiffViewer do
  @moduledoc """
  A pure scrollable text diff viewer.

  Initialize it with `:before` and `:after` text, or with a prebuilt
  `:unified_diff`. The viewer supports `:unified` and `:split` modes. Press
  `s` to switch modes. Arrow, Page Up, Page Down, Home, End, and mouse-wheel
  events control scrolling.
  """

  @behaviour TermUI.Widget

  # Styled spans contain MapSet's opaque representation through Style.t().
  @dialyzer {:nowarn_function, split_cell: 4}

  alias TermUI.{Event, Frame, Style}
  alias TermUI.Widget.Helpers

  @type row :: %{
          kind: :context | :added | :removed | :changed | :hunk | :header | :fold,
          old_number: pos_integer() | nil,
          new_number: pos_integer() | nil,
          old_text: String.t() | nil,
          new_text: String.t() | nil,
          text: String.t() | nil
        }

  @type t :: %__MODULE__{
          rows: [row()],
          mode: :unified | :split,
          scroll: non_neg_integer() | :end,
          page_size: pos_integer(),
          old_label: String.t(),
          new_label: String.t(),
          context: non_neg_integer()
        }

  defstruct rows: [],
            mode: :unified,
            scroll: 0,
            page_size: 20,
            old_label: "before",
            new_label: "after",
            context: 3

  @impl true
  def init(opts) do
    maximum = max(Keyword.get(opts, :max_lines, 5_000), 1)
    context = max(Keyword.get(opts, :context, 3), 0)

    rows =
      case Keyword.fetch(opts, :unified_diff) do
        {:ok, diff} -> diff |> to_string() |> parse_unified(maximum)
        :error -> compare(Keyword.get(opts, :before, ""), Keyword.get(opts, :after, ""), maximum)
      end
      |> collapse_context(context)

    %__MODULE__{
      rows: rows,
      mode: Keyword.get(opts, :mode, :unified),
      page_size: max(Keyword.get(opts, :page_size, 20), 1),
      old_label: opts |> Keyword.get(:old_label, "before") |> to_string(),
      new_label: opts |> Keyword.get(:new_label, "after") |> to_string(),
      context: context
    }
  end

  @impl true
  def update(%Event.Key{key: :up}, state), do: scroll(state, -1)
  def update(%Event.Key{key: :down}, state), do: scroll(state, 1)
  def update(%Event.Key{key: :page_up}, state), do: scroll(state, -state.page_size)
  def update(%Event.Key{key: :page_down}, state), do: scroll(state, state.page_size)
  def update(%Event.Key{key: :home}, state), do: {%{state | scroll: 0}, []}
  def update(%Event.Key{key: :end}, state), do: {%{state | scroll: :end}, []}
  def update(%Event.Text{text: "s"}, state), do: toggle_mode(state)
  def update(%Event.Text{text: "u"}, state), do: {%{state | mode: :unified}, [{:mode, :unified}]}
  def update(%Event.Mouse{action: :scroll_up}, state), do: scroll(state, -3)
  def update(%Event.Mouse{action: :scroll_down}, state), do: scroll(state, 3)
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, height} = dimensions) do
    rendered =
      case state.mode do
        :split -> split_rows(state, width)
        :unified -> unified_rows(state, width)
      end

    offset =
      if state.scroll == :end,
        do: max(length(rendered) - height, 0),
        else: min(state.scroll, max(length(rendered) - height, 0))

    Frame.from_rows(
      Enum.slice(rendered, offset, height),
      elem(dimensions, 0),
      elem(dimensions, 1)
    )
  end

  @doc "Builds comparison rows from two texts."
  @spec compare(String.t(), String.t(), pos_integer()) :: [row()]
  def compare(before, after_text, maximum \\ 5_000) do
    before_lines = before |> to_string() |> split_lines(maximum)
    after_lines = after_text |> to_string() |> split_lines(maximum)

    before_lines
    |> List.myers_difference(after_lines)
    |> build_rows(1, 1, [])
    |> Enum.reverse()
  end

  @doc "Replaces the compared texts."
  @spec set_texts(t(), String.t(), String.t(), pos_integer()) :: t()
  def set_texts(state, before, after_text, maximum \\ 5_000) do
    %{
      state
      | rows: compare(before, after_text, maximum) |> collapse_context(state.context),
        scroll: 0
    }
  end

  defp build_rows([], _old_number, _new_number, rows), do: rows

  defp build_rows([{:eq, lines} | rest], old_number, new_number, rows) do
    {rows, old_number, new_number} =
      Enum.reduce(lines, {rows, old_number, new_number}, fn line,
                                                            {rows, old_number, new_number} ->
        {[
           %{
             kind: :context,
             old_number: old_number,
             new_number: new_number,
             old_text: line,
             new_text: line,
             text: nil
           }
           | rows
         ], old_number + 1, new_number + 1}
      end)

    build_rows(rest, old_number, new_number, rows)
  end

  defp build_rows([{:del, removed}, {:ins, added} | rest], old_number, new_number, rows) do
    {rows, old_number, new_number} = pair_changes(removed, added, old_number, new_number, rows)
    build_rows(rest, old_number, new_number, rows)
  end

  defp build_rows([{:del, removed} | rest], old_number, new_number, rows) do
    {rows, old_number} =
      Enum.reduce(removed, {rows, old_number}, fn line, {rows, number} ->
        {[
           %{
             kind: :removed,
             old_number: number,
             new_number: nil,
             old_text: line,
             new_text: nil,
             text: nil
           }
           | rows
         ], number + 1}
      end)

    build_rows(rest, old_number, new_number, rows)
  end

  defp build_rows([{:ins, added} | rest], old_number, new_number, rows) do
    {rows, new_number} =
      Enum.reduce(added, {rows, new_number}, fn line, {rows, number} ->
        {[
           %{
             kind: :added,
             old_number: nil,
             new_number: number,
             old_text: nil,
             new_text: line,
             text: nil
           }
           | rows
         ], number + 1}
      end)

    build_rows(rest, old_number, new_number, rows)
  end

  defp pair_changes(removed, added, old_number, new_number, rows) do
    count = max(length(removed), length(added))

    Enum.reduce(0..(count - 1), {rows, old_number, new_number}, fn index,
                                                                   {rows, old_number, new_number} ->
      old_text = Enum.at(removed, index)
      new_text = Enum.at(added, index)

      kind =
        cond do
          old_text && new_text -> :changed
          old_text -> :removed
          true -> :added
        end

      row = %{
        kind: kind,
        old_number: if(old_text, do: old_number),
        new_number: if(new_text, do: new_number),
        old_text: old_text,
        new_text: new_text,
        text: nil
      }

      {[row | rows], old_number + if(old_text, do: 1, else: 0),
       new_number + if(new_text, do: 1, else: 0)}
    end)
  end

  defp parse_unified(diff, maximum) do
    {rows, _old_number, _new_number, _hunk_remaining} =
      diff
      |> split_lines(maximum)
      |> Enum.reduce({[], nil, nil, nil}, fn line,
                                             {rows, old_number, new_number, hunk_remaining} ->
        cond do
          String.starts_with?(line, "@@") ->
            {old_number, new_number, hunk_remaining} = hunk_numbers(line)

            {rows ++
               [
                 %{
                   kind: :hunk,
                   old_number: nil,
                   new_number: nil,
                   old_text: nil,
                   new_text: nil,
                   text: line
                 }
               ], old_number, new_number, hunk_remaining}

          is_nil(hunk_remaining) and unified_header?(line) ->
            {rows ++
               [
                 %{
                   kind: :header,
                   old_number: nil,
                   new_number: nil,
                   old_text: nil,
                   new_text: nil,
                   text: line
                 }
               ], old_number, new_number, nil}

          String.starts_with?(line, "+") ->
            row = %{
              kind: :added,
              old_number: nil,
              new_number: new_number,
              old_text: nil,
              new_text: drop_marker(line),
              text: nil
            }

            {rows ++ [row], old_number, increment(new_number), consume_hunk(hunk_remaining, 0, 1)}

          String.starts_with?(line, "-") ->
            row = %{
              kind: :removed,
              old_number: old_number,
              new_number: nil,
              old_text: drop_marker(line),
              new_text: nil,
              text: nil
            }

            {rows ++ [row], increment(old_number), new_number, consume_hunk(hunk_remaining, 1, 0)}

          String.starts_with?(line, "\\") ->
            row = %{
              kind: :header,
              old_number: nil,
              new_number: nil,
              old_text: nil,
              new_text: nil,
              text: line
            }

            {rows ++ [row], old_number, new_number, hunk_remaining}

          true ->
            text = context_text(line)

            row = %{
              kind: :context,
              old_number: old_number,
              new_number: new_number,
              old_text: text,
              new_text: text,
              text: nil
            }

            {rows ++ [row], increment(old_number), increment(new_number),
             consume_hunk(hunk_remaining, 1, 1)}
        end
      end)

    rows
  end

  defp unified_header?(line),
    do: String.starts_with?(line, ["--- ", "+++ ", "---\t", "+++\t"])

  defp drop_marker(line), do: binary_part(line, 1, byte_size(line) - 1)
  defp context_text(" " <> text), do: text
  defp context_text(text), do: text

  defp consume_hunk(nil, _old_count, _new_count), do: nil

  defp consume_hunk({old_remaining, new_remaining}, old_count, new_count) do
    remaining = {max(old_remaining - old_count, 0), max(new_remaining - new_count, 0)}
    if remaining == {0, 0}, do: nil, else: remaining
  end

  defp unified_rows(state, width) do
    header = [
      [{"--- " <> state.old_label, Style.new(fg: :red, attrs: [:bold])}],
      [{"+++ " <> state.new_label, Style.new(fg: :green, attrs: [:bold])}]
    ]

    body =
      Enum.flat_map(state.rows, fn row ->
        case row.kind do
          :changed ->
            [
              unified_line(row.old_number, nil, "-", row.old_text, :removed, width),
              unified_line(nil, row.new_number, "+", row.new_text, :added, width)
            ]

          :removed ->
            [unified_line(row.old_number, nil, "-", row.old_text, :removed, width)]

          :added ->
            [unified_line(nil, row.new_number, "+", row.new_text, :added, width)]

          :context ->
            [unified_line(row.old_number, row.new_number, " ", row.old_text, :context, width)]

          kind when kind in [:hunk, :header, :fold] ->
            [[{Frame.fit(row.text, width), row_style(kind)}]]
        end
      end)

    header ++ body
  end

  defp split_rows(state, width) do
    left_width = max(div(width - 1, 2), 1)
    right_width = max(width - left_width - 1, 1)
    header_style = Style.new(fg: :cyan, attrs: [:bold])

    header = [
      [
        {Frame.fit(state.old_label, left_width), header_style},
        {"│", Style.new(fg: :bright_black)},
        {Frame.fit(state.new_label, right_width), header_style}
      ]
    ]

    body =
      Enum.map(state.rows, fn row ->
        if row.kind in [:hunk, :header, :fold] do
          [{Frame.fit(row.text, width), row_style(row.kind)}]
        else
          left =
            split_cell(
              row.old_number,
              row.old_text,
              left_width,
              (row.kind in [:removed, :changed] && :removed) || :context
            )

          right =
            split_cell(
              row.new_number,
              row.new_text,
              right_width,
              (row.kind in [:added, :changed] && :added) || :context
            )

          left ++ [{"│", Style.new(fg: :bright_black)}] ++ right
        end
      end)

    header ++ body
  end

  defp unified_line(old_number, new_number, marker, text, kind, width) do
    number = number(old_number, 4) <> " " <> number(new_number, 4) <> " "

    [[{number, Style.new(fg: :bright_black)}, {marker <> (text || ""), row_style(kind)}]]
    |> List.first()
    |> Helpers.fit_row(width)
  end

  defp split_cell(number_value, text, width, kind) do
    prefix = number(number_value, 4) <> " "

    Helpers.fit_row(
      [{prefix, Style.new(fg: :bright_black)}, {text || "", row_style(kind)}],
      width
    )
  end

  defp collapse_context(rows, context) do
    rows
    |> Enum.chunk_by(&(&1.kind == :context))
    |> Enum.flat_map(fn chunk ->
      if chunk != [] and hd(chunk).kind == :context and length(chunk) > context * 2 + 1 do
        Enum.take(chunk, context) ++
          [
            %{
              kind: :fold,
              old_number: nil,
              new_number: nil,
              old_text: nil,
              new_text: nil,
              text: "… #{length(chunk) - context * 2} unchanged lines …"
            }
          ] ++ Enum.take(chunk, -context)
      else
        chunk
      end
    end)
  end

  defp toggle_mode(state) do
    mode = if state.mode == :unified, do: :split, else: :unified
    {%{state | mode: mode, scroll: 0}, [{:mode, mode}]}
  end

  defp scroll(state, delta) do
    scroll = if state.scroll == :end, do: length(state.rows), else: state.scroll
    scroll = max(scroll + delta, 0)
    {%{state | scroll: scroll}, [{:scrolled, scroll}]}
  end

  defp row_style(:added), do: Style.new(fg: :green)
  defp row_style(:removed), do: Style.new(fg: :red)
  defp row_style(:hunk), do: Style.new(fg: :cyan)
  defp row_style(:header), do: Style.new(attrs: [:bold])
  defp row_style(:fold), do: Style.new(fg: :bright_black, attrs: [:italic])
  defp row_style(_kind), do: Style.new()
  defp number(nil, width), do: String.duplicate(" ", width)
  defp number(value, width), do: value |> Integer.to_string() |> String.pad_leading(width)

  defp split_lines(text, maximum),
    do: text |> String.split(["\r\n", "\n"], trim: false) |> Enum.take(maximum)

  defp increment(nil), do: nil
  defp increment(number), do: number + 1

  defp hunk_numbers(line) do
    pattern =
      ~r/^@@ -(?<old_start>\d+)(?:,(?<old_count>\d+))? \+(?<new_start>\d+)(?:,(?<new_count>\d+))? @@/

    case Regex.named_captures(pattern, line) do
      %{
        "old_start" => old_start,
        "old_count" => old_count,
        "new_start" => new_start,
        "new_count" => new_count
      } ->
        {String.to_integer(old_start), String.to_integer(new_start),
         {hunk_count(old_count), hunk_count(new_count)}}

      _match ->
        {nil, nil, nil}
    end
  end

  defp hunk_count(count) when count in [nil, ""], do: 1
  defp hunk_count(count), do: String.to_integer(count)
end
