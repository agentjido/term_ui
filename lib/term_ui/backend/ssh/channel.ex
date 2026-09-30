defmodule TermUI.Backend.SSH.Channel do
  @moduledoc """
  An OTP `:ssh_server_channel` callback for TermUI sessions.

  Use this module as an SSH daemon `:ssh_cli` callback. The daemon owner must
  configure host keys, authentication, connection limits, and all network
  policy.

      :ssh.daemon(port,
        system_dir: system_dir,
        pwdfun: password_fun,
        ssh_cli: {TermUI.Backend.SSH.Channel, [MyApp, runtime_options: []]}
      )

  One callback process starts one isolated `TermUI.Backend.SSH` session when
  the client requests a shell. PTY input and window changes stay scoped to
  that channel.
  """

  @behaviour :ssh_server_channel

  alias TermUI.Backend.SSH

  @default_size {24, 80}
  @default_send_timeout 5_000
  @failure_status 1

  @impl true
  def init([root, opts]) when is_atom(root) and is_list(opts) do
    {:ok,
     %{
       root: root,
       options: opts,
       connection: nil,
       channel: nil,
       session: nil,
       size: @default_size,
       terminal: nil,
       send_timeout: Keyword.get(opts, :send_timeout, @default_send_timeout)
     }}
  end

  def init([root]) when is_atom(root), do: init([root, []])
  def init(args), do: {:stop, {:invalid_ssh_channel_options, args}}

  @impl true
  def handle_msg({:ssh_channel_up, channel, connection}, state) do
    {:ok, %{state | channel: channel, connection: connection}}
  end

  def handle_msg(
        {:term_ui_ssh_output, session, token, data},
        %{session: session, connection: connection, channel: channel} = state
      ) do
    result = :ssh_connection.send(connection, channel, 0, data, state.send_timeout)
    :ok = SSH.ack_output(session, token, result)

    case result do
      :ok ->
        {:ok, state}

      {:error, reason} ->
        SSH.disconnect(session, {:ssh_send_failed, reason})
        {:stop, channel, state}
    end
  end

  def handle_msg(
        {:term_ui_ssh_closed, session, reason},
        %{session: session, connection: connection, channel: channel} = state
      ) do
    _status = :ssh_connection.exit_status(connection, channel, exit_status(reason))
    _eof = :ssh_connection.send_eof(connection, channel)
    {:stop, channel, state}
  end

  def handle_msg({:EXIT, session, reason}, %{session: session, channel: channel} = state)
      when not is_nil(session) do
    {:stop, channel, %{state | session: nil, options: Keyword.put(state.options, :exit, reason)}}
  end

  def handle_msg(_message, state), do: {:ok, state}

  @impl true
  def handle_ssh_msg(
        {:ssh_cm, connection, {:pty, channel, want_reply, pty}},
        state
      ) do
    {_terminal, width, height, _pixel_width, _pixel_height, _modes} = pty
    size = {nonzero(height, 24), nonzero(width, 80)}
    terminal = elem(pty, 0)
    _reply = :ssh_connection.reply_request(connection, want_reply, :success, channel)
    {:ok, %{state | connection: connection, channel: channel, size: size, terminal: terminal}}
  end

  def handle_ssh_msg(
        {:ssh_cm, connection, {:shell, channel, want_reply}},
        %{session: nil} = state
      ) do
    session_opts =
      state.options
      |> Keyword.put(:output, self())
      |> Keyword.put(:owner, self())
      |> Keyword.put(:size, state.size)
      |> Keyword.put(:capabilities, channel_capabilities(state))

    case SSH.start_session(state.root, session_opts) do
      {:ok, session} ->
        _reply = :ssh_connection.reply_request(connection, want_reply, :success, channel)
        {:ok, %{state | connection: connection, channel: channel, session: session}}

      {:error, reason} ->
        _reply = :ssh_connection.reply_request(connection, want_reply, :failure, channel)

        _output =
          :ssh_connection.send(connection, channel, 1, inspect(reason), state.send_timeout)

        _status = :ssh_connection.exit_status(connection, channel, @failure_status)
        _eof = :ssh_connection.send_eof(connection, channel)
        {:stop, channel, state}
    end
  end

  def handle_ssh_msg(
        {:ssh_cm, connection, {:shell, channel, want_reply}},
        state
      ) do
    _reply = :ssh_connection.reply_request(connection, want_reply, :failure, channel)
    {:ok, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection, {:data, channel, 0, data}},
        %{session: session, channel: channel} = state
      )
      when is_pid(session) do
    case SSH.input(session, data) do
      :ok -> {:ok, state}
      {:error, _reason} -> {:stop, channel, state}
    end
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection,
         {:window_change, channel, width, height, _pixel_width, _pixel_height}},
        %{session: session, channel: channel} = state
      )
      when is_pid(session) do
    size = {nonzero(height, elem(state.size, 0)), nonzero(width, elem(state.size, 1))}

    case SSH.resize(session, elem(size, 0), elem(size, 1)) do
      :ok -> {:ok, %{state | size: size}}
      {:error, _reason} -> {:ok, state}
    end
  end

  def handle_ssh_msg(
        {:ssh_cm, _connection, {:eof, channel}},
        %{session: session, channel: channel} = state
      ) do
    if is_pid(session), do: SSH.disconnect(session, :eof)
    {:stop, channel, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, connection, {:exec, channel, want_reply, _command}},
        state
      ) do
    _reply = :ssh_connection.reply_request(connection, want_reply, :failure, channel)
    _status = :ssh_connection.exit_status(connection, channel, @failure_status)
    _eof = :ssh_connection.send_eof(connection, channel)
    {:stop, channel, state}
  end

  def handle_ssh_msg(
        {:ssh_cm, connection, {:env, channel, want_reply, _name, _value}},
        state
      ) do
    _reply = :ssh_connection.reply_request(connection, want_reply, :failure, channel)
    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _connection, {:signal, _channel, _signal}}, state),
    do: {:ok, state}

  def handle_ssh_msg({:ssh_cm, _connection, {:data, _channel, _type, _data}}, state),
    do: {:ok, state}

  def handle_ssh_msg(_message, state), do: {:ok, state}

  @impl true
  def terminate(reason, state) do
    if is_pid(state.session), do: SSH.disconnect(state.session, {:channel_terminated, reason})
    :ok
  end

  defp channel_capabilities(state) do
    configured = Keyword.get(state.options, :capabilities, %{})

    defaults =
      if dumb_terminal?(state.terminal) do
        %{colors: :monochrome, unicode: false, mouse: false}
      else
        %{
          colors: :true_color,
          unicode: true,
          mouse: Keyword.get(state.options, :mouse_tracking, :none) != :none
        }
      end

    defaults
    |> Map.merge(configured)
    |> Map.put(:paste, Keyword.get(state.options, :bracketed_paste, true))
    |> Map.put(:focus, Keyword.get(state.options, :focus_events, true))
    |> Map.put(:dimensions, state.size)
    |> Map.put(:remote, :ssh)
  end

  defp dumb_terminal?(terminal) when is_binary(terminal), do: terminal == "dumb"
  defp dumb_terminal?(terminal) when is_list(terminal), do: terminal == ~c"dumb"
  defp dumb_terminal?(_terminal), do: false

  defp nonzero(value, _fallback) when is_integer(value) and value > 0, do: value
  defp nonzero(_value, fallback), do: fallback

  defp exit_status(reason) when reason in [:normal, :shutdown], do: 0
  defp exit_status({:shutdown, _reason}), do: 0
  defp exit_status(_reason), do: @failure_status
end
