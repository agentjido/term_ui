defmodule TermUI.Command.Executor do
  @moduledoc """
  Executes commands asynchronously under a Task.Supervisor.

  The executor runs commands in isolated tasks, preventing failures
  from crashing the runtime. Results are sent back as messages to
  the originating component.

  ## Usage

      # Start an independent executor
      {:ok, executor} = Executor.start_link()

      # Execute a command
      {:ok, command_id} = Executor.execute(executor, command, runtime_pid, component_id)

      # Cancel a running command
      :ok = Executor.cancel(executor, command_id)

  `TermUI.Runtime` starts and links a private executor for its root commands.
  Applications normally use `TermUI.Command` through that runtime; start an
  executor directly only for a custom host.
  """

  use GenServer

  alias TermUI.Command

  # Dialyzer: Functions with unmatched return values in side-effect calls
  @dialyzer {:nowarn_function, execute_command: 4, handle_call: 3, handle_info: 2}

  @type t :: pid()

  # Default max concurrent commands
  @default_max_concurrent 100

  # --- Public API ---

  @doc """
  Starts the command executor.

  ## Options

  - `:name` - GenServer name (optional)
  - `:max_concurrent` - Maximum concurrent commands (default: 100)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Executes a command asynchronously.

  Returns the command ID that can be used for cancellation.
  Results are sent to the runtime as `{:command_result, component_id, command_id, result}`.
  """
  @spec execute(t(), Command.t(), pid(), atom()) :: {:ok, reference()} | {:error, term()}
  def execute(executor, %Command{} = command, runtime_pid, component_id) do
    GenServer.call(executor, {:execute, command, runtime_pid, component_id})
  end

  @doc """
  Cancels a running command by ID.
  """
  @spec cancel(t(), reference()) :: :ok | {:error, :not_found}
  def cancel(executor, command_id) do
    GenServer.call(executor, {:cancel, command_id})
  end

  @doc """
  Cancels all commands for a component.

  Used when a component unmounts.
  """
  @spec cancel_all_for_component(t(), atom()) :: :ok
  def cancel_all_for_component(executor, component_id) do
    GenServer.call(executor, {:cancel_all_for_component, component_id})
  end

  @doc """
  Returns the number of currently running commands.
  """
  @spec running_count(t()) :: non_neg_integer()
  def running_count(executor) do
    GenServer.call(executor, :running_count)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    max_concurrent = Keyword.get(opts, :max_concurrent, @default_max_concurrent)

    # Start Task.Supervisor for command execution
    {:ok, task_sup} = Task.Supervisor.start_link()

    state = %{
      task_supervisor: task_sup,
      running: %{},
      intervals: %{},
      max_concurrent: max_concurrent
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:execute, command, runtime_pid, component_id}, _from, state) do
    # Check concurrent limit
    if map_size(state.running) >= state.max_concurrent do
      {:reply, {:error, :max_concurrent_reached}, state}
    else
      # Assign ID if not already assigned
      command = if command.id, do: command, else: Command.assign_id(command)

      case execute_command(command, runtime_pid, component_id, state) do
        {:ok, new_state} ->
          {:reply, {:ok, command.id}, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:cancel, command_id}, _from, state) do
    case Map.get(state.running, command_id) do
      nil ->
        # Check intervals
        case Map.get(state.intervals, command_id) do
          nil ->
            {:reply, {:error, :not_found}, state}

          %{timer_ref: timer_ref} ->
            Process.cancel_timer(timer_ref)
            intervals = Map.delete(state.intervals, command_id)
            {:reply, :ok, %{state | intervals: intervals}}
        end

      info ->
        Task.Supervisor.terminate_child(state.task_supervisor, info.task.pid)
        running = Map.delete(state.running, command_id)
        {:reply, :ok, %{state | running: running}}
    end
  end

  @impl true
  def handle_call({:cancel_all_for_component, component_id}, _from, state) do
    # Cancel all running tasks for the component
    {to_cancel, to_keep} =
      Enum.split_with(state.running, fn {_id, info} ->
        info.component_id == component_id
      end)

    Enum.each(to_cancel, fn {_id, info} ->
      Task.Supervisor.terminate_child(state.task_supervisor, info.task.pid)
    end)

    # Cancel all intervals for the component
    {intervals_to_cancel, intervals_to_keep} =
      Enum.split_with(state.intervals, fn {_id, info} ->
        is_map(info) and info.component_id == component_id
      end)

    Enum.each(intervals_to_cancel, fn {_id, info} ->
      if is_map(info), do: Process.cancel_timer(info.timer_ref)
    end)

    state = %{
      state
      | running: Map.new(to_keep),
        intervals: Map.new(intervals_to_keep)
    }

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:running_count, _from, state) do
    {:reply, map_size(state.running), state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Task completed successfully
    case find_by_task_ref(state.running, ref) do
      {command_id, info} ->
        # Demonitor and flush
        Process.demonitor(ref, [:flush])

        # Send result to runtime
        send_result(info.runtime_pid, info.component_id, command_id, result)

        running = Map.delete(state.running, command_id)
        {:noreply, %{state | running: running}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Task crashed
    case find_by_task_ref(state.running, ref) do
      {command_id, info} ->
        # Send error to runtime
        send_result(info.runtime_pid, info.component_id, command_id, {:error, reason})

        running = Map.delete(state.running, command_id)
        {:noreply, %{state | running: running}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        {:interval_tick, command_id, runtime_pid, component_id, message, interval_ms},
        state
      ) do
    # Deliver interval message
    send_result(runtime_pid, component_id, command_id, message)

    # Schedule next tick
    timer_ref =
      Process.send_after(
        self(),
        {:interval_tick, command_id, runtime_pid, component_id, message, interval_ms},
        interval_ms
      )

    intervals =
      Map.put(state.intervals, command_id, %{
        timer_ref: timer_ref,
        component_id: component_id
      })

    {:noreply, %{state | intervals: intervals}}
  end

  @impl true
  def handle_info({:timeout, command_id}, state) do
    # Command timed out
    case Map.get(state.running, command_id) do
      nil ->
        {:noreply, state}

      info ->
        Task.Supervisor.terminate_child(state.task_supervisor, info.task.pid)
        send_result(info.runtime_pid, info.component_id, command_id, {:error, :timeout})
        running = Map.delete(state.running, command_id)
        {:noreply, %{state | running: running}}
    end
  end

  # --- Private Functions ---

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.intervals, fn {_id, interval} ->
      Process.cancel_timer(interval.timer_ref)
    end)

    if Process.alive?(state.task_supervisor) do
      Supervisor.stop(state.task_supervisor, :normal)
    end

    :ok
  end

  defp execute_command(%Command{type: :none}, _runtime_pid, _component_id, state) do
    {:ok, state}
  end

  defp execute_command(%Command{type: :timer} = cmd, runtime_pid, component_id, state) do
    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        Process.sleep(cmd.payload)
        cmd.on_result
      end)

    running =
      Map.put(state.running, cmd.id, %{
        task: task,
        runtime_pid: runtime_pid,
        component_id: component_id
      })

    # Set timeout if specified
    if cmd.timeout != :infinity do
      Process.send_after(self(), {:timeout, cmd.id}, cmd.timeout)
    end

    {:ok, %{state | running: running}}
  end

  defp execute_command(%Command{type: :interval} = cmd, runtime_pid, component_id, state) do
    # Schedule first tick
    timer_ref =
      Process.send_after(
        self(),
        {:interval_tick, cmd.id, runtime_pid, component_id, cmd.on_result, cmd.payload},
        cmd.payload
      )

    intervals =
      Map.put(state.intervals, cmd.id, %{
        timer_ref: timer_ref,
        component_id: component_id
      })

    {:ok, %{state | intervals: intervals}}
  end

  defp execute_command(%Command{type: :file_read} = cmd, runtime_pid, component_id, state) do
    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        case File.read(cmd.payload) do
          {:ok, content} -> {cmd.on_result, {:ok, content}}
          {:error, reason} -> {cmd.on_result, {:error, reason}}
        end
      end)

    running =
      Map.put(state.running, cmd.id, %{
        task: task,
        runtime_pid: runtime_pid,
        component_id: component_id
      })

    if cmd.timeout != :infinity do
      Process.send_after(self(), {:timeout, cmd.id}, cmd.timeout)
    end

    {:ok, %{state | running: running}}
  end

  defp execute_command(%Command{type: :send_after} = cmd, runtime_pid, component_id, state) do
    {target_component, message, delay_ms} = cmd.payload

    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        Process.sleep(delay_ms)
        # Return the target and message for the runtime to route
        {:send_to, target_component, message}
      end)

    running =
      Map.put(state.running, cmd.id, %{
        task: task,
        runtime_pid: runtime_pid,
        component_id: component_id
      })

    {:ok, %{state | running: running}}
  end

  defp execute_command(%Command{type: type}, _runtime_pid, _component_id, _state) do
    {:error, {:unknown_command_type, type}}
  end

  defp send_result(runtime_pid, component_id, command_id, result) do
    send(runtime_pid, {:command_result, component_id, command_id, result})
  end

  defp find_by_task_ref(running, ref) do
    Enum.find(running, fn {_id, info} -> info.task.ref == ref end)
  end
end
