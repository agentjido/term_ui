# Physical terminal checks for issues #5, #6, and #35

The automated checks pass real PTY and Windows ConPTY input. These checks
need the physical key and the user's terminal frontend. Do not replace a
missing physical result with an injected-key result.

Use separate clean checkouts of `maint/1.x` and `next/v2`. Record the exact
commit from `git rev-parse HEAD`, OS, terminal name, version, and profile.
Run `mix deps.get` and `mix compile` before the input check. Windows Raw
needs the C build tools described in the backend guide. Build in the native
tools shell, then run in the terminal profile under test.

The existing console probe is `test/support/windows_console_probe.exs` on
both branches. It shows a colored screen, `READY`, Unicode text, and a final
`!` cell. It records normalized input and normal owner cleanup. The probe
does not edit a text widget; the widget word-deletion tests are separate.

## macOS Option+Delete

In the normal terminal profile, save the settings and run the Raw probe:

```sh
stty -g > /tmp/term-ui-manual-before.txt
TERM_UI_CONSOLE_BACKEND=raw \
TERM_UI_CONSOLE_PROGRESS=/tmp/term-ui-manual-input.json \
mix run test/support/windows_console_probe.exs
```

Type `one two`. Press the physical Option+Delete key. Type `X`. Repeat with
Unicode text. Press `q` to exit. Do not paste an escape sequence in place of
the key. Then run:

```sh
stty -g > /tmp/term-ui-manual-after.txt
diff /tmp/term-ui-manual-before.txt /tmp/term-ui-manual-after.txt
cat /tmp/term-ui-manual-input.json.result
```

The settings comparison must have no difference. The result must show an
Alt+Backspace event, subsequent input including `X`, a normal exit reason,
and stopped owners and reader. V2 reports text in `text` fields; v1 reports
it in `key` fields. Repeat on the other version branch.

If the key produces another event, record that event and the terminal's
Option-key setting. Do not change the profile before recording its result.
Issue #35 also needs the existing Unicode word-deletion and continued-input
tests. Those tests and injected ESC+DEL/ESC+Backspace PTY checks already pass.

## Windows Terminal and Mintty

Check Windows Terminal with the normal Command Prompt or PowerShell profile.
Check a separate Git Bash Mintty window too. Git Bash inside ConPTY has
already passed; it is a separate frontend check.

In PowerShell, run:

```powershell
$env:TERM_UI_CONSOLE_BACKEND = "raw"
$env:TERM_UI_CONSOLE_PROGRESS = "$env:TEMP\term-ui-manual-input.json"
mix run test/support/windows_console_probe.exs
```

In Git Bash, run:

```sh
TERM_UI_CONSOLE_BACKEND=raw \
TERM_UI_CONSOLE_PROGRESS="$(cygpath -w /tmp/term-ui-manual-input.json)" \
mix run test/support/windows_console_probe.exs
```

Type Unicode text and a space. Press Up, Ctrl+O, Ctrl+C, Ctrl+S, and Ctrl+Q.
Resize the window. Check the colored rows, wide text, and final `!` cell.
Type `q` to exit. Read the `.result` file in the chosen temporary directory.
It must show each expected event, the changed size, a normal exit, and stopped
owners and reader. Confirm that ordinary shell input and display work after
exit. Repeat on both version branches.

Repeat with `TERM_UI_CONSOLE_BACKEND=tty`. TTY uses line input; press Enter
after text and after `q`. Its native shell controls can stay active, so the
Raw control-key expectations do not apply to this mode.

If Raw is unavailable, record the exact error and whether TTY works. This
can establish a frontend support limit; it is not a passing Raw result.
Keep #5 and #6 open until their physical results have a clear resolution.

## Result to return

Return the branch and SHA, OS and frontend, profile settings, backend, key
events, resize result, exit and cleanup result, and any error. No credentials
or live provider are needed. Keep the original terminal profile settings.
