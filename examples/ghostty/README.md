# Optional shell in the browser

This example adds a real shell to a normal TermUI Elm application. The parent
stores each complete terminal frame and overlays it below two application rows.
It returns commands for input and frame confirmations. It uses the same browser
renderer as `examples/web`. There is no second terminal renderer.

Run on GNU Linux (x86_64 or ARM64) or macOS ARM64:

```sh
cd examples/ghostty
mix deps.get
TERM=xterm-256color mix run --no-halt
```

Open `http://127.0.0.1:4040`. Type in the shell. Use Ctrl+Alt+Q to close its web
runtime. Reconnect starts a new runtime and shell. Each browser connection has
its own shell. The example uses Ghostty 0.5.0 as an optional consumer dependency.
The terminal region is at most 80 columns and 30 rows, to match that version's
mouse encoder. The outer application frame still follows browser dimensions.

The host binds to loopback and checks the exact origin. Shell commands and
arguments come from the host. Browser input cannot select a module or command.
Keep this example on loopback. Add authentication, shell access policy, host
limits, and isolation before making a shell available over a network.

Checks:

```sh
TERM=xterm-256color mix test --warnings-as-errors
cd ../web
npm ci --ignore-scripts
npx playwright install chromium
cd ../ghostty
node ../web/node_modules/@playwright/test/cli.js test
```

The native checks need Python 3 and Vim. They test real PTYs, query replies,
keyboard and mouse input, bracketed paste, focus, resize, scrollback, Vim,
separate sessions, and normal/forced/owner cleanup. They verify that the OS
child is gone. Chromium checks use the shared renderer with a real shell and
Vim, two browser connections, resize, and child cleanup.

See [the session guide](../../guides/terminal-session.md) for the ownership
contract and the native SDK limits.
