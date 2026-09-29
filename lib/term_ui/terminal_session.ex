defmodule TermUI.TerminalSession do
  @moduledoc """
  An optional Ghostty emulator and PTY owned by one application process.

  Install `{:ghostty, "== 0.5.0", runtime: false}` in the consumer to use this
  module. Ordinary TermUI backends do not need that package. Ghostty 0.5 has
  native builds for GNU Linux on x86_64 and ARM64, and macOS on ARM64. Other
  platforms return a structured error from `start/1`.

  Each session owns one emulator and one child PTY. Output is
  `{:term_ui_terminal_frame, session, sequence, frame, metadata}`. Store the
  frame in application state, confirm it with `acknowledge/2`, and overlay it
  in the application's complete view. The session keeps one unconfirmed frame
  and one latest waiting frame. A missing confirmation closes the session.

  Use a command to send `{:terminal_input, event}`, `{:terminal_ack, sequence}`,
  or `:terminal_stop` from an Elm update. Start a session in an async command
  with `owner: runtime_pid`; the async worker must not be the owner. Widgets
  remain pure. The command and argument list are trusted host settings.

  The owner receives `{:term_ui_terminal_closed, session, reason}` after
  cleanup. Owner exit also closes both children. Mouse coordinates are cells;
  Ghostty 0.5 limits encoded mouse input to its fixed 80 by 30 area. Wheel
  events scroll emulator history. Cursor shape and overline are not part of
  the TermUI frame contract.
  """

  @doc "Starts an unlinked session. The owner defaults to the caller."
  @spec start(keyword()) :: GenServer.on_start()
  def start(opts \\ []) do
    opts = Keyword.put_new(opts, :owner, self())
    GenServer.start(Module.concat(__MODULE__, Server), opts)
  end

  @doc "Returns the owned process IDs, dimensions, and output queue counts."
  @spec info(pid()) :: map()
  def info(session), do: GenServer.call(session, :info)

  @doc "Sends normalized terminal input to the child program."
  @spec input(pid(), TermUI.Event.t()) :: :ok | {:error, term()}
  def input(session, event), do: GenServer.call(session, {:input, event})

  @doc "Confirms a frame after the application stores it."
  @spec acknowledge(pid(), pos_integer()) :: :ok | {:error, term()}
  def acknowledge(session, sequence), do: GenServer.call(session, {:ack, sequence})

  @doc "Closes the PTY and emulator."
  @spec stop(pid()) :: :ok
  def stop(session), do: GenServer.stop(session, :normal)
end
