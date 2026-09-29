# Optional terminal sessions

Use `TermUI.TerminalSession` to run a shell or terminal program inside a TermUI
application. This is an optional capability. Raw, TTY, SSH, deterministic, and
ordinary browser backends do not need an emulator or PTY dependency.

Install this dependency in the consumer:

```elixir
{:ghostty, "== 0.5.0", runtime: false}
```

The adapter uses the public Ghostty 0.5 API. Its native builds support GNU Linux
on x86_64 and ARM64, and macOS on ARM64. Windows, Intel macOS, musl Linux, and
other systems return `{:error, {:unsupported_platform, os, architecture}}`.
A missing package or native module returns
`{:error, {:ghostty_unavailable, module, reason}}`. These errors do not disable
other TermUI backends.

The Ghostty 0.5.0 Linux ARM64 archive is mislabeled: its ELF libraries are
x86_64. Use the example's `build_native.sh` with Zig 0.15.2 on a native Linux
ARM64 host. It builds the SDK's pinned Ghostty source and both NIFs. Install
Zigler as a consumer build dependency and keep `GHOSTTY_BUILD=1` while compiling
or running that source build. The other supported targets use the published
assets. CI checks the source build on Linux ARM64; it does not treat the broken
precompiled archive as a pass.

## Ownership and commands

The parent runtime owns application state. The session owns one emulator and
one PTY. Start it through an async command, with the runtime as owner. Capture
the owner PID in `init/1`, before the command starts:

```elixir
owner = self()
Command.async(
  fn -> TermUI.TerminalSession.start(owner: owner, cmd: "/bin/sh", size: {20, 80}) end,
  &{:session_started, &1}
)
```

An async return is wrapped by the command runner. A successful start reaches
the mapper as `{:ok, {:ok, session}}`. The async worker must not own the session.
Choose the command and arguments in trusted host code. Never let browser data
select the executable, arguments, driver, or BEAM module.

The session sends:

```elixir
{:term_ui_terminal_frame, session, sequence, frame, metadata}
```

Store the frame in the parent's state and return
`Command.send(session, {:terminal_ack, sequence})`. Use `Frame.overlay/4` in
the parent's `view/1` to include that frame in its one complete view. A widget
does not own a process or run terminal effects.

Send normalized input with `Command.send(session, {:terminal_input, event})`.
Translate application mouse coordinates to the terminal region. Send resize
events for that region, not the whole application frame. These operations also
have synchronous API forms for non-Elm hosts.

The session has one unconfirmed frame and one latest waiting frame. New output
replaces the waiting frame. It renders at most once per 16 ms output batch.
The default confirmation timeout is five seconds. Initial and resized dimensions
are limited to 300 columns and 120 rows; scrollback defaults to 1,000 lines and
is limited to 10,000. Output chunks above 65,536 bytes or a data mailbox above
1,024 messages close the session. These checks bound session output; the host
must still limit incoming connections and events.

`info/1` reports the emulator, PTY, size, and output queue. Natural child exit
sends a final frame. After the parent confirms it, the session closes both
children and sends `{:term_ui_terminal_closed, session, {:exit, status}}`.
Explicit stop, owner exit, and output timeout also close both children. Force
killing the session releases its linked native owners. Tested shell and Vim
children stop with them. Ghostty closes a child with SIGHUP.

## Conversion and input limits

`TermUI.TerminalSession.Frame.from_snapshot/2` is pure. It converts Unicode,
wide cells, RGB colors, backgrounds, supported attributes, and the visible
cursor position to the existing frame contract. Overline and native cursor
shape, color, or blink are outside that contract. Metadata preserves native
cursor, scrollbar, mouse, and focus settings for the parent.

Terminal query replies go back to the owned PTY. Keyboard encoding uses the
emulator's current modes. Paste queries bracketed-paste mode and uses its
current setting. The adapter removes ESC bytes inside a bracketed paste so
pasted text cannot end that bracket early. Its own mode query reply is not
sent to the child. Focus events are sent only when focus reporting is active.

Ghostty 0.5's mouse encoder uses fixed 10 by 20 pixel cells in an 800 by 600
pixel area. The adapter converts cell positions to that geometry and rejects
positions beyond 80 columns or 30 rows. The example limits its terminal region
to this area. Wheel events scroll emulator history. Larger text frames are
supported, but mouse encoding beyond this area returns an error.

## Shared display path

The [shell example](https://github.com/agentjido/term_ui/tree/next/v2/examples/ghostty)
uses normal Elm callbacks and the browser backend. It stores emulator frames,
then overlays them in a complete application view. The existing DOM renderer
displays these frames exactly as it displays ordinary application output.

Native acceptance checks use real PTYs and Vim. Browser checks use Chromium,
the same packaged JavaScript and CSS, a real shell, Vim, resize, two isolated
connections, and OS child cleanup. Other browser engines remain unverified.
