defmodule TermUI.Integration.SSHNetworkTest do
  use ExUnit.Case, async: false

  alias TermUI.{Command, Event, Runtime}
  alias TermUI.Test.AnsiScreen

  defmodule Root do
    use TermUI.Elm

    @impl true
    def init(opts) do
      state = %{
        width: Keyword.fetch!(opts, :ssh_columns),
        height: Keyword.fetch!(opts, :ssh_rows),
        label: "A",
        phase: :full
      }

      {state, []}
    end

    @impl true
    def event_to_msg(%Event.Key{key: :up, modifiers: []}, _state), do: {:msg, {:label, "U"}}
    def event_to_msg(%Event.Key{key: "b", modifiers: []}, _state), do: {:msg, {:label, "B"}}
    def event_to_msg(%Event.Key{key: "s", modifiers: []}, _state), do: {:msg, :shrink}
    def event_to_msg(%Event.Key{key: "f", modifiers: []}, _state), do: {:msg, :full}
    def event_to_msg(%Event.Key{key: "q", modifiers: []}, _state), do: {:msg, :quit}

    def event_to_msg(%Event.Resize{width: width, height: height}, _state),
      do: {:msg, {:resize, width, height}}

    def event_to_msg(_event, _state), do: :ignore

    @impl true
    def update({:label, label}, state), do: {%{state | label: label}, []}
    def update(:shrink, state), do: {%{state | phase: :shrink}, []}
    def update(:full, state), do: {%{state | phase: :full}, []}
    def update(:quit, state), do: {state, [Command.quit()]}

    def update({:resize, width, height}, state),
      do: {%{state | width: width, height: height}, []}

    @impl true
    def view(state) do
      rows =
        for row <- 1..state.height do
          case {state.phase, row == state.height} do
            {:shrink, true} -> "!"
            {:shrink, false} -> state.label
            {:full, true} -> String.duplicate(".", state.width - 1) <> "!"
            {:full, false} -> String.duplicate(state.label, state.width)
          end
        end

      {:text, Enum.join(rows, "\n")}
    end
  end

  # V1 exposes an IO-device backend. The application host owns the OTP SSH
  # callback, byte parser, and IO bridge. These fixtures exercise that public
  # contract without introducing a v2 session owner into the v1 runtime.
  defmodule HostChannel do
    @behaviour :ssh_server_channel

    alias TermUI.Backend.SSH
    alias TermUI.Terminal.EscapeParser

    @impl true
    def init([owner]) do
      Process.flag(:trap_exit, true)

      {:ok,
       %{
         owner: owner,
         connection: nil,
         channel: nil,
         size: {3, 8},
         runtime: nil,
         writer: nil,
         input: ""
       }}
    end

    @impl true
    def handle_msg({:ssh_channel_up, channel, connection}, state),
      do: {:ok, %{state | channel: channel, connection: connection}}

    def handle_msg({:EXIT, runtime, reason}, %{runtime: runtime} = state) do
      send(state.owner, {:ssh_network_stopped, runtime, reason})
      status = if reason == :normal, do: 0, else: 1
      :ssh_connection.exit_status(state.connection, state.channel, status)
      :ssh_connection.send_eof(state.connection, state.channel)
      {:stop, state.channel, %{state | runtime: nil}}
    end

    def handle_msg(_message, state), do: {:ok, state}

    @impl true
    def handle_ssh_msg({:ssh_cm, connection, {:pty, channel, want_reply, pty}}, state) do
      {_terminal, width, height, _pixel_width, _pixel_height, _modes} = pty
      :ssh_connection.reply_request(connection, want_reply, :success, channel)
      {:ok, %{state | connection: connection, channel: channel, size: {height, width}}}
    end

    def handle_ssh_msg({:ssh_cm, connection, {:shell, channel, want_reply}}, state) do
      owner = self()
      writer = spawn(fn -> forward_io(owner, connection, channel) end)
      {height, width} = state.size

      {:ok, runtime} =
        Runtime.start_link(
          root: Root,
          ssh_columns: width,
          ssh_rows: height,
          backend: {SSH, device: writer, size: state.size}
        )

      send(state.owner, {:ssh_network_started, runtime, width, height})
      :ssh_connection.reply_request(connection, want_reply, :success, channel)
      {:ok, %{state | connection: connection, channel: channel, runtime: runtime, writer: writer}}
    end

    def handle_ssh_msg({:ssh_cm, _connection, {:data, _channel, 0, data}}, state) do
      {events, remaining} = EscapeParser.parse(state.input <> data)
      Enum.each(events, &send(state.runtime, {:ssh_input, &1}))
      render(state.runtime)
      {:ok, %{state | input: remaining}}
    end

    def handle_ssh_msg(
          {:ssh_cm, _connection, {:window_change, _channel, width, height, _pw, _ph}},
          state
        ) do
      send(state.runtime, {:ssh_resize, height, width})
      render(state.runtime)
      {:ok, %{state | size: {height, width}}}
    end

    def handle_ssh_msg({:ssh_cm, _connection, {:eof, channel}}, state),
      do: {:stop, channel, state}

    def handle_ssh_msg(_message, state), do: {:ok, state}

    @impl true
    def terminate(_reason, state) do
      if is_pid(state.runtime) and Process.alive?(state.runtime) do
        reference = Process.monitor(state.runtime)
        Runtime.shutdown(state.runtime)

        receive do
          {:DOWN, ^reference, :process, _runtime, _reason} -> :ok
        after
          2_000 -> :ok
        end
      end

      if is_pid(state.writer), do: send(state.writer, :stop)
      :ok
    end

    defp render(runtime) do
      :ok = Runtime.sync(runtime)
      send(runtime, :render)
      :sys.get_state(runtime)
      :ok
    catch
      :exit, _reason -> :ok
    end

    defp forward_io(owner, connection, channel) do
      monitor = Process.monitor(owner)
      forward_io_loop(connection, channel, monitor)
    end

    defp forward_io_loop(connection, channel, monitor) do
      receive do
        {:io_request, caller, tag, request} ->
          result = write_request(connection, channel, request)
          send(caller, {:io_reply, tag, result})
          forward_io_loop(connection, channel, monitor)

        {:DOWN, ^monitor, :process, _owner, _reason} ->
          :ok

        :stop ->
          :ok
      end
    end

    defp write_request(connection, channel, {:put_chars, _encoding, data}),
      do: :ssh_connection.send(connection, channel, 0, IO.iodata_to_binary(data), 2_000)

    defp write_request(connection, channel, {:put_chars, encoding, module, function, args}),
      do:
        write_request(connection, channel, {:put_chars, encoding, apply(module, function, args)})

    defp write_request(_connection, _channel, _request), do: {:error, :enotsup}
  end

  setup_all do
    {:ok, _applications} = Application.ensure_all_started(:ssh)

    directory =
      Path.join(
        System.tmp_dir!(),
        "term-ui-ssh-network-#{:os.getpid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    key = :public_key.generate_key({:rsa, 2_048, 65_537})
    entry = :public_key.pem_entry_encode(:RSAPrivateKey, key)
    path = Path.join(directory, "ssh_host_rsa_key")
    File.write!(path, :public_key.pem_encode([entry]))
    File.chmod!(path, 0o600)
    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, system_dir: directory}
  end

  test "an OTP SSH PTY renders the final cell, clears old cells, and follows resize", context do
    connection = start_host(context.system_dir)
    channel = open_shell(connection, 8, 3)
    assert_receive {:ssh_network_started, runtime, 8, 3}, 2_000

    {screen, output} = receive_screen(connection, channel, AnsiScreen.new(), full_rows("A", 8, 3))
    assert output =~ "\e[?7l"
    refute output =~ "\n"

    assert :ok = :ssh_connection.send(connection, channel, "\e[")
    assert :ok = :ssh_connection.send(connection, channel, "A")
    {screen, _output} = receive_screen(connection, channel, screen, full_rows("U", 8, 3))

    assert :ok = :ssh_connection.send(connection, channel, "s")

    {screen, _output} =
      receive_screen(connection, channel, screen, ["U       ", "U       ", "!       "])

    assert :ok = :ssh_connection.send(connection, channel, "f")
    {screen, _output} = receive_screen(connection, channel, screen, full_rows("U", 8, 3))
    assert :ok = :ssh_connection.window_change(connection, channel, 12, 4)
    {screen, _output} = receive_screen(connection, channel, screen, full_rows("U", 12, 4))
    assert Runtime.get_state(runtime).dimensions == {12, 4}

    assert :ok = :ssh_connection.window_change(connection, channel, 5, 2)
    {_screen, output} = receive_screen(connection, channel, screen, full_rows("U", 5, 2))
    assert Runtime.get_state(runtime).dimensions == {5, 2}

    for [row, column] <- Regex.scan(~r/\e\[(\d+);(\d+)H/, output, capture: :all_but_first) do
      assert String.to_integer(row) <= 2
      assert String.to_integer(column) <= 5
    end

    assert :ok = :ssh_connection.send(connection, channel, "q")
    assert_receive {:ssh_network_stopped, ^runtime, :normal}, 2_000
    output = receive_closed(connection, channel)
    assert output =~ "\e[?25h"
    assert output =~ "\e[?7h"
    assert output =~ "\e[?1049l"
  end

  test "concurrent OTP SSH channels isolate buffers and disconnect cleanup", context do
    connection = start_host(context.system_dir)
    channel_a = open_shell(connection, 8, 3)
    channel_b = open_shell(connection, 10, 4)
    assert_receive {:ssh_network_started, runtime_a, 8, 3}, 2_000
    assert_receive {:ssh_network_started, runtime_b, 10, 4}, 2_000

    {screen_a, _output} =
      receive_screen(connection, channel_a, AnsiScreen.new(), full_rows("A", 8, 3))

    {_screen_b, _output} =
      receive_screen(connection, channel_b, AnsiScreen.new(), full_rows("A", 10, 4))

    buffer_a = Runtime.get_state(runtime_a).buffer_manager
    buffer_b = Runtime.get_state(runtime_b).buffer_manager
    refute buffer_a == buffer_b

    assert :ok = :ssh_connection.send(connection, channel_a, "b")
    {_screen, _output} = receive_screen(connection, channel_a, screen_a, full_rows("B", 8, 3))
    assert Runtime.get_state(runtime_b).root_state.label == "A"

    runtime_monitor = Process.monitor(runtime_a)
    buffer_monitor = Process.monitor(buffer_a)
    assert :ok = :ssh_connection.close(connection, channel_a)
    assert_receive {:DOWN, ^runtime_monitor, :process, ^runtime_a, _reason}, 2_000
    assert_receive {:DOWN, ^buffer_monitor, :process, ^buffer_a, _reason}, 2_000
    assert Process.alive?(runtime_b)

    assert :ok = :ssh_connection.send(connection, channel_b, "q")
    assert_receive {:ssh_network_stopped, ^runtime_b, :normal}, 2_000
    receive_closed(connection, channel_b)
  end

  defp start_host(system_dir) do
    options = [
      system_dir: String.to_charlist(system_dir),
      auth_methods: ~c"password",
      pwdfun: fn user, password -> user == ~c"termui" and password == ~c"secret" end,
      ssh_cli: {HostChannel, [self()]}
    ]

    assert {:ok, daemon} = :ssh.daemon(:loopback, 0, options)
    assert {:port, port} = :ssh.daemon_info(daemon, :port)
    on_exit(fn -> :ssh.stop_daemon(daemon) end)

    assert {:ok, connection} =
             :ssh.connect(~c"localhost", port,
               user: ~c"termui",
               password: ~c"secret",
               user_interaction: false,
               silently_accept_hosts: true
             )

    on_exit(fn -> :ssh.close(connection) end)
    connection
  end

  defp open_shell(connection, width, height) do
    assert {:ok, channel} = :ssh_connection.session_channel(connection, 5_000)

    assert :success =
             :ssh_connection.ptty_alloc(
               connection,
               channel,
               [term: ~c"xterm-256color", width: width, height: height, pty_opts: []],
               5_000
             )

    assert :ok = :ssh_connection.shell(connection, channel)
    channel
  end

  defp full_rows(label, width, height),
    do:
      List.duplicate(String.duplicate(label, width), height - 1) ++
        [String.duplicate(".", width - 1) <> "!"]

  defp receive_screen(connection, channel, screen, rows) do
    receive_screen(
      connection,
      channel,
      screen,
      rows,
      "",
      System.monotonic_time(:millisecond) + 2_000
    )
  end

  defp receive_screen(connection, channel, screen, rows, output, deadline) do
    if screen_rows(screen, String.length(hd(rows)), length(rows)) == rows do
      {screen, output}
    else
      receive do
        {:ssh_cm, ^connection, {:data, ^channel, 0, data}} ->
          receive_screen(
            connection,
            channel,
            AnsiScreen.feed(screen, data),
            rows,
            output <> data,
            deadline
          )
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          flunk("SSH screen did not reach #{inspect(rows)}: #{inspect(output)}")
      end
    end
  end

  defp screen_rows(screen, width, height) do
    for row <- 1..height do
      for(
        column <- 1..width,
        into: "",
        do: screen.cells |> Map.get({row, column}, {" ", nil, nil, nil}) |> elem(0)
      )
    end
  end

  defp receive_closed(connection, channel, output \\ "") do
    receive do
      {:ssh_cm, ^connection, {:data, ^channel, 0, data}} ->
        receive_closed(connection, channel, output <> data)

      {:ssh_cm, ^connection, {:closed, ^channel}} ->
        output
    after
      2_000 -> flunk("SSH channel did not close")
    end
  end
end
