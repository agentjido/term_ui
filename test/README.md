# Test layout

See [the testing guide](../guides/testing.md) for commands and limits.

- `term_ui`: focused tests, with paths that match `lib/term_ui` where possible.
- `integration`: runtime and host behavior across module boundaries.
- `spex`: user acceptance workflows. SexySpex finds this path by default.
- `platform`: real PTY checks and platform probe scripts under `support`.
- `mix`: tests for the consumer Mix task.
- `support`: private compiled Elixir test helpers.

Keep consumer application tests beside each example. Do not duplicate an
example application inside an acceptance test. Keep core assertions, physical
terminal evidence, and optional host checks distinct. Run `mix coveralls` and
`mix spex` before a commit that changes either group.
