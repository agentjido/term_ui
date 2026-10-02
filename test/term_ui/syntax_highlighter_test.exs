defmodule TermUI.SyntaxHighlighterTest do
  use ExUnit.Case, async: true

  alias TermUI.{Frame, Style, SyntaxHighlighter}
  alias TermUI.SyntaxHighlighter.Makeup
  alias TermUI.Widget.MarkdownViewer

  defmodule TokenAdapter do
    @behaviour TermUI.SyntaxHighlighter

    @impl true
    def highlight("def " <> name, "elixir") do
      {:ok,
       [
         {:keyword_declaration, "def"},
         {:whitespace, " "},
         {:unknown_library_token, name}
       ]}
    end

    def highlight(_source, _language), do: :skip
  end

  defmodule KeywordAdapter do
    @behaviour TermUI.SyntaxHighlighter

    @impl true
    def highlight(source, _language), do: {:ok, [{:keyword, source}]}
  end

  defmodule InvalidAdapter do
    @behaviour TermUI.SyntaxHighlighter

    @impl true
    def highlight(_source, _language), do: {:ok, [{:keyword, "changed"}]}
  end

  test "adapter tokens map to styles and unknown types keep plain code styling" do
    assert [
             {"def", %Style{fg: :magenta}},
             {" ", %Style{fg: :yellow}},
             {"value", %Style{fg: :yellow}}
           ] = SyntaxHighlighter.spans("def value", "elixir", adapter: TokenAdapter)
  end

  test "missing and invalid adapters preserve the complete plain source" do
    source = "plain\ntext"

    assert [{^source, %Style{fg: :yellow}}] = SyntaxHighlighter.spans(source, nil)

    assert [{^source, %Style{fg: :yellow}}] =
             SyntaxHighlighter.spans(source, "elixir", adapter: InvalidAdapter)

    assert [[{"plain", _first_style}], [{"text", _second_style}]] =
             SyntaxHighlighter.lines(source, nil)
  end

  test "the byte limit bypasses the adapter without truncating source" do
    source = "0123456789"

    assert [{^source, %Style{fg: :yellow}}] =
             SyntaxHighlighter.spans(source, "elixir",
               adapter: KeywordAdapter,
               max_bytes: 4
             )

    assert [{^source, %Style{fg: :magenta}}] =
             SyntaxHighlighter.spans(source, "elixir",
               adapter: KeywordAdapter,
               max_bytes: byte_size(source)
             )
  end

  test "Markdown viewer keeps adapter options in pure widget state" do
    state =
      MarkdownViewer.init(
        content: "```elixir\ndef value\n```",
        highlighter: TokenAdapter,
        highlight_limit: 20
      )

    assert state.highlighter == TokenAdapter
    assert state.highlight_limit == 20
    refute is_pid(state.highlighter)

    frame = MarkdownViewer.view(state, {24, 4})
    assert Frame.cell(frame, 2, 3).fg == :magenta
    assert Frame.cell(frame, 2, 7).fg == :yellow
  end

  test "Makeup adapter skips unsupported languages without requiring Makeup" do
    assert Makeup.highlight("value", "unknown") == :skip
  end

  test "a compiled but unloaded adapter is loaded before callback lookup" do
    directory =
      Path.join(System.tmp_dir!(), "term-ui-adapter-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)

    [{module, beam}] =
      Code.compile_string("""
      defmodule TermUI.UnloadedTestAdapter do
        def highlight("raise", _), do: raise("failure")
        def highlight("invalid", _), do: {:ok, [{:keyword, {:bad}}]}
        def highlight(source, _), do: {:ok, [{:keyword, source}]}
      end
      """)

    File.write!(Path.join(directory, Atom.to_string(module) <> ".beam"), beam)
    :code.purge(module)
    :code.delete(module)
    Code.prepend_path(directory)

    on_exit(fn ->
      Code.delete_path(directory)
      :code.purge(module)
      :code.delete(module)
      File.rm_rf!(directory)
    end)

    assert :code.is_loaded(module) == false
    assert [{"if", %Style{fg: :magenta}}] = SyntaxHighlighter.spans("if", nil, adapter: module)

    assert [{"if", %Style{fg: :yellow}}] =
             SyntaxHighlighter.spans("if", nil, adapter: TermUI.MissingTestAdapter)

    for source <- ["raise", "invalid"] do
      assert [{^source, %Style{fg: :yellow}}] =
               SyntaxHighlighter.spans(source, nil, adapter: module)
    end
  end
end
