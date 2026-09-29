# Backend contract

A backend implements `TermUI.Backend`.

```elixir
@callback init(keyword()) :: {:ok, state()} | {:error, term()}
@callback size(state()) :: {:ok, {rows, columns}} | {:error, term()}
@callback capabilities(state()) :: map()
@callback draw(state(), TermUI.Frame.t()) :: {:ok, state()} | {:error, term()}
@callback flush(state()) :: {:ok, state()} | {:error, term()}
@callback clipboard(state(), TermUI.Clipboard.Operation.t()) ::
            {:ok, state()} | {:error, term()}
@callback poll_event(state(), non_neg_integer()) ::
            {:ok, TermUI.Event.t(), state()} | {:timeout, state()} | {:error, term(), state()}
@callback resize(state(), {rows, columns}) :: {:ok, state()} | {:error, term()}
@callback shutdown(state(), term()) :: :ok
```

`clipboard/2` is optional. The runtime returns a structured unsupported error
when a custom backend does not implement it. The callback must return the next
backend state so clipboard output stays in sequence with draw and cleanup.

The size at the backend boundary is `{rows, columns}`. The runtime converts it
to application dimensions `{columns, rows}`.

`init/1` must not leave partial terminal state after an error. `shutdown/2`
must be safe during error cleanup. `draw/2` must retain the last successful
frame or equivalent backend state so that a later frame can clear old cells.

`TermUI.Test.DeterministicBackend` is the public v2 test boundary. It uses a
fixed size, reports explicit capabilities, accepts normalized event and resize
injection, and captures every complete frame. It does not open a terminal or
call the TTY NIF.

```elixir
alias TermUI.Test.DeterministicBackend

{:ok, runtime} =
  TermUI.start_link(MyApp,
    backend: {
      DeterministicBackend,
      owner: self(),
      size: {12, 40},
      capabilities: %{colors: :ansi_16, unicode: true}
    },
    backend_opts: [size_poll_interval: :disabled]
  )

assert_receive {:backend, :draw, %TermUI.Frame{} = initial}

:ok = DeterministicBackend.send_event(runtime, TermUI.Event.key(:enter))
:ok = DeterministicBackend.resize(runtime, 60, 20)

assert_receive {:backend, :resize, {20, 60}}
assert_receive {:backend, :draw, %TermUI.Frame{width: 60, height: 20}}

TermUI.Runtime.shutdown(runtime)
assert_receive {:backend, :shutdown_snapshot, snapshot}
```

The snapshot contains `:frames` in draw order, the final `:size`, the explicit
`:capabilities`, pending queued events, clipboard operations, flush count, and
`:shutdown_reason`. This test path needs no native terminal state. Use normal
ExUnit message assertions. No v1 component harness or test renderer is used.

Use a SexySpex acceptance specification for a small number of user-visible
workflows that benefit from Given-When-Then documentation across input, state,
and rendered output. Put them in `test/spex/*_spex.exs` and run `mix spex`.
Use normal ExUnit tests for focused units, edge cases, internal contracts, and
most regressions; they are faster to write and keep the main suite cohesive.

The runtime puts each backend behind one serialized owner. State returned by
input, size, draw, flush, and resize callbacks becomes the state for the next
callback and for final cleanup.

## Native build policy

Only the local raw backend can need the TTY NIF. OTP 28 and OTP 29 need this
small native helper to stop the terminal driver from consuming Ctrl+O,
Ctrl+C, Ctrl+S, and Ctrl+Q. The `:tty` backend is the pure BEAM local fallback.
The SSH and deterministic backends also use only BEAM code.

The `TERM_UI_TTY_NIF` build setting has these values:

| Value | Build and runtime behavior |
| --- | --- |
| `auto` | Build from source when `make` and a C compiler exist. Otherwise, do not build the NIF. |
| `source` | Require a source build. Stop with a clear list of missing tools when the toolchain is incomplete. |
| `disabled` | Do not build the NIF. Keep TTY, SSH, deterministic, and custom backends available. |

`auto` is the default. TermUI does not ship precompiled artifacts. The local
raw path loads the NIF on demand. Backend selection falls back to `:tty` when
the NIF is absent and OTP cannot manage control signals. An explicit `:raw`
selection returns a structured `:raw_mode_unavailable` error. It does not
leave the terminal in raw mode.

Size polling uses a 200 ms interval when direct terminal or environment size
checks are available. It uses a 1 second interval when detection must start
`stty`. Set `backend_opts: [size_poll_interval: milliseconds]` to use an
interval of at least 50 ms. Use `:disabled` when the application supplies all
resize events through its backend input stream.

## SSH sessions

`TermUI.Backend.SSH` owns one remote terminal session and one v2 runtime. It
does not start an SSH daemon. Thus, the host application keeps control of
authentication, host keys, network policy, and connection limits.

An application that already owns an SSH server can use the direct session API:

```elixir
{:ok, session} =
  TermUI.Backend.SSH.start_session(MyApp,
    size: {24, 80},
    output: fn data -> MySSHTransport.send(data) end
  )

:ok = TermUI.Backend.SSH.input(session, remote_bytes)
:ok = TermUI.Backend.SSH.resize(session, 40, 120)
:ok = TermUI.Backend.SSH.stop_session(session)
```

Some SSH libraries require output from the channel process. Set `:output` to
that process. It receives this message:

```elixir
{:term_ui_ssh_output, session, token, data}
```

After it sends the data, it must call
`TermUI.Backend.SSH.ack_output(session, token, result)`. Only one output is in
flight. One newer frame can wait, and each later frame replaces the stale
waiting frame. Frame diffs use the last confirmed frame, so a slow client does
not receive an invalid diff.

OTP SSH daemons can use the supplied channel callback:

```elixir
:ssh.daemon(port,
  system_dir: system_dir,
  pwdfun: password_fun,
  ssh_cli: {TermUI.Backend.SSH.Channel, [MyApp, runtime_options: []]}
)
```

The callback accepts PTY input and window changes. It sends Unicode text,
bracketed paste, mouse, focus, and resize values through the normal v2 event
contract. The SSH path does not select raw mode or call the local terminal NIF.
