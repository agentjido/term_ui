# Share examples and ask for help

Use the existing [TermUI thread on Elixir Forum](https://elixirforum.com/t/termui-a-direct-mode-terminal-user-interface-framework-with-components/73464)
to share applications, screenshots, components, and development methods.
Use that thread for general questions too. Include a link to your source and
the TermUI version or commit that you used.

Use [GitHub issues](https://github.com/agentjido/term_ui/issues) for a defect
or a specific feature request. Search the open and closed issues first. For a
defect, include a small example, expected output, actual output, TermUI commit,
Elixir and OTP versions, operating system, terminal, and backend. For an input
defect, include the key and its received bytes when possible.

The project repository is `agentjido/term_ui`. Older examples can link to an
earlier repository or use an older API. Check their version before use.

## Choose the version branch

| Work | Base and pull request target | Application contract |
| --- | --- | --- |
| V1 fixes and examples | `maint/1.x` | Use the v1 render tree, widgets, and commands on that branch. |
| V2 fixes and examples | `next/v2` | Return a complete `TermUI.Frame`. Keep widgets pure and effects in application commands. |

`next/v2` is the v2 development branch. It is not yet a published 2.0 release.
Keep v2 changes out of `develop` until the separate release decision.

## Contribute an example

Start with the example on your target branch. For v2, the
[IEx counter](https://github.com/agentjido/term_ui/tree/next/v2/examples/iex_counter)
shows the small application contract. The
[showcase](https://github.com/agentjido/term_ui/tree/next/v2/examples/showcase)
shows widget composition and application-owned effects.

Put a contributed example in `examples/<name>`. Give it a README with:

- The TermUI branch or release, required toolchain, and start command.
- The keys, backend choices, and expected behavior.
- The tested operating system and terminal.
- Tests for the main state changes and resulting output.

Keep the example small. Keep application state and update order in one runtime.
Keep terminal setup and cleanup in the backend. On v2, widgets return values;
the application owns their state and effects. Do not start a polling process
from a widget.

Run the checks in [CONTRIBUTING.md](https://github.com/agentjido/term_ui/blob/next/v2/CONTRIBUTING.md)
before you submit a pull request. A terminal example also needs an interactive
check of input, resize, quit, and restored terminal settings. Record the
terminal and result in the pull request.

## Share a prompt or development plan

The [prompt examples](https://github.com/agentjido/term_ui/tree/next/v2/examples/prompts)
contain a small v2 counter request. You can use it with Claude or another code
tool. Adapt its namespace, version, and behavior to the application. Read the
result and run its checks before use.

A prompt contribution must name the target version and the expected behavior.
Include a runnable example or a link to one, plus the checks used to verify the
result. Keep prompts independent of a required editor or model. A prompt does
not replace API documents or tests.

[andyl/zing](https://github.com/andyl/zing) is a community example shared in
issue [#9](https://github.com/agentjido/term_ui/issues/9). Its
[development plan](https://github.com/andyl/zing/blob/master/PLANS/dev_plan.md)
describes a counter and file browsers. It uses older TermUI references. Check
and adapt its API before use with v2. The project does not claim that this
external application passes the current v2 checks.
