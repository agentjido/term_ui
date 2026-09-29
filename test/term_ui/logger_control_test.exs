defmodule TermUI.LoggerControlTest do
  use ExUnit.Case, async: false

  alias TermUI.{Frame, LoggerControl, Runtime}
  alias TermUI.Test.DeterministicBackend

  @filter_id :term_ui_full_screen
  @eventual_timeout 1_000

  defmodule QuietApp do
    use TermUI.Elm

    def init(_opts), do: %{}
    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state
    def view(_state), do: Frame.from_rows(["quiet"], 20, 2)
  end

  test "keeps the console logger quiet until the last full-screen owner exits" do
    first = LoggerControl.suspend()
    second = LoggerControl.suspend()

    on_exit(fn ->
      LoggerControl.resume(first)
      LoggerControl.resume(second)
    end)

    assert filter_present?()
    assert :ok = LoggerControl.resume(first)
    assert filter_present?()
    assert :ok = LoggerControl.resume(second)
    refute filter_present?()
  end

  test "restores the console logger when a full-screen owner is killed" do
    test_pid = self()

    owner =
      spawn(fn ->
        token = LoggerControl.suspend()
        send(test_pid, {:suspended, token})
        Process.sleep(:infinity)
      end)

    assert_receive {:suspended, {_token_ref, watcher} = token}

    on_exit(fn -> LoggerControl.resume(token) end)

    assert Process.alive?(watcher)
    assert filter_present?()
    Process.exit(owner, :kill)

    refute_filter_present()
  end

  test "runtime owns logger suppression for one full-screen session" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: QuietApp,
               backend: {DeterministicBackend, owner: self()},
               suppress_logger: true
             )

    runtime_ref = Process.monitor(runtime)

    assert_receive {:backend, :draw, _frame}, @eventual_timeout
    assert filter_present?()

    Runtime.shutdown(runtime)

    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :normal}, @eventual_timeout
    refute_filter_present()
  end

  defp filter_present? do
    {:ok, %{filters: filters}} = :logger.get_handler_config(:default)
    Enum.any?(filters, fn {id, _filter} -> id == @filter_id end)
  end

  defp refute_filter_present(attempts \\ 20)

  defp refute_filter_present(0), do: refute(filter_present?())

  defp refute_filter_present(attempts) do
    if filter_present?() do
      Process.sleep(5)
      refute_filter_present(attempts - 1)
    else
      refute filter_present?()
    end
  end
end
