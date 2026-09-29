defmodule TermUI.Test.WindowsConsoleApp do
  use TermUI.Elm

  alias TermUI.{Command, Event, Frame, Style}

  @impl true
  def init(opts) do
    %{
      owner: Keyword.fetch!(opts, :probe_owner),
      dimensions: Keyword.fetch!(opts, :dimensions),
      events: []
    }
  end

  @impl true
  def event_to_msg(event, _state), do: {:msg, {:event, event}}

  @impl true
  def update({:event, %Event.Text{text: "q"}}, state),
    do: {state, [Command.shutdown(:normal)]}

  def update({:event, %Event.Resize{width: width, height: height}}, state),
    do: %{state | dimensions: {width, height}}

  def update({:event, %Event.Text{text: text}}, state),
    do: %{state | events: state.events ++ [%{text: text}]}

  def update({:event, %Event.Key{key: key, modifiers: modifiers}}, state) do
    event = %{key: to_string(key), modifiers: Enum.map(modifiers, &to_string/1)}
    %{state | events: state.events ++ [event]}
  end

  def update({:event, _event}, state), do: state

  @impl true
  def view(state) do
    {width, height} = state.dimensions
    blue = Style.new(bg: {:rgb, 10, 20, 180})
    yellow = Style.new(fg: {:rgb, 240, 200, 20}, bg: {:rgb, 10, 20, 180})
    blank = [{String.duplicate(" ", width), blue}]

    Frame.from_rows(List.duplicate(blank, height), width, height)
    |> Frame.put_row(1, [{"READY #{length(state.events)}", yellow}])
    |> Frame.put_row(2, [{"é界", yellow}])
    |> Frame.put_row(height, [{String.duplicate(".", width - 1) <> "!", yellow}])
  end

  @impl true
  def terminate(reason, state) do
    send(state.owner, {:console_probe_stopped, reason, state})
    :ok
  end
end

defmodule TermUI.Test.WindowsConsoleProbe do
  alias TermUI.Runtime

  def run do
    backend = System.fetch_env!("TERM_UI_CONSOLE_BACKEND") |> String.to_existing_atom()
    progress = System.fetch_env!("TERM_UI_CONSOLE_PROGRESS")

    {:ok, runtime} =
      TermUI.start_link(TermUI.Test.WindowsConsoleApp,
        probe_owner: self(),
        backend: backend,
        backend_opts: [alternate_screen: true, size_poll_interval: 100]
      )

    reference = Process.monitor(runtime)
    :ok = Runtime.sync(runtime)
    info = Runtime.get_state(runtime)
    manager = info.backend_manager
    reader = :sys.get_state(manager).backend_state.input_reader
    loop(runtime, reference, manager, reader, progress, info.backend, nil)
  end

  defp loop(runtime, reference, manager, reader, progress, backend, previous) do
    receive do
      {:console_probe_stopped, reason, state} ->
        receive do
          {:DOWN, ^reference, :process, ^runtime, :normal} ->
            result = snapshot(state, backend)

            result =
              Map.merge(result, %{
                reason: inspect(reason),
                manager_stopped: not Process.alive?(manager),
                reader_stopped: is_nil(reader) or not Process.alive?(reader)
              })

            File.write!(progress <> ".result", Jason.encode!(result))
        after
          5_000 -> raise "console runtime did not stop normally"
        end

      {:DOWN, ^reference, :process, ^runtime, reason} ->
        raise "console runtime stopped before its application: #{inspect(reason)}"
    after
      10 ->
        current = current_snapshot(runtime, backend) || previous

        if current != previous do
          temporary = progress <> ".tmp"
          File.write!(temporary, Jason.encode!(current))
          File.rename!(temporary, progress)
        end

        loop(runtime, reference, manager, reader, progress, backend, current)
    end
  end

  defp current_snapshot(runtime, backend) do
    runtime |> Runtime.get_state() |> Map.fetch!(:app_state) |> snapshot(backend)
  catch
    :exit, _reason -> nil
  end

  defp snapshot(state, backend) do
    %{
      dimensions: Tuple.to_list(state.dimensions),
      events: state.events,
      backend: inspect(backend)
    }
  end
end

TermUI.Test.WindowsConsoleProbe.run()
