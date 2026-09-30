defmodule TermUI.SyntaxHighlighter.Makeup do
  @moduledoc """
  Optional Makeup adapter for Elixir and Erlang code.

  The host application must add `:makeup`, `:makeup_elixir`, and
  `:makeup_erlang` to its dependencies. This module loads those lexers only
  when an applicable code block is rendered. Missing lexers return `:skip`.
  """

  @behaviour TermUI.SyntaxHighlighter

  @elixir_lexer Module.concat(["Makeup", "Lexers", "ElixirLexer"])
  @erlang_lexer Module.concat(["Makeup", "Lexers", "ErlangLexer"])
  @compile {:no_warn_undefined, [{@elixir_lexer, :lex, 1}, {@erlang_lexer, :lex, 1}]}

  @impl true
  def highlight(source, language) when is_binary(source) do
    with {:ok, lexer} <- lexer(language),
         true <- Code.ensure_loaded?(lexer),
         true <- function_exported?(lexer, :lex, 1),
         tokens when is_list(tokens) <- lexer.lex(source) do
      normalize(tokens)
    else
      _unavailable -> :skip
    end
  end

  defp lexer(language) when is_binary(language) do
    case String.downcase(language) do
      language when language in ["elixir", "ex", "exs"] -> {:ok, @elixir_lexer}
      language when language in ["erlang", "erl", "hrl"] -> {:ok, @erlang_lexer}
      _unsupported -> :error
    end
  end

  defp lexer(_language), do: :error

  defp normalize(tokens) do
    Enum.reduce_while(tokens, {:ok, []}, fn
      {type, _metadata, text}, {:ok, normalized} ->
        {:cont, {:ok, [{type, text} | normalized]}}

      _invalid, _acc ->
        {:halt, :error}
    end)
    |> then(fn
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      :error -> {:error, :invalid_tokens}
    end)
  end
end
