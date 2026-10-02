# Markdown and diff viewers

## Markdown

`TermUI.Markdown` parses Markdown with MDEx. It returns styled frame rows.

```elixir
rows = TermUI.Markdown.render(markdown, 80)
frame = TermUI.Frame.from_rows(rows, 80, 24)
```

Use `TermUI.Widget.MarkdownViewer` for scrolling and code-block selection. A
copy action returns `{:copy, code}` to the parent. The widget does not access
the system clipboard.

```elixir
viewer = TermUI.Widget.MarkdownViewer.init(content: markdown)
{viewer, messages} = TermUI.Widget.MarkdownViewer.update(event, viewer)
frame = TermUI.Widget.MarkdownViewer.view(viewer, {80, 24})
```

For streaming content, `append/2` uses a bounded `TermUI.Markdown.Document`.
Completed top-level blocks are parsed once. The final paragraph, list, or fenced
code block remains pending because more source can still extend it. Rendering
reparses only that unfinished tail for ordinary documents. When retained source
contains a possible reference definition (`]:`), rendering parses the full
retained source so that references before and after a cached block stay valid.
Source bytes and the content limit stay unchanged.

```elixir
viewer = TermUI.Widget.MarkdownViewer.init(content_limit: 2_000_000)
viewer = TermUI.Widget.MarkdownViewer.append(viewer, token_fragment)
```

The viewer supports headings, emphasis, strong and strike-through text, inline
code, links, images, quotes, ordered and unordered lists, task lists, code
blocks, rules, and tables. Raw HTML is reduced to terminal-safe text.

### Optional syntax highlighting

Plain code rendering has no lexer dependency. To enable highlighting, set a
module that implements `TermUI.SyntaxHighlighter`:

```elixir
viewer =
  TermUI.Widget.MarkdownViewer.init(
    content: markdown,
    highlighter: MyApp.SyntaxAdapter,
    highlight_limit: 100_000
  )
```

An adapter returns `{:ok, [{token_type, text}]}`, `:skip`, or
`{:error, reason}`. Token text must reproduce the complete input. Known token
families receive terminal styles. Unknown token types keep the plain code
style. An absent or failed adapter also falls back to plain code.

`TermUI.SyntaxHighlighter.Makeup` supports Elixir and Erlang when the host
application installs `:makeup`, `:makeup_elixir`, and `:makeup_erlang`. TermUI
does not require those packages. The default `:highlight_limit` is 100,000
bytes per code block. Larger blocks remain complete but bypass the adapter.

## Diffs

Create a diff from two texts:

```elixir
viewer =
  TermUI.Widget.DiffViewer.init(
    before: old_text,
    after: new_text,
    old_label: "a/file.ex",
    new_label: "b/file.ex"
  )
```

Or supply an existing unified diff with `:unified_diff`. Press `s` to switch
between unified and side-by-side views. The viewer uses line-based Myers
comparison and bounds input to 5,000 lines by default.

An adapter must keep token boundaries between complete source graphemes.
If a token splits a combining sequence, joined emoji, or flag, that code block
uses plain styling. Its source bytes and row geometry stay the same.

DiffViewer accepts `update(event, state, dimensions)` and `set_dimensions/2`.
Use the same dimensions for update and view. Its scroll messages contain a
bounded display-row offset, `:end`, or `{:end, distance}` from the last page.
`update/2` remains available; an End distance resolves at the next view size.
