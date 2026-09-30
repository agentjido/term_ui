# Examples

These examples are separate consumer projects. They keep host dependencies and
application code outside the library. Use Elixir 1.18.4 or later with OTP 28 or
later. Start from the repository root and follow each README.

| Directory | Purpose | Start |
| --- | --- | --- |
| [iex_counter](iex_counter/README.md) | Small Elm application: state, typed events, commands, and a complete frame | `cd examples/iex_counter`, then `mix deps.get` and `mix run run.exs` |
| [showcase](showcase/README.md) | Widget composition, responsive views, and application-owned effects | `cd examples/showcase`, then `mix deps.get` and `mix run run.exs` |
| [web](web/README.md) | Browser host with separate sessions and the packaged web renderer | `cd examples/web`, then `mix deps.get` and `mix run --no-halt`; open `http://127.0.0.1:4040` |
| [ghostty](ghostty/README.md) | Optional native shell session in the browser | Follow the platform-specific commands in its README; open `http://127.0.0.1:4040` |
| [linux_release](../guides/linux-releases.md) | Docker build inputs for a release that must run on older Linux | Follow the Linux release guide; this is not a Mix application |

Web host libraries and Ghostty are example dependencies. They are not required
core dependencies. The Ghostty example needs its supported native SDK. Its
Linux ARM64 build has additional steps.

CI runs the existing application, browser, and native checks. See
[CONTRIBUTING.md](../CONTRIBUTING.md) for the core checks. New examples need a
clear user task, local fixtures where possible, and tests for their actual
application.
