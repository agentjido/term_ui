defmodule TermUI.Terminal.SignalHandlerTest do
  use ExUnit.Case, async: true

  alias TermUI.Terminal.SignalHandler

  test "forwards SIGWINCH to the terminal process" do
    terminal = self()
    assert {:ok, ^terminal} = SignalHandler.handle_event(:sigwinch, terminal)
    assert_receive :sigwinch
  end

  test "restores the terminal before SIGTERM shutdown continues" do
    test_process = self()

    terminal =
      spawn(fn ->
        receive do
          {:"$gen_call", from, :restore} ->
            send(test_process, :restored)
            GenServer.reply(from, :ok)
        end
      end)

    assert {:ok, ^terminal} = SignalHandler.handle_event(:sigterm, terminal)
    assert_receive :restored
  end

  test "supports a custom restore request and no resize target" do
    test_process = self()

    terminal =
      spawn(fn ->
        receive do
          {:"$gen_call", from, :restore_terminal} ->
            send(test_process, :restored)
            GenServer.reply(from, :ok)
        end
      end)

    state = {terminal, :restore_terminal, nil}
    assert {:ok, ^state} = SignalHandler.handle_event(:sigwinch, state)
    refute_receive :sigwinch
    assert {:ok, ^state} = SignalHandler.handle_event(:sigterm, state)
    assert_receive :restored
  end

  test "ignores unrelated signals" do
    terminal = self()
    assert {:ok, ^terminal} = SignalHandler.handle_event(:sigusr2, terminal)
    refute_receive _message
  end

  test "forwards resume to the terminal owner or the TTY runtime" do
    terminal = self()
    assert {:ok, ^terminal} = SignalHandler.handle_event(:sigcont, terminal)
    assert_receive :sigcont

    state = {terminal, :restore_terminal, nil}
    assert {:ok, ^state} = SignalHandler.handle_event(:sigcont, state)
    assert_receive :terminal_resume
  end
end
