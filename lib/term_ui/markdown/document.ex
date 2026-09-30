defmodule TermUI.Markdown.Document do
  @moduledoc """
  A bounded, incremental Markdown document.

  Completed top-level blocks are parsed once and retained as MDEx nodes. The
  final paragraph, list, or fenced block stays in `pending` because later text
  can still extend it. Rendering reparses only that unfinished tail. If the
  byte limit removes old source, the retained tail is rebuilt once.
  """

  alias TermUI.Markdown.Parser

  @type segment :: %{source: String.t(), nodes: [struct()]}
  @type t :: %__MODULE__{
          content: String.t(),
          segments: [segment()],
          pending: String.t(),
          content_limit: pos_integer(),
          parsed_segments: non_neg_integer()
        }

  defstruct content: "",
            segments: [],
            pending: "",
            content_limit: 2_000_000,
            parsed_segments: 0

  @doc "Creates a bounded incremental document from source text."
  @spec new(String.t(), keyword()) :: t()
  def new(content \\ "", opts \\ []) do
    limit = opts |> Keyword.get(:content_limit, 2_000_000) |> max(1)
    content = content |> to_string() |> retain_tail(limit)
    {segments, pending} = parse_complete([], content)

    %__MODULE__{
      content: content,
      segments: segments,
      pending: pending,
      content_limit: limit,
      parsed_segments: length(segments)
    }
  end

  @doc "Appends a fragment and parses only newly completed block groups."
  @spec append(t(), String.t()) :: t()
  def append(document, fragment) when is_binary(fragment) do
    combined = document.content <> fragment
    retained = retain_tail(combined, document.content_limit)

    if byte_size(retained) < byte_size(combined) do
      new(retained, content_limit: document.content_limit)
    else
      {segments, pending} = parse_complete(document.segments, document.pending <> fragment)

      %{
        document
        | content: retained,
          segments: segments,
          pending: pending,
          parsed_segments: document.parsed_segments + length(segments) - length(document.segments)
      }
    end
  end

  @doc "Replaces all source and resets the incremental parse state."
  @spec replace(t(), String.t()) :: t()
  def replace(document, content),
    do: new(content, content_limit: document.content_limit)

  @doc "Returns the count of source bytes that no longer need parsing."
  @spec committed_bytes(t()) :: non_neg_integer()
  def committed_bytes(document),
    do: Enum.reduce(document.segments, 0, &(byte_size(&1.source) + &2))

  defp parse_complete(existing, buffer) do
    case Parser.parse(buffer) do
      {:ok, %MDEx.Document{nodes: nodes}} when length(nodes) > 1 ->
        pending_node = List.last(nodes)

        case pending_start_line(pending_node) do
          nil ->
            {existing, buffer}

          line ->
            boundary = line_start_offset(buffer, line)
            source = binary_part(buffer, 0, boundary)
            pending = binary_part(buffer, boundary, byte_size(buffer) - boundary)
            segment = %{source: source, nodes: Enum.drop(nodes, -1)}
            {existing ++ [segment], pending}
        end

      _result ->
        {existing, buffer}
    end
  end

  defp pending_start_line(%{sourcepos: %{start: {line, _column}}}) when is_integer(line), do: line
  defp pending_start_line(_node), do: nil

  defp line_start_offset(_buffer, line) when line <= 1, do: 0

  defp line_start_offset(buffer, line) do
    case buffer |> :binary.matches("\n") |> Enum.at(line - 2) do
      {position, length} -> position + length
      nil -> 0
    end
  end

  defp retain_tail(content, limit) when byte_size(content) <= limit, do: content

  defp retain_tail(content, limit) do
    content
    |> binary_part(byte_size(content) - limit, limit)
    |> valid_utf8_tail()
  end

  defp valid_utf8_tail(<<>>), do: ""

  defp valid_utf8_tail(content) do
    if String.valid?(content),
      do: content,
      else: content |> binary_part(1, byte_size(content) - 1) |> valid_utf8_tail()
  end
end
