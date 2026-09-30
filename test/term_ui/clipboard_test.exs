defmodule TermUI.ClipboardTest do
  use ExUnit.Case, async: true

  alias TermUI.Backend.Manager, as: BackendManager
  alias TermUI.{Clipboard, Command, Frame}
  alias TermUI.Test.DeterministicBackend

  defmodule ClipboardApp do
    use TermUI.Elm

    alias TermUI.{Clipboard, Command, Frame}

    @impl true
    def init(opts) do
      state = %{owner: Keyword.fetch!(opts, :test_owner), dimensions: opts[:dimensions]}
      {state, [Clipboard.copy("runtime copy", on_result: &{:copied, &1})]}
    end

    @impl true
    def event_to_msg(_event, _state), do: :ignore

    @impl true
    def update({:copied, result}, state) do
      send(state.owner, {:clipboard_done, result})
      {state, [Command.shutdown()]}
    end

    @impl true
    def view(%{dimensions: {width, height}}), do: Frame.new(width, height)
  end

  test "copy creates bounded clipboard command data" do
    assert %Command{kind: :clipboard, value: {operation, mapper}} =
             Clipboard.copy("hello", target: :primary)

    assert operation.kind == :write
    assert operation.target == :primary
    assert operation.content == "hello"
    assert mapper.(:ok) == {:clipboard_result, :ok}
  end

  test "OSC 52 encoding supports write and clear operations" do
    operation = Clipboard.operation("hello")
    assert {:ok, "\e]52;c;aGVsbG8=\e\\"} = Clipboard.sequence(operation)

    assert {:ok, "\e]52;p;\e\\"} =
             Clipboard.clear_operation(target: :primary) |> Clipboard.sequence()

    assert {:ok, "\e]52;s;aGVsbG8=\e\\"} =
             Clipboard.operation("hello", target: :secondary) |> Clipboard.sequence()
  end

  test "OSC 52 encoding rejects invalid targets and oversized content" do
    assert_raise ArgumentError, fn -> Clipboard.operation("hello", target: :invalid) end
    assert_raise ArgumentError, fn -> Clipboard.operation("hello", max_bytes: 0) end

    operation = Clipboard.operation("toolong", max_bytes: 3)
    assert {:error, {:clipboard_too_large, 7, 3}} = Clipboard.sequence(operation)
  end

  test "clear creates a backend command with the default result mapper" do
    assert %Command{kind: :clipboard, value: {operation, mapper}} = Clipboard.clear()
    assert operation.kind == :clear
    assert mapper.(:ok) == {:clipboard_result, :ok}
  end

  test "a caller can replace the result message mapper" do
    assert %Command{value: {_operation, mapper}} =
             Clipboard.copy("hello", on_result: &{:copied, &1})

    assert mapper.({:error, :unsupported}) == {:copied, {:error, :unsupported}}
  end

  test "the backend manager serializes clipboard state" do
    operation = Clipboard.operation("manager copy")

    assert {:ok, manager} =
             BackendManager.start_link(
               self(),
               {DeterministicBackend, owner: self(), size: {2, 8}},
               []
             )

    assert :ok = BackendManager.clipboard(manager, operation)
    assert_receive {:backend, :clipboard, ^operation}
    assert :ok = BackendManager.close(manager, :normal)
  end

  test "the runtime maps a clipboard result back to the Elm application" do
    assert {:ok, runtime} =
             TermUI.start_link(ClipboardApp,
               backend: {DeterministicBackend, owner: self(), size: {2, 8}},
               test_owner: self()
             )

    reference = Process.monitor(runtime)

    assert_receive {:backend, :clipboard, %Clipboard.Operation{content: "runtime copy"}}
    assert_receive {:clipboard_done, :ok}
    assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}
  end

  test "unsupported custom backends return data instead of crashing the runtime contract" do
    defmodule NoClipboardBackend do
      @behaviour TermUI.Backend

      def init(_opts), do: {:ok, %{}}
      def size(_state), do: {:ok, {1, 1}}
      def capabilities(_state), do: %{}
      def draw(state, %Frame{}), do: {:ok, state}
      def flush(state), do: {:ok, state}
      def poll_event(state, _timeout), do: {:timeout, state}
      def resize(state, _size), do: {:ok, state}
      def shutdown(_state, _reason), do: :ok
    end

    assert {:ok, manager} = BackendManager.start_link(self(), NoClipboardBackend, [])

    assert {:error, {:backend, NoClipboardBackend, :clipboard, :unsupported}} =
             BackendManager.clipboard(manager, Clipboard.operation("copy"))

    assert :ok = BackendManager.close(manager, :normal)
  end
end
