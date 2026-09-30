# V2 migration check record

Checked on 29 September 2026 against code candidate `56c1d69caf3f3b8264bf4e1ba968d9a360de70ae`.

All 27 required checks pass in [run 36654920854](https://github.com/agentjido/term_ui/actions/runs/36654920854). Local quality passes; 1,041 tests pass, one is excluded, and coverage is 90.6%. The implementation commits recorded in the migration issues are ancestors of the candidate.

This confirms migration implementation. TermUI 2.0 is not published. Physical frontend checks, the separate release decision, required review, and publication remain in PR #67 and `release-2.0.0.md`.

| Issue | Current evidence |
| --- | --- |
| [#48](https://github.com/agentjido/term_ui/issues/48) | Real SSH integration and backend tests; PRs #87 and #94. |
| [#49](https://github.com/agentjido/term_ui/issues/49) | `test/term_ui/app_test.exs`. |
| [#50](https://github.com/agentjido/term_ui/issues/50) | `test/term_ui/compatibility_alias_test.exs`. |
| [#51](https://github.com/agentjido/term_ui/issues/51) | `test/term_ui/config_test.exs`. |
| [#52](https://github.com/agentjido/term_ui/issues/52) | `test/term_ui/widget/router_test.exs`. |
| [#53](https://github.com/agentjido/term_ui/issues/53) | `test/integration/public_test_backend_test.exs`. |
| [#54](https://github.com/agentjido/term_ui/issues/54) | `test/term_ui/layout_test.exs`. |
| [#55](https://github.com/agentjido/term_ui/issues/55) | `test/support/no_nif_backend_probe.exs`. |
| [#56](https://github.com/agentjido/term_ui/issues/56) | `test/term_ui/widget/plural_compatibility_test.exs`. |
| [#57](https://github.com/agentjido/term_ui/issues/57) | `test/term_ui/widget/table_state_test.exs`. |
| [#58](https://github.com/agentjido/term_ui/issues/58) | `test/term_ui/input_test.exs`. |
| [#59](https://github.com/agentjido/term_ui/issues/59) | `test/term_ui/widget/form_validation_test.exs`. |
| [#60](https://github.com/agentjido/term_ui/issues/60) | `test/term_ui/widget/menu_nested_test.exs`. |
| [#61](https://github.com/agentjido/term_ui/issues/61) | `test/term_ui/syntax_highlighter_test.exs`. |
| [#62](https://github.com/agentjido/term_ui/issues/62) | `test/term_ui/widget/split_pane_test.exs`. |
| [#63](https://github.com/agentjido/term_ui/issues/63) | `test/term_ui/snapshot_provider_test.exs`. |
| [#64](https://github.com/agentjido/term_ui/issues/64) | `test/term_ui/widget/toast_manager_test.exs`. |
| [#65](https://github.com/agentjido/term_ui/issues/65) | `guides/package-quality.md`. |
| [#66](https://github.com/agentjido/term_ui/issues/66) | `guides/ui-context.md`. |

Issue #66 is a completed evaluation. No generic `TermUI.Context` is added. Theme, focus, shortcut, and mouse values stay in their smallest parent-owned scope. The guide had an old 1.0 candidate label; PR #96 corrects it to 2.0.
