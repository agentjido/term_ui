# Learn from the examples

The four examples are separate consumer Mix projects. They use the library
through its public API. Host libraries stay in the consumer so that a terminal
application does not have to install a web server or terminal emulator.

Read them in this order. Each README has run commands, expected behavior,
source guidance, and checks.

After the counter, use the [widget recipes](widget-recipes.md). They run in
the same consumer and show input/focus, forms, row identity, and bounded
stream updates. Each lesson links to source and behavior tests.

| Order | Lesson | Main result |
| --- | --- | --- |
| 1 | [Counter](https://github.com/agentjido/term_ui/blob/main/examples/iex_counter/README.md) | Input becomes a message, state becomes one complete frame, quit becomes command data |
| 2 | [Showcase](https://github.com/agentjido/term_ui/blob/main/examples/showcase/README.md) | One parent composes pure widgets and collects external data through commands |
| 3 | [Browser host](https://github.com/agentjido/term_ui/blob/main/examples/web/README.md) | The same application contract runs in isolated browser sessions |
| 4 | [Ghostty shell host](https://github.com/agentjido/term_ui/blob/main/examples/ghostty/README.md) | A parent overlays a real terminal frame and owns input and cleanup commands |

The counter and showcase run in a local terminal. The web example adds Bandit,
WebSock, and Jason. Ghostty adds an optional native PTY and emulator dependency;
it is a shell host example, not the local TTY input NIF. Read its platform limits
before use. Windows and Intel macOS are not supported by that example.

CI checks each consumer. Counter and showcase tests run their application
code; browser tests inspect rendered cells and events in Chromium. Ghostty
checks real shell children, native frames, and cleanup on its supported CI
platforms. See [testing](testing.md) for what each layer can prove.

The Oracle Linux files are a consumer build recipe, not a fifth application.
Read [Linux releases](linux-releases.md) when a native dependency must load on
an older glibc target. Its files are in `docs/recipes/linux-release`.
