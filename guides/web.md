# Browser backend

Use `TermUI.WebBackend` for a normal Elm application in a browser. Application
callbacks, commands, normalized events, pure widgets, and complete frames use
the same contract as local and SSH applications. The session owner supplies
browser display and input. It does not open a local terminal.

The package includes `priv/web/term_ui.js` and `priv/web/term_ui.css`. Serve them
from the host, then create a client:

```html
<link rel="stylesheet" href="/assets/term_ui.css">
<div id="terminal" style="width:100%;height:500px"></div>
<script type="module">
  import {connectTermUI} from "/assets/term_ui.js";
  const client = connectTermUI(document.querySelector("#terminal"), "/ws");
  // client.reconnect() starts a new connection. client.close() releases the view.
</script>
```

Use a WebSocket URL accepted by the browser, such as `ws://127.0.0.1:4040/ws`
for the local example or `wss://your-host/ws` for a TLS host. Give the container
an explicit height. The client measures its font and container, then reports
columns and rows. Default browser limits match the backend: 300 columns and
120 rows. Supply `maxColumns` and `maxRows` when the host selects different
limits. The backend Frame bounds still apply.

The complete [example](https://github.com/agentjido/term_ui/tree/main/examples/web)
has a fixed counter application, a WebSock host, input limits, and browser checks.
The host owns authentication, authorization, origin, allowed application modules,
JSON encoding, message bytes, rates, and connection limits. TermUI has no required
web framework. A browser cannot select a BEAM module.

## Output and recovery

Protocol version 1 carries complete changed rows. Each cell includes Unicode
text, terminal width, foreground, background, and attributes. Cursor positions
are one-based. Mouse positions use the existing zero-based event contract.
See `TermUI.WebBackend.Protocol` and [the backend guide](backend.md).

A wide character occupies two columns. Its following placeholder is hidden.
Blank cells still carry backgrounds. The client sets text through `textContent`;
cell text does not execute HTML. It validates the complete message before it
changes the screen. Named, indexed, and RGB colors use a fixed color conversion.

A changed-row frame must match the client's confirmed sequence and dimensions.
An unknown base requests resync. A complete frame replaces all rows. The client
confirms a frame after applying it to the DOM. The session has one frame in
flight and one waiting frame. New output replaces the waiting frame while an
acknowledgement is pending. This bounds output for a slow client.

Normal shutdown accepts the final frame acknowledgement before it closes the
connection. Disconnect and owner exit release the runtime immediately. An output
timeout stops the runtime and reports an error. Reconnect creates new application
state and starts with a complete frame. It does not recover old application state.

## Input

Printable input becomes `Event.Text`. Named keys and Ctrl, Alt, or Meta keys
become `Event.Key`. Shift-only printable keys stay text. IME composition sends
one committed text event. Paste sends one `Event.Paste`. Focus, resize, mouse
press/release, move/drag, and wheel input use their existing event types.
Mouse moves are limited to one per browser animation frame. The application
owns the response to each event.

## Renderer decision and limits

The v2 renderer uses DOM cells. It updates changed cells in complete changed
rows and reuses the existing nodes. This keeps fixed terminal columns, Unicode
widths, CSS styles, browser text, and one renderer path. There is no Canvas path.

Measured on macOS ARM64 with Chromium 153.0.8010.12 and Playwright 1.63.0:

| Frame | Cells | Complete update p95 | One changed row p95 | Complete JSON bytes | Row JSON bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 80 × 24 | 1,920 | 12.5 ms | 1.0 ms | 58,243 | 2,522 |
| 160 × 50 | 8,000 | 54.1 ms | 1.2 ms | 242,043 | 4,939 |
| 200 × 100 | 20,000 | 137.7 ms | 1.4 ms | 604,795 | 6,150 |

Each size uses 15 complete updates and 30 row updates. These times include DOM
update and synchronous layout. They exclude server work, network, and paint.
The benchmark source is `examples/web/test/browser/benchmark.mjs`.

The results support DOM for normal terminal sizes and row updates. A dense
200 × 100 frame does not support 60 complete updates per second in this check.
Use bounded output and changed rows for large displays. Recheck Canvas if a
future application requires frequent complete large frames. This release keeps
one renderer and reports this limit.

The current automated browser check uses Chromium. Other browser engines and
physical mobile keyboards remain unverified. See [optional terminal sessions](terminal-session.md)
to embed a shell in the same frame path. Normal browser applications need no emulator.
