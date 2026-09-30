defmodule TermUI.Test.WindowsConsoleApp do
  use TermUI.Elm

  alias TermUI.{Command, Event}
  alias TermUI.Component.RenderNode
  alias TermUI.Renderer.Cell

  @impl true
  def init(opts) do
    {rows, columns} = TermUI.Platform.terminal_size()
    %{dimensions: {columns, rows}, events: [], owner: Keyword.fetch!(opts, :probe_owner)}
  end

  @impl true
  def event_to_msg(event, _state), do: {:msg, {:event, event}}

  @impl true
  def update({:event, %Event.Key{key: "q", modifiers: []}}, state),
    do: {state, [Command.quit()]}

  def update({:event, %Event.Resize{width: width, height: height}}, state),
    do: {%{state | dimensions: {width, height}}, []}

  def update({:event, %Event.Key{key: key, modifiers: modifiers}}, state) do
    event = %{key: to_string(key), modifiers: Enum.map(modifiers, &to_string/1)}
    {%{state | events: state.events ++ [event]}, []}
  end

  def update({:event, _event}, state), do: {state, []}

  @impl true
  def view(state) do
    {width, height} = state.dimensions
    blank = Cell.new(" ", bg: {10, 20, 180})

    cells =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: %{} do
        {{x, y}, blank}
      end

    text = "READY #{length(state.events)}"
    cells = put_text(cells, 0, text)
    cells = put_text(cells, 1, "é界")
    cells = put_text(cells, height - 1, String.duplicate(".", width - 1) <> "!")

    cells
    |> Enum.map(fn {{x, y}, cell} -> %{x: x, y: y, cell: cell} end)
    |> RenderNode.cells()
  end

  defp put_text(cells, row, text) do
    {cells, _column} =
      Enum.reduce(String.graphemes(text), {cells, 0}, fn char, {cells, column} ->
        cell = Cell.new(char, fg: {240, 200, 20}, bg: {10, 20, 180})
        cells = Map.put(cells, {column, row}, cell)

        cells =
          if cell.width == 2,
            do: Map.put(cells, {column + 1, row}, Cell.wide_placeholder(cell)),
            else: cells

        {cells, column + cell.width}
      end)

    cells
  end
end

defmodule TermUI.Test.WindowsConsoleProbe do
  alias TermUI.Runtime

  def run do
    backend = System.fetch_env!("TERM_UI_CONSOLE_BACKEND") |> String.to_existing_atom()
    progress = System.fetch_env!("TERM_UI_CONSOLE_PROGRESS")

    {:ok, runtime} =
      Runtime.start_link(
        root: TermUI.Test.WindowsConsoleApp,
        probe_owner: self(),
        backend: backend
      )

    reference = Process.monitor(runtime)
    :ok = Runtime.sync(runtime)
    state = Runtime.get_state(runtime)
    legacy_worker = if is_pid(state.input_reader), do: :sys.get_state(state.input_reader).port

    readers =
      Enum.filter([state.input_reader, state.input_handler_reader, legacy_worker], &is_pid/1)

    task_supervisor = :sys.get_state(state.command_executor).task_supervisor

    owners =
      Enum.filter([state.buffer_manager, state.command_executor, task_supervisor], &is_pid/1)

    loop(runtime, reference, readers, owners, progress, state.backend, nil)
  end

  defp loop(runtime, reference, readers, owners, progress, backend, previous) do
    receive do
      {:DOWN, ^reference, :process, ^runtime, :normal} ->
        result =
          Map.merge(previous, %{
            reason: ":normal",
            owners_stopped: Enum.all?(owners, &(not Process.alive?(&1))),
            reader_stopped: Enum.all?(readers, &(not Process.alive?(&1)))
          })

        File.write!(progress <> ".result", Jason.encode!(result))

      {:DOWN, ^reference, :process, ^runtime, reason} ->
        raise "console runtime stopped unexpectedly: #{inspect(reason)}"
    after
      10 ->
        current = snapshot(runtime, backend) || previous

        if current != previous do
          File.write!(progress <> ".tmp", Jason.encode!(current))
          File.rename!(progress <> ".tmp", progress)
        end

        loop(runtime, reference, readers, owners, progress, backend, current)
    end
  end

  defp snapshot(runtime, backend) do
    runtime_state = Runtime.get_state(runtime)
    state = runtime_state.root_state

    %{
      dimensions: Tuple.to_list(state.dimensions),
      events: state.events,
      backend: inspect(backend),
      io_options: inspect(:io.getopts())
    }
  catch
    :exit, _reason -> nil
  end
end

TermUI.Test.WindowsConsoleProbe.run()
