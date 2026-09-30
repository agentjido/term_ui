# Terminal

TermUI selects a backend, parses its input into `TermUI.Event` structs, and
restores owned terminal state at shutdown.

## Raw and TTY modes

| | Raw | TTY |
|---|---|---|
| Minimum OTP | 28 | 26 |
| Terminal mode | character-at-a-time | cooked; may buffer until Enter |
| Typical use | standalone Unix TUI | IEx, remsh, constrained terminals |
| Runtime alternate screen | yes | yes |
| Runtime buffer strategy | double-buffered differential | temporary full frame |
| Local mouse setup | enabled except WSL/ConPTY | not enabled by runtime |

With `backend: :auto`, a standalone runtime tries Raw and falls back to TTY.
Inside IEx it selects TTY directly so the shell keeps terminal ownership.

```elixir
TermUI.Runtime.run(root: MyApp)                # automatic
TermUI.Runtime.run(root: MyApp, backend: :raw)
TermUI.Runtime.run(root: MyApp, backend: :tty)
```

Forcing Raw fails if native Raw mode cannot be acquired. TTY calls can block in
their dedicated input process while the render loop continues.

## Alternate screen and cursor

The runtime enters the alternate screen for both local backends, hides the
cursor, and restores both on normal shutdown. `TermUI.Backend.TTY` has a
standalone `alternate_screen: false` default, but `TermUI.Runtime` explicitly
passes true.

Direct `TermUI.Terminal` calls are Raw/local primitives and can conflict with a
running runtime. Prefer runtime ownership. If you use them independently, pair
every setup operation with cleanup:

```elixir
{:ok, _state} = TermUI.Terminal.enable_raw_mode()
:ok = TermUI.Terminal.enter_alternate_screen()
:ok = TermUI.Terminal.hide_cursor()

# later
:ok = TermUI.Terminal.show_cursor()
:ok = TermUI.Terminal.leave_alternate_screen()
:ok = TermUI.Terminal.disable_raw_mode()
```

Use `TermUI.ANSI` to generate low-level clear or cursor-position sequences;
`TermUI.Terminal` does not expose `clear_screen/0` or
`set_cursor_position/2`.

## Mouse

Raw runtime setup requests all mouse reporting modes and parses SGR mouse input
into 0-based `%TermUI.Event.Mouse{x: column, y: row}` coordinates. WSL/ConPTY
mouse tracking is intentionally disabled because cleanup sequences are not
reliable. TTY may parse mouse sequences if an external host emits them, but the
runtime does not enable local TTY mouse reporting.

Always provide keyboard alternatives for mouse interactions.

## Focus and paste

The input parser understands focus sequences and bracketed paste payloads, but
the runtime does not automatically enable either terminal reporting mode in
1.0. `TermUI.Focus` and `TermUI.Clipboard` provide enable/disable sequences for
custom terminal integrations. When enabled by the host:

```elixir
def event_to_msg(%TermUI.Event.Focus{action: :gained}, _state),
  do: {:msg, :focused}

def event_to_msg(%TermUI.Event.Paste{content: text}, _state),
  do: {:msg, {:paste, text}}
```

Without bracketed-paste reporting, pasted bytes arrive as ordinary key input.

## Restore the screen

Call `TermUI.Runtime.force_render(runtime)` after external output damages the
screen. The runtime clears previous output, resets terminal styles, and renders
the complete current view. This works even when application state is unchanged.
Do not send clear-screen sequences from a widget; the runtime owns the backend.

A focus-gained event also restores the screen when the application ignores the
event. The host must enable focus reporting to receive those terminal events.
Ordinary state updates still use differential output.

On Unix with `SIGCONT` support, the runtime also restores the screen after the
process resumes from the background. Raw restores its input flags and active
terminal features. TTY restores its output features and keeps the active input
mode. The saved settings for final shutdown are not replaced on resume.

OTP 26 does not expose `SIGCONT` to application handlers. On that version, use
`force_render/1` or enable focus reporting to request screen recovery.

## Size and resize

`TermUI.Terminal.get_terminal_size/0` returns `{:ok, {rows, cols}}` for a local
terminal. Runtime resize events use `%TermUI.Event.Resize{width: cols,
height: rows}`.

OTP 26 TTY operation can query size, but its signal API does not expose
`SIGWINCH` to application handlers. Automatic local resize therefore requires a
newer OTP. Raw already requires OTP 28. An SSH host must forward channel window
changes to the session runtime.

## Capabilities and character sets

`TermUI.Runtime.capabilities/0` exposes detected TTY color, Unicode, dimension,
and terminal information. `TermUI.App.supports?/1` provides convenience color
and Unicode queries. Capability values describe detection, not a guarantee
that the runtime enabled every reporting feature.

Runtime context selects Unicode/ASCII from detected capabilities; the
application `character_set` setting is only the fallback when no
runtime-managed value exists in 1.0. Use `TermUI.CharacterSet` helpers when
drawing UI glyphs. Common widgets degrade to ASCII, but Braille visuals and a
few specialized/legacy code paths have limitations documented in the
[widget compatibility guide](../../docs/widget-compatibility.md). Color options
range from monochrome through 16/256 colors and true color.

## SSH

`TermUI.Backend.SSH` is an explicit custom backend for an OTP SSH channel
device, not an automatic TTY fallback. Each connection gets independent runtime
and buffer state. The channel host sends `{:ssh_input, event}` and
`{:ssh_resize, rows, cols}` to that runtime.

## Platform support

- Linux and macOS Unix terminals are the supported local targets.
- WSL uses Unix paths with mouse disabled; verify the specific deployment
  terminal.
- Native Windows support is experimental. TermUI does not configure Win32
  console modes or implement native Raw input and resize handling.

## Cleanup

Runtime cleanup stops input first, shuts down the backend/buffers, restores the
terminal and cursor, restores local logger output, and uses defensive local
TTY/stty cleanup. Custom backends perform their own device cleanup. A root Elm
`terminate/2` callback is not invoked by the runtime.

Next: [Commands](09-commands.md).

## Windows native control input

Raw mode on Windows also disables the console's processed-input flag. The
terminal owner keeps the flag token and restores it after cooked mode. This
allows Ctrl+C to reach the application on OTP 28.

Build this small NIF in a Microsoft C/C++ developer shell with `cl` and
`nmake` on PATH. The package includes its source and `Makefile.win`. Automatic
selection uses TTY if native control setup is unavailable. TTY input and Unix
raw input do not require this Windows build.
