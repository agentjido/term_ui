# Browser example

Run a normal Elm application through `TermUI.WebBackend` and the packaged DOM
renderer. Bandit, WebSock, and JSON encoding belong to this example. They are
not required TermUI dependencies. This example does not need the local TTY NIF
or Ghostty.

```sh
cd examples/web
mix deps.get
mix run --no-halt
```

Open <http://127.0.0.1:4040>. Use Space or Up to add one. Type Unicode text,
paste, click, or resize the window. Press q for normal shutdown. Reconnect starts
a new application state. Each connection has its own runtime and session owner.

The host binds to `127.0.0.1`. It permits only the matching HTTP origin and host.
The application module is fixed on the server. Input is limited to 70,000 bytes
per complete WebSocket message and 300 messages per second. The backend also
limits decoded text, paste, dimensions, and queued events. The browser limits
its pending input buffer. Add authentication, authorization, TLS, and connection
limits in your host before you make this local example available to other users.

The [WebSock contract](https://websock.hexdocs.pm/WebSock.html) defines the host
callbacks. Keep authentication and origin checks before the WebSocket upgrade.

## Checks

```sh
mix hex.audit
mix test --warnings-as-errors
npm ci --ignore-scripts
npx playwright install chromium
npm test
npm run benchmark
```

The Playwright tests start and stop their own server. They check actual rendered
cells, RGB and palette colors, wide characters, changed rows, styles, cursor,
Unicode input, modifiers, IME composition, paste, mouse, focus, resize, normal
shutdown, reconnect, separate sessions, origin checks, and invalid input.

The benchmark uses a real Chromium browser. It reports DOM update and synchronous
layout time, plus encoded message sizes. It excludes the server, network, and
paint. It is a measurement, with no device-dependent speed assertion in CI.
See [the web guide](../../guides/web.md) for the protocol and measured limits.
