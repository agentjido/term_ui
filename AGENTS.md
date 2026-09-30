# TermUI Agent Instructions

TermUI is a small Elm-style terminal runtime for Elixir and the BEAM.

Keep these runtime boundaries:

- One runtime process owns application state and update order.
- Application views return one complete `TermUI.Frame`.
- One backend owner controls terminal input, output, size, capabilities, and cleanup.
- Widgets are pure. The parent application owns widget state and effects.
- Commands are data values. Do not run effects in widget code.

Use `main` as the pull request target for v2 work. Use `maint/1.x` for v1
fixes. The maintainer approved the v2 transition on 30 September 2026.
Keep the two version lines separate. Preserve the public `TermUI` namespace and the Jido
Console runtime contract. Run `mix quality` and `mix coveralls` before a commit.
Terminal lifecycle changes also need a real terminal check.

Hex publication is managed separately by the maintainer. Repository cleanup
must not publish a package, push a release tag, or run a publication workflow.

Use Conventional Commits. Never mention an AI assistant in a commit message.
