defmodule TermUI.CompatibilityAliasTest do
  use ExUnit.Case, async: true

  alias TermUI.{Command, Frame, Runtime}
  alias TermUI.Test.DeterministicBackend

  defmodule MessageApp do
    use TermUI.Elm

    def init(opts) do
      %{messages: [], dimensions: Keyword.fetch!(opts, :dimensions)}
    end

    def event_to_msg(_event, _state), do: :ignore
    def update(message, state), do: %{state | messages: state.messages ++ [message]}

    def view(%{dimensions: {width, height}}) do
      Frame.from_rows(["messages"], width, height)
    end
  end

  test "quit aliases return the exact shutdown commands" do
    assert command().quit() == Command.shutdown()
    assert command().quit(:user_requested) == Command.shutdown(:user_requested)
  end

  test "the root target delegates to send_message/2" do
    direct = start_runtime()
    alias_runtime = start_runtime()

    assert :ok = Runtime.send_message(direct, :hello)
    assert :ok = runtime().send_message(alias_runtime, :root, :hello)
    assert :ok = Runtime.sync(direct)
    assert :ok = Runtime.sync(alias_runtime)

    assert Runtime.get_state(alias_runtime).app_state == Runtime.get_state(direct).app_state
  end

  test "component targets return a migration error without routing a message" do
    runtime = start_runtime()

    assert {:error,
            {:component_routing_removed, :old_component,
             "Use TermUI.Runtime.send_message/2 and route the message in the root update/2 function."}} =
             runtime().send_message(runtime, :old_component, :hello)

    assert :ok = Runtime.sync(runtime)
    assert Runtime.get_state(runtime).app_state.messages == []
  end

  test "compatibility aliases name their v2 replacements" do
    assert deprecated(Command, :quit, 0) == "Use TermUI.Command.shutdown/0 instead."
    assert deprecated(Command, :quit, 1) == "Use TermUI.Command.shutdown/1 instead."

    assert deprecated(Runtime, :send_message, 3) ==
             "Use TermUI.Runtime.send_message/2 and route the message in the root application."
  end

  defp start_runtime do
    options = [
      backend: {DeterministicBackend, owner: self()},
      suppress_logger: false
    ]

    assert {:ok, runtime} = TermUI.start_link(MessageApp, options)
    on_exit(fn -> stop_runtime(runtime) end)
    runtime
  end

  defp stop_runtime(runtime) do
    if Process.alive?(runtime) do
      Process.unlink(runtime)
      reference = Process.monitor(runtime)
      Runtime.shutdown(runtime)
      assert_receive {:DOWN, ^reference, :process, ^runtime, _reason}, 1_000
    end
  end

  defp deprecated(module, name, arity) do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(module)

    Enum.find_value(entries, fn
      {{:function, ^name, ^arity}, _, _, _, metadata} -> metadata[:deprecated]
      _entry -> nil
    end)
  end

  defp command, do: Module.concat(TermUI, "Command")
  defp runtime, do: Module.concat(TermUI, "Runtime")
end
