defmodule TermUIGhosttyExample.App do
  @moduledoc false
  use TermUI.Elm

  alias TermUI.{Command, Event, Frame, TerminalSession}

  @impl true
  def init(opts) do
    owner = self()
    dimensions = Keyword.fetch!(opts, :dimensions)
    size = terminal_size(dimensions)
    command = Keyword.get(opts, :terminal_command, System.get_env("SHELL") || "/bin/sh")
    args = Keyword.get(opts, :terminal_args, [])

    state = %{
      dimensions: dimensions,
      session: nil,
      frame: nil,
      status: "Starting shell",
      notice: ""
    }

    {state,
     [
       Command.async(
         fn -> TerminalSession.start(owner: owner, size: size, cmd: command, args: args) end,
         &{:session_started, &1}
       )
     ]}
  end

  @impl true
  def event_to_msg(event, _state), do: {:msg, {:event, event}}

  @impl true
  def update({:session_started, _result}, %{status: "Shell closed"} = state), do: state

  def update({:session_started, {:ok, {:ok, session}}}, state) do
    state = %{state | session: session, status: "Shell"}
    {rows, columns} = terminal_size(state.dimensions)
    {state, input_commands(state, Event.resize(columns, rows))}
  end

  def update({:session_started, result}, state),
    do: %{state | status: "Shell unavailable", notice: inspect(result)}

  def update({:event, %Event.Key{key: "q", modifiers: modifiers} = event}, state) do
    if :ctrl in modifiers and :alt in modifiers,
      do: {state, [Command.shutdown(:normal)]},
      else: {state, input_commands(state, event)}
  end

  def update({:event, %Event.Resize{width: width, height: height}}, state) do
    state = %{state | dimensions: {width, height}}
    {rows, columns} = terminal_size(state.dimensions)
    {state, input_commands(state, Event.resize(columns, rows))}
  end

  def update({:event, %Event.Mouse{x: x, y: y} = event}, state) when y >= 2 and x < 80 and y < 32,
    do: {state, input_commands(state, %{event | y: y - 2})}

  def update({:event, %Event.Mouse{}}, state), do: state
  def update({:event, event}, state), do: {state, input_commands(state, event)}

  @impl true
  def handle_info({:term_ui_terminal_frame, session, sequence, frame, _metadata}, state) do
    {%{state | session: session, frame: frame},
     [Command.send(session, {:terminal_ack, sequence})]}
  end

  def handle_info({:term_ui_terminal_closed, _session, reason}, state),
    do: %{state | session: nil, status: "Shell closed", notice: inspect(reason)}

  def handle_info({:term_ui_terminal_error, _session, reason}, state),
    do: %{state | notice: inspect(reason)}

  def handle_info(_message, state), do: state

  @impl true
  def view(state) do
    {width, height} = state.dimensions

    frame =
      Frame.from_rows(
        ["TermUI shell · #{state.status}", "Ctrl+Alt+Q: close. #{state.notice}"],
        width,
        height
      )

    if state.frame, do: Frame.overlay(frame, state.frame, 1, 3), else: frame
  end

  defp terminal_size({width, height}), do: {max(1, min(height - 2, 30)), min(width, 80)}
  defp input_commands(%{session: nil}, _event), do: []

  defp input_commands(%{session: session}, event),
    do: [Command.send(session, {:terminal_input, event})]
end
