defmodule TermUI.Backend.InputReader do
  @moduledoc false

  use GenServer

  @type result :: {:ok, binary()} | :eof | {:error, term()}

  @doc "Starts a serialized reader for a blocking input function."
  @spec start_link((-> result())) :: GenServer.on_start()
  def start_link(read_fun) when is_function(read_fun, 0) do
    GenServer.start_link(__MODULE__, read_fun)
  end

  @doc "Gets the next input result or returns `:timeout`."
  @spec take(pid(), non_neg_integer()) :: result() | :timeout
  def take(reader, timeout) do
    GenServer.call(reader, {:take, timeout}, timeout + 1_000)
  end

  @doc "Stops an input reader. A `nil` reader is already stopped."
  @spec stop(pid() | nil) :: :ok
  def stop(nil), do: :ok

  def stop(reader) when is_pid(reader) do
    if Process.alive?(reader), do: GenServer.stop(reader, :normal)
    :ok
  catch
    :exit, _reason -> :ok
  end

  @impl true
  @doc false
  def init(read_fun) do
    owner = self()
    worker = spawn_link(fn -> read_loop(owner, read_fun) end)
    {:ok, %{worker: worker, result: nil, waiter: nil}}
  end

  @impl true
  @doc false
  def handle_call({:take, _timeout}, _from, %{result: result} = state) when not is_nil(result) do
    continue_reader(state.worker, result)
    {:reply, result, %{state | result: nil}}
  end

  def handle_call({:take, 0}, _from, state), do: {:reply, :timeout, state}

  def handle_call({:take, timeout}, from, %{waiter: nil} = state) do
    token = make_ref()
    timer = Process.send_after(self(), {:take_timeout, token}, timeout)
    {:noreply, %{state | waiter: {from, token, timer}}}
  end

  @impl true
  @doc false
  def handle_info({:input_result, worker, result}, %{worker: worker, waiter: nil} = state) do
    {:noreply, %{state | result: result}}
  end

  def handle_info(
        {:input_result, worker, result},
        %{worker: worker, waiter: {from, _token, timer}} = state
      ) do
    _cancelled = Process.cancel_timer(timer)
    GenServer.reply(from, result)
    continue_reader(worker, result)
    {:noreply, %{state | waiter: nil}}
  end

  def handle_info({:take_timeout, token}, %{waiter: {from, token, _timer}} = state) do
    GenServer.reply(from, :timeout)
    {:noreply, %{state | waiter: nil}}
  end

  def handle_info({:take_timeout, _old_token}, state), do: {:noreply, state}

  @impl true
  @doc false
  def terminate(_reason, state) do
    if Process.alive?(state.worker), do: Process.exit(state.worker, :kill)
    :ok
  end

  defp read_loop(owner, read_fun) do
    result = read_fun.()
    send(owner, {:input_result, self(), result})

    if match?({:ok, _data}, result) do
      receive do
        :continue -> read_loop(owner, read_fun)
      end
    end
  end

  defp continue_reader(worker, {:ok, _data}), do: send(worker, :continue)
  defp continue_reader(_worker, _result), do: :ok
end
