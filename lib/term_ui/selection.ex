defmodule TermUI.Selection do
  @moduledoc """
  Pure Unicode text selection state.

  Positions are zero-based grapheme offsets. A selection keeps its anchor and
  moving head, so backward selections remain directional. The public range is
  always a half-open `{start, finish}` tuple in ascending order.
  """

  import Kernel, except: [length: 1]

  @type position :: non_neg_integer()
  @type t :: %__MODULE__{anchor: position() | nil, head: position() | nil}

  @position Zoi.union([Zoi.integer() |> Zoi.non_negative(), Zoi.literal(nil)])
  @schema Zoi.struct(__MODULE__, %{
            anchor: @position |> Zoi.default(nil),
            head: @position |> Zoi.default(nil)
          })

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for selection state."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates an empty selection."
  @spec new() :: %__MODULE__{anchor: nil, head: nil}
  def new, do: %__MODULE__{}

  @doc "Starts a selection and sets its anchor."
  @spec start(t(), position()) :: t()
  def start(%__MODULE__{}, position) when is_integer(position) and position >= 0,
    do: %__MODULE__{anchor: position, head: position}

  @doc "Moves the selection head while retaining its anchor."
  @spec extend(t(), position()) :: t()
  def extend(%__MODULE__{anchor: nil} = selection, position), do: start(selection, position)

  def extend(%__MODULE__{} = selection, position)
      when is_integer(position) and position >= 0,
      do: %{selection | head: position}

  @doc "Clears the selection."
  @spec clear(t()) :: t()
  def clear(%__MODULE__{}), do: new()

  @doc "Returns true when the selection has an anchor and head."
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{anchor: anchor, head: head}), do: anchor != nil and head != nil

  @doc "Returns true when the selection has no selected graphemes."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = selection) do
    not active?(selection) or selection.anchor == selection.head
  end

  @doc "Returns the ascending half-open range, or `nil` when inactive."
  @spec range(t()) :: {position(), position()} | nil
  def range(%__MODULE__{} = selection) do
    if active?(selection),
      do: {min(selection.anchor, selection.head), max(selection.anchor, selection.head)},
      else: nil
  end

  @doc "Returns the anchor position."
  @spec anchor(t()) :: position() | nil
  def anchor(%__MODULE__{anchor: anchor}), do: anchor

  @doc "Returns the moving head position."
  @spec head(t()) :: position() | nil
  def head(%__MODULE__{head: head}), do: head

  @doc "Returns the selected grapheme count."
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{} = selection) do
    case range(selection) do
      nil -> 0
      {start, finish} -> finish - start
    end
  end

  @doc "Returns true when a grapheme position is inside the selection."
  @spec contains?(t(), position()) :: boolean()
  def contains?(%__MODULE__{} = selection, position)
      when is_integer(position) and position >= 0 do
    case range(selection) do
      nil -> false
      {start, finish} -> position >= start and position < finish
    end
  end

  @doc "Extracts selected graphemes from text."
  @spec extract(t(), String.t()) :: String.t()
  def extract(%__MODULE__{} = selection, text) when is_binary(text) do
    graphemes = String.graphemes(text)

    case clamped_range(selection, Kernel.length(graphemes)) do
      nil -> ""
      {start, finish} -> graphemes |> Enum.slice(start, finish - start) |> Enum.join()
    end
  end

  @doc "Replaces selected graphemes and returns `{text, cursor, cleared_selection}`."
  @spec replace(t(), String.t(), String.t()) :: {String.t(), position(), t()}
  def replace(%__MODULE__{} = selection, text, replacement)
      when is_binary(text) and is_binary(replacement) do
    graphemes = String.graphemes(text)
    inserted = String.graphemes(replacement)

    {start, finish} = clamped_range(selection, Kernel.length(graphemes)) || {0, 0}
    value = Enum.take(graphemes, start) ++ inserted ++ Enum.drop(graphemes, finish)
    {Enum.join(value), start + Kernel.length(inserted), new()}
  end

  @doc "Selects all text."
  @spec select_all(t(), String.t()) :: t()
  def select_all(%__MODULE__{}, text) when is_binary(text),
    do: %__MODULE__{anchor: 0, head: grapheme_count(text)}

  @doc "Selects the word, whitespace run, or punctuation run at a position."
  @spec select_word(t(), String.t(), position()) :: t()
  def select_word(%__MODULE__{}, text, position)
      when is_binary(text) and is_integer(position) and position >= 0 do
    graphemes = String.graphemes(text)

    case graphemes do
      [] ->
        start(new(), 0)

      _items ->
        index = min(position, Kernel.length(graphemes) - 1)
        category = graphemes |> Enum.at(index) |> category()
        start = run_start(graphemes, index, category)
        finish = run_finish(graphemes, index, category)
        %__MODULE__{anchor: start, head: finish}
    end
  end

  @doc "Selects the line containing a grapheme position, without its newline."
  @spec select_line(t(), String.t(), position()) :: t()
  def select_line(%__MODULE__{}, text, position)
      when is_binary(text) and is_integer(position) and position >= 0 do
    graphemes = String.graphemes(text)
    position = min(position, Kernel.length(graphemes))
    start = line_start(graphemes, position)
    finish = line_finish(graphemes, position)
    %__MODULE__{anchor: start, head: finish}
  end

  defp clamped_range(selection, maximum) do
    case range(selection) do
      nil -> nil
      {start, finish} -> {min(start, maximum), min(finish, maximum)}
    end
  end

  defp run_start(graphemes, index, category) do
    graphemes
    |> Enum.take(index)
    |> Enum.reverse()
    |> Enum.take_while(&(category(&1) == category))
    |> Kernel.length()
    |> then(&(index - &1))
  end

  defp run_finish(graphemes, index, category) do
    graphemes
    |> Enum.drop(index)
    |> Enum.take_while(&(category(&1) == category))
    |> Kernel.length()
    |> Kernel.+(index)
  end

  defp line_start(graphemes, position) do
    graphemes
    |> Enum.take(position)
    |> Enum.reverse()
    |> Enum.find_index(&(&1 == "\n"))
    |> case do
      nil -> 0
      distance -> position - distance
    end
  end

  defp line_finish(graphemes, position) do
    graphemes
    |> Enum.drop(position)
    |> Enum.find_index(&(&1 == "\n"))
    |> case do
      nil -> Kernel.length(graphemes)
      distance -> position + distance
    end
  end

  defp category(grapheme) do
    cond do
      String.match?(grapheme, ~r/^[\p{L}\p{N}_]$/u) -> :word
      String.match?(grapheme, ~r/^\s$/u) -> :space
      true -> :punctuation
    end
  end

  defp grapheme_count(text), do: text |> String.graphemes() |> Kernel.length()
end
