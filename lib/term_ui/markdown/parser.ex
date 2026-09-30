defmodule TermUI.Markdown.Parser do
  @moduledoc false

  @extensions [table: true, strikethrough: true, tasklist: true, autolink: true]

  @doc false
  @spec parse(String.t()) :: {:ok, MDEx.Document.t()} | {:error, term()}
  def parse(markdown) when is_binary(markdown),
    do: MDEx.parse_document(markdown, extension: @extensions)
end
