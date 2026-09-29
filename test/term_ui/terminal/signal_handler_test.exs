defmodule TermUI.Terminal.SignalHandlerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias TermUI.Backend.Manager
  alias TermUI.{Event, Frame}
  alias TermUI.Terminal.SignalHandler

  test "forwards resume and ignores unrelated signals" do
    owner = self()
    assert {:ok, ^owner} = SignalHandler.handle_event(:sigcont, owner)
    assert_receive :terminal_resume
    assert {:ok, ^owner} = SignalHandler.handle_event(:sigusr2, owner)
    refute_receive :terminal_resume
  end

  test "the OTP barrier preserves the existing driver and input group" do
    driver = Process.whereis(:user_drv)
    user = Process.whereis(:user)
    owner = self()

    assert {:ok, :ok, ^owner} = SignalHandler.handle_call(:sync, owner)
    assert Process.whereis(:user_drv) == driver
    assert Process.whereis(:user) == user
  end

  test "a local backend removes its supervised signal handler on shutdown" do
    capture_io(fn ->
      {:ok, manager} =
        Manager.start_link(self(), :tty, size: {3, 8}, size_poll_interval: :disabled)

      handler = {SignalHandler, manager}

      if match?({:unix, _}, :os.type()) do
        assert handler in :gen_event.which_handlers(:erl_signal_server)
      end

      assert :ok = Manager.close(manager, :normal)

      if match?({:unix, _}, :os.type()) do
        refute handler in :gen_event.which_handlers(:erl_signal_server)
      end
    end)
  end

  test "the Unix signal subscriber restores a local backend while its input read is pending" do
    if match?({:unix, _}, :os.type()) do
      {:ok, output} = StringIO.open("")
      test_process = self()
      device = spawn(fn -> hold_input(output, test_process) end)
      previous = Process.group_leader()
      Process.group_leader(self(), device)

      try do
        {:ok, manager} =
          Manager.start_link(self(), :tty,
            size: {3, 8},
            alternate_screen: true,
            size_poll_interval: :disabled
          )

        frame = Frame.from_rows(["LEFT", "RIGHT", "END"], 8, 3)
        assert :ok = Manager.draw(manager, frame)
        snapshot = output |> StringIO.contents() |> elem(1)
        assert :ok = Manager.activate(manager)
        assert_receive {:input_waiting, worker}, 1_000
        reader = :sys.get_state(manager).backend_state.input_reader

        :gen_event.notify(:erl_signal_server, :sigcont)
        assert_receive :backend_resumed, 1_000
        assert Process.alive?(reader)
        assert Process.alive?(worker)
        assert :ok = Manager.draw(manager, frame)
        repaired = output |> StringIO.contents() |> elem(1) |> String.replace_prefix(snapshot, "")
        assert repaired =~ "\e[?1049h"
        assert repaired =~ "LEFT"
        assert repaired =~ "RIGHT"
        assert repaired =~ "END"

        send(device, {:release_input, "q"})
        assert_receive {:backend_event, %Event.Text{text: "q"}}, 1_000
        assert_receive {:input_waiting, ^worker}, 1_000
        assert :sys.get_state(manager).backend_state.input_reader == reader
        assert :ok = Manager.close(manager, :normal)
      after
        Process.group_leader(self(), previous)
        send(device, :stop)
        StringIO.close(output)
      end
    end
  end

  defp hold_input(output, owner, pending \\ nil) do
    receive do
      {:io_request, reader, tag, {:get_chars, _encoding, _prompt, _count}} ->
        send(owner, {:input_waiting, reader})
        hold_input(output, owner, {reader, tag})

      {:release_input, text} when not is_nil(pending) ->
        {reader, tag} = pending
        send(reader, {:io_reply, tag, text})
        hold_input(output, owner)

      {:io_request, _from, _tag, _request} = request ->
        send(output, request)
        hold_input(output, owner, pending)

      :stop ->
        :ok
    end
  end
end
