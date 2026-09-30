defmodule TermUI.SyntaxHighlighter do
  @moduledoc """
  Converts optional lexer tokens to terminal styles.

  An adapter implements `highlight/2` and returns ordered `{type, text}`
  tokens. The token text must reproduce the complete source. The renderer uses
  plain code styling when no adapter is set, the adapter fails, its output is
  invalid, or the source is larger than the configured byte limit.

  This module has no lexer dependency and starts no process.
  """

  alias TermUI.{Frame, Style}

  # Dialyzer does not preserve MapSet's opaque type in the compiled style constants.
  @dialyzer {:nowarn_function, style: 1}

  @default_max_bytes 100_000
  @plain_code Style.new(fg: :yellow)
  @keyword Style.new(fg: :magenta, attrs: [:bold])
  @name Style.new(fg: :cyan)
  @string Style.new(fg: :green)
  @number Style.new(fg: :yellow)
  @comment Style.new(fg: :bright_black, attrs: [:italic])
  @operator Style.new(fg: :bright_cyan)
  @punctuation Style.new(fg: :white)
  @attribute Style.new(fg: :bright_yellow)
  @error Style.new(fg: :bright_red, attrs: [:underline])

  @type token_type :: atom() | {atom(), atom()}
  @type token :: {token_type(), iodata()}
  @type result :: {:ok, [token()]} | :skip | {:error, term()}

  @callback highlight(source :: String.t(), language :: String.t() | nil) :: result()

  @doc "Returns the default maximum source size sent to an adapter."
  @spec default_max_bytes() :: 100_000
  def default_max_bytes, do: @default_max_bytes

  @doc """
  Returns styled spans for source code.

  Options are `:adapter`, which is a module that implements this behavior, and
  `:max_bytes`, which defaults to `100_000`. Source above the bound is kept in
  full and receives plain code styling. It is not sent to the adapter.
  """
  @spec spans(String.t(), String.t() | nil, keyword()) :: [Frame.span()]
  def spans(source, language, opts \\ []) when is_binary(source) do
    adapter = Keyword.get(opts, :adapter)
    max_bytes = normalize_max_bytes(Keyword.get(opts, :max_bytes, @default_max_bytes))

    if is_nil(adapter) or byte_size(source) > max_bytes do
      plain(source)
    else
      adapter_spans(adapter, source, language)
    end
  end

  @doc "Returns styled logical lines for source code."
  @spec lines(String.t(), String.t() | nil, keyword()) :: [[Frame.span()]]
  def lines(source, language, opts \\ []) do
    source
    |> spans(language, opts)
    |> split_lines()
  end

  @doc "Returns the terminal style for one lexer token type."
  @spec style(token_type()) :: Style.t()
  def style(type), do: token_style(type)

  defp adapter_spans(adapter, source, language) when is_atom(adapter) do
    with true <- function_exported?(adapter, :highlight, 2),
         {:ok, tokens} when is_list(tokens) <- adapter.highlight(source, language),
         {:ok, spans} <- normalize_tokens(tokens),
         true <- spans_text(spans) == source do
      spans
    else
      _not_highlighted -> plain(source)
    end
  rescue
    _error -> plain(source)
  catch
    _kind, _reason -> plain(source)
  end

  defp adapter_spans(_adapter, source, _language), do: plain(source)

  defp normalize_tokens(tokens) do
    Enum.reduce_while(tokens, {:ok, []}, fn
      {type, text}, {:ok, spans} when is_atom(type) or is_tuple(type) ->
        case safe_binary(text) do
          {:ok, binary} -> {:cont, {:ok, [{binary, token_style(type)} | spans]}}
          :error -> {:halt, :error}
        end

      _invalid, _acc ->
        {:halt, :error}
    end)
    |> then(fn
      {:ok, spans} -> {:ok, Enum.reverse(spans)}
      :error -> :error
    end)
  end

  defp safe_binary(text) do
    {:ok, IO.iodata_to_binary(text)}
  rescue
    _error -> :error
  end

  defp spans_text(spans), do: Enum.map_join(spans, fn {text, _style} -> text end)

  defp split_lines(spans) do
    {lines, current} =
      Enum.reduce(spans, {[], []}, fn {text, style}, {lines, current} ->
        text
        |> String.split("\n", trim: false)
        |> add_parts(lines, current, style)
      end)

    Enum.reverse([Enum.reverse(current) | lines])
  end

  defp add_parts([part], lines, current, style),
    do: {lines, add_part(current, part, style)}

  defp add_parts([part | rest], lines, current, style) do
    line = current |> add_part(part, style) |> Enum.reverse()
    add_parts(rest, [line | lines], [], style)
  end

  defp add_part(current, "", _style), do: current
  defp add_part([{text, style} | rest], part, style), do: [{text <> part, style} | rest]
  defp add_part(current, part, style), do: [{part, style} | current]

  defp token_style({family, _detail}), do: token_style(family)
  defp token_style(:keyword), do: @keyword
  defp token_style(:name), do: @name
  defp token_style(:string), do: @string
  defp token_style(:number), do: @number
  defp token_style(:comment), do: @comment
  defp token_style(:operator), do: @operator
  defp token_style(:punctuation), do: @punctuation
  defp token_style(:attribute), do: @attribute
  defp token_style(:error), do: @error
  defp token_style(type) when is_atom(type), do: prefixed_token_style(Atom.to_string(type))
  defp token_style(_unknown), do: @plain_code

  defp prefixed_token_style("keyword" <> _detail), do: @keyword
  defp prefixed_token_style("name" <> _detail), do: @name
  defp prefixed_token_style("string" <> _detail), do: @string
  defp prefixed_token_style("number" <> _detail), do: @number
  defp prefixed_token_style("comment" <> _detail), do: @comment
  defp prefixed_token_style("operator" <> _detail), do: @operator
  defp prefixed_token_style("punctuation" <> _detail), do: @punctuation
  defp prefixed_token_style("attribute" <> _detail), do: @attribute
  defp prefixed_token_style("error" <> _detail), do: @error
  defp prefixed_token_style(_unknown), do: @plain_code

  defp normalize_max_bytes(max_bytes) when is_integer(max_bytes) and max_bytes > 0, do: max_bytes
  defp normalize_max_bytes(_invalid), do: @default_max_bytes
  defp plain(source), do: [{source, @plain_code}]
end
