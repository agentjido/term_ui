defmodule TermUI.Integration.SSHRuntimeTest do
  use ExUnit.Case, async: false

  alias TermUI.Backend.SSH
  alias TermUI.Backend.SSH.Channel
  alias TermUI.{Command, Event, Frame, Runtime, Style}
  alias TermUI.Test.AnsiScreen

  defmodule SSHApp do
    use TermUI.Elm

    @impl true
    def init(opts) do
      state = %{
        owner: Keyword.fetch!(opts, :test_owner),
        label: Keyword.fetch!(opts, :label),
        dimensions: Keyword.fetch!(opts, :dimensions),
        text: ""
      }

      send(state.owner, {:ssh_app_started, self(), state.label, state.dimensions})
      state
    end

    @impl true
    def event_to_msg(event, _state), do: {:msg, {:event, event}}

    @impl true
    def update({:event, %Event.Text{text: "q"}}, state) do
      {state, [Command.shutdown(:normal)]}
    end

    def update({:event, %Event.Text{text: text}}, state) do
      state = %{state | text: state.text <> text}
      send(state.owner, {:ssh_app_event, self(), state.label, {:text, state.text}})
      state
    end

    def update({:event, %Event.Resize{width: width, height: height}}, state) do
      state = %{state | dimensions: {width, height}}
      send(state.owner, {:ssh_app_event, self(), state.label, {:resize, width, height}})
      state
    end

    def update({:event, _event}, state), do: state

    @impl true
    def view(state) do
      {width, height} = state.dimensions
      Frame.from_rows([state.label, state.text], width, height)
    end

    @impl true
    def terminate(reason, state) do
      send(state.owner, {:ssh_app_stopped, self(), state.label, reason})
      :ok
    end
  end

  defmodule MatrixApp do
    use TermUI.Elm

    @impl true
    def init(opts) do
      state = %{
        owner: Keyword.fetch!(opts, :test_owner),
        label: Keyword.fetch!(opts, :label),
        dimensions: Keyword.fetch!(opts, :dimensions),
        phase: :full,
        background: Keyword.get(opts, :background, :default)
      }

      send(state.owner, {:ssh_app_started, self(), state.label, state.dimensions})
      state
    end

    @impl true
    def event_to_msg(%Event.Key{key: :up, modifiers: []}, _state), do: {:msg, {:label, "U"}}
    def event_to_msg(%Event.Text{text: "s"}, _state), do: {:msg, :shrink}
    def event_to_msg(%Event.Text{text: "f"}, _state), do: {:msg, :full}
    def event_to_msg(%Event.Text{text: "q"}, _state), do: {:msg, :quit}

    def event_to_msg(%Event.Resize{width: width, height: height}, _state),
      do: {:msg, {:resize, width, height}}

    def event_to_msg(_event, _state), do: :ignore

    @impl true
    def update({:label, label}, state), do: %{state | label: label}
    def update(:shrink, state), do: %{state | phase: :shrink}
    def update(:full, state), do: %{state | phase: :full}
    def update(:quit, state), do: {state, [Command.shutdown(:normal)]}
    def update({:resize, width, height}, state), do: %{state | dimensions: {width, height}}
    def update({:background, background}, state), do: %{state | background: background}

    @impl true
    def view(state) do
      {width, height} = state.dimensions

      rows =
        for row <- 1..height do
          case {state.phase, row == height} do
            {:shrink, true} -> "!"
            {:shrink, false} -> state.label
            {:full, true} -> String.duplicate(".", width - 1) <> "!"
            {:full, false} -> String.duplicate(state.label, width)
          end
        end

      style = Style.new(bg: state.background)
      rows = Enum.map(rows, &[{String.pad_trailing(&1, width), style}])
      Frame.from_rows(rows, width, height)
    end
  end

  setup_all do
    assert {:ok, _applications} = Application.ensure_all_started(:ssh)
    directory = temporary_key_directory()
    write_host_key(directory)

    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, system_dir: directory}
  end

  test "an OTP SSH client starts, resizes, uses, and stops one TermUI session", context do
    {daemon, port} = start_daemon(context.system_dir, "one", self())
    connection = connect(port)
    channel = open_shell(connection, 40, 10)

    assert_receive {:ssh_app_started, runtime, "one", {40, 10}}, 2_000
    assert receive_channel_data(connection, channel, "one") =~ "one"

    assert :ok = :ssh_connection.send(connection, channel, "é")
    assert_receive {:ssh_app_event, ^runtime, "one", {:text, "é"}}, 2_000

    assert :ok = :ssh_connection.window_change(connection, channel, 60, 15)
    assert_receive {:ssh_app_event, ^runtime, "one", {:resize, 60, 15}}, 2_000

    assert :ok = :ssh_connection.send(connection, channel, "q")
    assert_receive {:ssh_app_stopped, ^runtime, "one", :normal}, 2_000
    assert_receive {:ssh_cm, ^connection, {:closed, ^channel}}, 2_000

    close_connection(connection)
    assert :ok = :ssh.stop_daemon(daemon)
  end

  test "two OTP SSH channels isolate state and disconnect failure", context do
    {daemon, port} = start_daemon(context.system_dir, "shared", self())
    connection = connect(port)
    channel_a = open_shell(connection, 30, 8)
    channel_b = open_shell(connection, 50, 12)

    assert_receive {:ssh_app_started, runtime_a, "shared", {30, 8}}, 2_000
    assert_receive {:ssh_app_started, runtime_b, "shared", {50, 12}}, 2_000
    refute runtime_a == runtime_b

    assert :ok = :ssh_connection.send(connection, channel_a, "a")
    assert_receive {:ssh_app_event, ^runtime_a, "shared", {:text, "a"}}, 2_000
    refute_receive {:ssh_app_event, ^runtime_b, "shared", {:text, _text}}, 100

    assert :ok = :ssh_connection.close(connection, channel_a)
    assert_receive {:ssh_app_stopped, ^runtime_a, "shared", _reason}, 2_000
    assert Process.alive?(runtime_b)

    assert :ok = :ssh_connection.send(connection, channel_b, "b")
    assert_receive {:ssh_app_event, ^runtime_b, "shared", {:text, "b"}}, 2_000

    close_connection(connection)
    assert_receive {:ssh_app_stopped, ^runtime_b, "shared", _reason}, 2_000
    assert :ok = :ssh.stop_daemon(daemon)
  end

  test "an OTP SSH PTY renders the final cell, clears old cells, and follows resize", context do
    {_daemon, port} = start_daemon(context.system_dir, "A", self(), MatrixApp)
    connection = connect(port)
    channel = open_shell(connection, 8, 3)
    assert_receive {:ssh_app_started, runtime, "A", {8, 3}}, 2_000

    {screen, output} = receive_screen(connection, channel, AnsiScreen.new(), full_rows("A", 8, 3))
    assert output =~ "\e[?1049h"
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
    output = receive_closed(connection, channel)
    assert output =~ "\e[?25h"
    assert output =~ "\e[?2004l"
    assert output =~ "\e[?1004l"
    assert output =~ "\e[?1049l"
  end

  test "a blocked OTP SSH receive window retains only the latest waiting frame", context do
    # Keep the receive window blocked through all 100 renders. Timeout behavior
    # has separate session tests; this check verifies bounded frame storage.
    {_daemon, port} =
      start_daemon(context.system_dir, "A", self(), MatrixApp, [],
        send_timeout: 30_000,
        output_timeout: 30_000
      )

    connection = connect(port)

    # The first eight bytes enter the alternate screen. The remaining setup
    # output cannot complete until this client grants more receive capacity.
    assert {:ok, channel} = :ssh_connection.session_channel(connection, 8, 32_768, 5_000)
    request_shell(connection, channel, 8, 3)
    assert_receive {:ssh_app_started, runtime, "A", {8, 3}}, 2_000
    assert_receive {:ssh_cm, ^connection, {:data, ^channel, 0, "\e[?1049h"}}, 2_000

    manager = Runtime.get_state(runtime).backend_manager
    session = :sys.get_state(manager).backend_state.session

    for index <- 1..100 do
      label = if index == 100, do: "Z", else: "B"
      Runtime.send_message(runtime, {:label, label})
      render_pending_frame(runtime)

      assert %{output_queue: %{capacity: 2, in_flight: 1, pending_frames: 1}} =
               SSH.session_info(session)
    end

    assert :ok = :ssh_connection.adjust_window(connection, channel, 1_000_000)

    {_screen, output} =
      receive_screen(connection, channel, AnsiScreen.new(), full_rows("Z", 8, 3))

    refute output =~ "BBBBBBBB"
    assert :ok = :ssh_connection.send(connection, channel, "q")
    assert receive_closed(connection, channel) =~ "\e[?1049l"
  end

  test "complete styled SSH frames preserve blank-cell backgrounds and style changes", context do
    {_daemon, port} = start_daemon(context.system_dir, "A", self(), MatrixApp, background: :blue)
    connection = connect(port)
    channel = open_shell(connection, 8, 3)
    assert_receive {:ssh_app_started, runtime, "A", {8, 3}}, 2_000

    {screen, _output} =
      receive_screen(connection, channel, AnsiScreen.new(), full_rows("A", 8, 3), :blue)

    assert :ok = :ssh_connection.send(connection, channel, "s")
    rows = ["A       ", "A       ", "!       "]
    {screen, _output} = receive_screen(connection, channel, screen, rows, :blue)

    Runtime.send_message(runtime, {:background, :red})
    render_pending_frame(runtime)
    {_screen, _output} = receive_screen(connection, channel, screen, rows, :red)

    assert :ok = :ssh_connection.send(connection, channel, "q")
    assert receive_closed(connection, channel) =~ "\e[0m"
  end

  defp start_daemon(
         system_dir,
         label,
         owner,
         root \\ SSHApp,
         runtime_options \\ [],
         channel_options \\ []
       ) do
    password_fun = fn user, password -> user == ~c"termui" and password == ~c"secret" end

    options = [
      system_dir: String.to_charlist(system_dir),
      auth_methods: ~c"password",
      pwdfun: password_fun,
      ssh_cli:
        {Channel,
         [
           root,
           Keyword.merge(
             [
               runtime_options: [test_owner: owner, label: label] ++ runtime_options,
               output_timeout: 10_000
             ],
             channel_options
           )
         ]}
    ]

    assert {:ok, daemon} = :ssh.daemon(:loopback, 0, options)
    assert {:port, port} = :ssh.daemon_info(daemon, :port)

    on_exit(fn ->
      if Process.alive?(daemon), do: :ssh.stop_daemon(daemon)
    end)

    {daemon, port}
  end

  defp connect(port) do
    options = [
      user: ~c"termui",
      password: ~c"secret",
      user_interaction: false,
      silently_accept_hosts: true
    ]

    assert {:ok, connection} = :ssh.connect(~c"localhost", port, options, 5_000)
    on_exit(fn -> close_connection(connection) end)
    connection
  end

  defp open_shell(connection, width, height) do
    assert {:ok, channel} = :ssh_connection.session_channel(connection, 5_000)
    request_shell(connection, channel, width, height)
    channel
  end

  defp request_shell(connection, channel, width, height) do
    assert :success =
             :ssh_connection.ptty_alloc(
               connection,
               channel,
               [term: ~c"xterm-256color", width: width, height: height, pty_opts: []],
               5_000
             )

    assert :ok = :ssh_connection.shell(connection, channel)
    :ok
  end

  defp render_pending_frame(runtime) do
    :ok = Runtime.sync(runtime)

    case Runtime.get_state(runtime).render_timer do
      {_reference, token} -> send(runtime, {:render, token})
      nil -> :ok
    end

    :ok = Runtime.sync(runtime)
  end

  defp full_rows(label, width, height),
    do:
      List.duplicate(String.duplicate(label, width), height - 1) ++
        [String.duplicate(".", width - 1) <> "!"]

  defp receive_screen(connection, channel, screen, rows, background \\ nil) do
    receive_screen(
      connection,
      channel,
      screen,
      rows,
      background,
      "",
      System.monotonic_time(:millisecond) + 2_000
    )
  end

  defp receive_screen(connection, channel, screen, rows, background, output, deadline) do
    if screen_matches?(screen, rows, background) do
      {screen, output}
    else
      receive do
        {:ssh_cm, ^connection, {:data, ^channel, 0, data}} ->
          receive_screen(
            connection,
            channel,
            AnsiScreen.feed(screen, data),
            rows,
            background,
            output <> data,
            deadline
          )
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          flunk("SSH screen did not reach #{inspect(rows)}: #{inspect(output)}")
      end
    end
  end

  defp screen_matches?(screen, rows, background) do
    width = String.length(hd(rows))

    screen_rows(screen, width, length(rows)) == rows and
      (is_nil(background) or
         Enum.all?(for(row <- 1..length(rows), column <- 1..width, do: {row, column}), fn
           position -> match?({_char, _fg, ^background, _attrs}, screen.cells[position])
         end))
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

  defp receive_channel_data(connection, channel, expected, output \\ "") do
    receive do
      {:ssh_cm, ^connection, {:data, ^channel, 0, data}} ->
        output = output <> data

        if String.contains?(output, expected) do
          output
        else
          receive_channel_data(connection, channel, expected, output)
        end
    after
      2_000 -> flunk("did not receive SSH channel output containing #{inspect(expected)}")
    end
  end

  defp close_connection(connection) do
    :ok = :ssh.close(connection)
  catch
    :exit, _reason -> :ok
  end

  defp temporary_key_directory do
    directory =
      Path.join(
        System.tmp_dir!(),
        "term-ui-ssh-#{:os.getpid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(directory)
    directory
  end

  defp write_host_key(directory) do
    key = :public_key.generate_key({:rsa, 2_048, 65_537})
    entry = :public_key.pem_entry_encode(:RSAPrivateKey, key)
    path = Path.join(directory, "ssh_host_rsa_key")
    File.write!(path, :public_key.pem_encode([entry]))
    File.chmod!(path, 0o600)
  end
end
