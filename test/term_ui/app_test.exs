defmodule TermUI.AppTest do
  use ExUnit.Case, async: true

  alias TermUI.{App, Command, Frame, Runtime}
  alias TermUI.Test.DeterministicBackend

  defmodule RunningApp do
    use TermUI.Elm

    def init(opts), do: %{dimensions: Keyword.fetch!(opts, :dimensions)}
    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state

    def view(%{dimensions: {width, height}}) do
      Frame.from_rows(["running"], width, height)
    end
  end

  defmodule StoppingApp do
    use TermUI.Elm

    def init(opts) do
      {%{dimensions: Keyword.fetch!(opts, :dimensions)}, [Command.shutdown()]}
    end

    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state

    def view(%{dimensions: {width, height}}) do
      Frame.from_rows(["stopping"], width, height)
    end
  end

  test "start delegates to TermUI.start_link/2 and starts only the v2 runtime" do
    direct = start_runtime(&TermUI.start_link/2)
    facade = start_runtime(fn root, opts -> app().start(root, opts) end)

    direct_state = Runtime.get_state(direct)
    facade_state = Runtime.get_state(facade)

    assert Map.take(facade_state, [:app, :backend, :dimensions, :capabilities]) ==
             Map.take(direct_state, [:app, :backend, :dimensions, :capabilities])

    assert :proc_lib.translate_initial_call(facade) == :proc_lib.translate_initial_call(direct)
    assert :proc_lib.translate_initial_call(facade) == {Runtime, :init, 1}
  end

  test "run delegates to TermUI.run/2 and keeps the v1 success value" do
    options = runtime_options()

    assert :ok = TermUI.run(StoppingApp, options)
    assert {:ok, :exited_normally} = app().run(StoppingApp, options)

    failure_options = runtime_options(fail: :draw)
    assert {:error, _reason} = direct_error = TermUI.run(RunningApp, failure_options)
    assert app().run(RunningApp, failure_options) == direct_error
  end

  test "shutdown returns the direct v2 result and stops the same runtime" do
    direct = start_runtime(&TermUI.start_link/2)
    facade = start_runtime(fn root, opts -> app().start(root, opts) end)
    direct_reference = Process.monitor(direct)
    facade_reference = Process.monitor(facade)

    direct_result = Runtime.shutdown(direct)
    facade_result = app().shutdown(facade)

    assert facade_result == direct_result
    assert_receive {:DOWN, ^direct_reference, :process, ^direct, :normal}, 1_000
    assert_receive {:DOWN, ^facade_reference, :process, ^facade, :normal}, 1_000
  end

  test "all facade functions name their direct replacements" do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(App)

    deprecations =
      Map.new(entries, fn
        {{:function, name, arity}, _, _, _, metadata} -> {{name, arity}, metadata[:deprecated]}
        {_entry, _, _, _, _metadata} -> {nil, nil}
      end)

    assert deprecations[{:start, 2}] == "Use TermUI.start_link/2 instead."

    assert deprecations[{:run, 2}] ==
             "Use TermUI.run/2 instead. It returns :ok after a normal exit."

    assert deprecations[{:shutdown, 1}] == "Use TermUI.Runtime.shutdown/1 instead."
  end

  test "global v1 capability queries are not restored" do
    refute function_exported?(App, :backend_mode, 0)
    refute function_exported?(App, :supports?, 1)

    runtime = start_runtime(&TermUI.start_link/2)
    assert Runtime.capabilities(runtime) == %{colors: :true_color, unicode: true}
  end

  defp start_runtime(starter) do
    assert {:ok, runtime} = starter.(RunningApp, runtime_options())
    on_exit(fn -> stop_runtime(runtime) end)
    runtime
  end

  defp runtime_options(backend_options \\ []) do
    backend_options = Keyword.put_new(backend_options, :owner, self())
    [backend: {DeterministicBackend, backend_options}, suppress_logger: false]
  end

  defp app, do: Module.concat(TermUI, "App")

  defp stop_runtime(runtime) do
    if Process.alive?(runtime) do
      Process.unlink(runtime)
      reference = Process.monitor(runtime)
      Runtime.shutdown(runtime)
      assert_receive {:DOWN, ^reference, :process, ^runtime, _reason}, 1_000
    end
  end
end
