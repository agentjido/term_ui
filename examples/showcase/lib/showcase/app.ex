defmodule Showcase.App do
  @moduledoc "The interactive TermUI widget and architecture showcase."

  use TermUI.Elm

  alias TermUI.Event.{Key, Resize, Text}
  alias TermUI.{Clipboard, Command, Frame, Style}
  alias Showcase.{LiveData, SnapshotData}
  alias Showcase.Pages.{Architecture, Beam, Content, Controls, Inputs, Overview}

  @refresh_interval 1_000
  @pages [
    {:overview, "Overview", Overview},
    {:inputs, "Inputs", Inputs},
    {:content, "Content", Content},
    {:beam, "BEAM", Beam},
    {:architecture, "Architecture", Architecture},
    {:controls, "Controls", Controls}
  ]

  @impl true
  def init(opts) do
    data_mode = Keyword.get(opts, :data_mode, :live)

    unless data_mode in [:live, :snapshot] do
      raise ArgumentError, "data_mode must be :live or :snapshot"
    end

    page_states = Map.new(@pages, fn {id, _label, module} -> {id, module.init()} end)

    state = %{
      command_mode: false,
      data_mode: data_mode,
      dimensions: Keyword.fetch!(opts, :dimensions),
      last_snapshot: nil,
      page: :overview,
      page_states: page_states,
      refreshing: data_mode == :live,
      theme: :dark,
      status: "Press Escape, then 1 through 6, to select a page"
    }

    case data_mode do
      :live -> {state, [collect_command(self()), refresh_timer()]}
      :snapshot -> state |> apply_snapshot(SnapshotData.snapshot()) |> snapshot_status()
    end
  end

  @impl true
  def event_to_msg(%Resize{width: width, height: height}, _state),
    do: {:msg, {:resize, width, height}}

  def event_to_msg(%Key{key: :escape}, _state), do: {:msg, :toggle_command_mode}

  def event_to_msg(%Text{text: key}, %{command_mode: true})
      when key in ["1", "2", "3", "4", "5", "6", "n", "p", "q", "r", "t"],
      do: {:msg, {:command_key, key}}

  def event_to_msg(%Key{key: key}, %{command_mode: true}) when key in [:left, :right],
    do: {:msg, {:command_key, key}}

  def event_to_msg(%Key{key: key, modifiers: modifiers} = event, _state)
      when key in [:left, :right] do
    if :ctrl in modifiers,
      do: {:msg, arrow_message(key)},
      else: {:msg, {:page_event, event}}
  end

  def event_to_msg(%Key{key: key, modifiers: modifiers} = event, _state)
      when key in ["n", "p", "q", "r", "t"] do
    if :ctrl in modifiers,
      do: {:msg, control_message(key)},
      else: {:msg, {:page_event, event}}
  end

  def event_to_msg(_event, %{command_mode: true}), do: {:msg, :close_command_mode}

  def event_to_msg(event, _state), do: {:msg, {:page_event, event}}

  @impl true
  def update({:resize, width, height}, state),
    do: %{state | dimensions: {width, height}, status: "Terminal resized to #{width}x#{height}"}

  def update({:select_page, page}, state), do: select_page(state, page)
  def update(:next_page, state), do: move_page(state, 1)
  def update(:previous_page, state), do: move_page(state, -1)
  def update(:toggle_theme, state), do: toggle_theme(state)
  def update(:quit, state), do: {state, [Command.shutdown()]}
  def update(:refresh, state), do: request_refresh(state)
  def update(:toggle_command_mode, state), do: toggle_command_mode(state)
  def update(:close_command_mode, state), do: close_command_mode(state)
  def update({:command_key, key}, state), do: apply_command_key(state, key)

  def update(:refresh_timer, state) do
    {state, commands} = request_refresh(state)
    {state, commands ++ [refresh_timer()]}
  end

  def update({:page_event, event}, state) do
    {state, messages} = update_current_page(state, event)
    apply_page_messages(state, messages)
  end

  def update({:clipboard_result, :ok}, state), do: %{state | status: "Copied to clipboard"}

  def update({:clipboard_result, {:error, reason}}, state),
    do: %{state | status: "Clipboard error: #{inspect(reason)}"}

  def update({:live_snapshot, {:ok, snapshot}}, state) do
    state
    |> apply_snapshot(snapshot)
    |> Map.put(:refreshing, false)
    |> live_status()
  end

  def update({:live_snapshot, {:error, reason}}, state),
    do: %{state | refreshing: false, status: "Live refresh failed: #{inspect(reason)}"}

  @impl true
  def view(%{dimensions: {width, height}} = state) do
    if height < 4 do
      Frame.from_rows([[{" TermUI Showcase ", header_style(state.theme)}]], width, height)
    else
      {_id, label, module} = current_page(state)
      content_height = height - 3

      content =
        module.view(
          Map.fetch!(state.page_states, state.page),
          {width, content_height},
          state.theme
        )

      Frame.new(width, height)
      |> Frame.put_row(1, header_row(label, state.data_mode, state.theme))
      |> Frame.put_row(2, page_row(state.page, state.theme))
      |> Frame.put_row(height, footer_row(state, width))
      |> Frame.overlay(content, 1, 3)
    end
  end

  @doc "Runs the showcase in the current terminal."
  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []), do: TermUI.run(__MODULE__, opts)

  @doc false
  def pages, do: @pages

  defp update_current_page(state, event) do
    {_id, _label, module} = current_page(state)
    page_state = Map.fetch!(state.page_states, state.page)
    {page_state, messages} = module.update(event, page_state)
    {%{state | page_states: Map.put(state.page_states, state.page, page_state)}, messages}
  end

  defp apply_page_messages(state, messages) do
    {commands, status} =
      Enum.reduce(messages, {[], nil}, fn
        {:copy, text}, {commands, _status} ->
          {[Clipboard.copy(text) | commands], "Copy requested"}

        :refresh_requested, {commands, _status} ->
          {[Command.message(:refresh) | commands], "Refresh requested"}

        message, {commands, _status} ->
          {commands, format_message(message)}
      end)

    state = if status, do: %{state | status: status}, else: state
    if commands == [], do: state, else: {state, Enum.reverse(commands)}
  end

  defp current_page(state),
    do: Enum.find(@pages, fn {id, _label, _module} -> id == state.page end)

  defp select_page(state, page) do
    case Enum.find(@pages, fn {id, _label, _module} -> id == page end) do
      nil ->
        state

      {_id, label, module} ->
        %{state | command_mode: false, page: page, status: label <> ": " <> module.help()}
    end
  end

  defp move_page(state, delta) do
    ids = Enum.map(@pages, &elem(&1, 0))
    index = Enum.find_index(ids, &(&1 == state.page)) || 0
    next = rem(index + delta + length(ids), length(ids))
    select_page(state, Enum.at(ids, next))
  end

  defp toggle_theme(state) do
    theme = if state.theme == :dark, do: :light, else: :dark
    %{state | command_mode: false, theme: theme, status: "Theme: #{theme}"}
  end

  defp header_row(label, data_mode, theme) do
    [
      {" TermUI Showcase ", header_style(theme)},
      {" #{label} · #{data_mode |> Atom.to_string() |> String.upcase()}",
       Style.new(fg: accent(theme), attrs: [:bold])}
    ]
  end

  defp page_row(selected, theme) do
    @pages
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{id, label, _module}, index} ->
      style =
        if id == selected,
          do: Style.new(fg: :black, bg: accent(theme), attrs: [:bold]),
          else: Style.new(fg: :bright_black)

      [{" #{index} #{label} ", style}, " "]
    end)
  end

  defp footer_row(%{command_mode: true}, width) do
    menu = "Choose 1-6 page  N/P next  R refresh  T theme  Q quit  Esc close"
    [{Frame.fit(menu, width), Style.new(fg: :black, bg: :cyan, attrs: [:bold])}]
  end

  defp footer_row(%{status: status}, width) do
    controls = "Esc menu  Ctrl+N/P page  Ctrl+R refresh  Ctrl+Q quit"
    available = max(width - String.length(controls) - 1, 0)

    [
      {Frame.fit(status, available), Style.new(fg: :bright_black)},
      {controls, Style.new(fg: :cyan)}
    ]
  end

  defp header_style(:light), do: Style.new(fg: :white, bg: :blue, attrs: [:bold])
  defp header_style(:dark), do: Style.new(fg: :black, bg: :cyan, attrs: [:bold])
  defp accent(:light), do: :blue
  defp accent(:dark), do: :cyan

  defp control_message("n"), do: :next_page
  defp control_message("p"), do: :previous_page
  defp control_message("q"), do: :quit
  defp control_message("r"), do: :refresh
  defp control_message("t"), do: :toggle_theme

  defp arrow_message(:left), do: :previous_page
  defp arrow_message(:right), do: :next_page

  defp toggle_command_mode(%{command_mode: false} = state) do
    %{
      state
      | command_mode: true,
        status: "Choose 1-6 page, N/P next, R refresh, T theme, or Q quit"
    }
  end

  defp toggle_command_mode(state), do: close_command_mode(state)

  defp close_command_mode(state),
    do: %{state | command_mode: false, status: "Command menu closed"}

  defp apply_command_key(state, key) do
    state = %{state | command_mode: false}

    case command_message(key) do
      :refresh -> request_refresh(state)
      message -> update(message, state)
    end
  end

  defp command_message("1"), do: {:select_page, :overview}
  defp command_message("2"), do: {:select_page, :inputs}
  defp command_message("3"), do: {:select_page, :content}
  defp command_message("4"), do: {:select_page, :beam}
  defp command_message("5"), do: {:select_page, :architecture}
  defp command_message("6"), do: {:select_page, :controls}
  defp command_message("n"), do: :next_page
  defp command_message("p"), do: :previous_page
  defp command_message("q"), do: :quit
  defp command_message("r"), do: :refresh
  defp command_message("t"), do: :toggle_theme
  defp command_message(:left), do: :previous_page
  defp command_message(:right), do: :next_page

  defp request_refresh(%{data_mode: :live, refreshing: false} = state),
    do:
      {%{state | refreshing: true, status: "Collecting live BEAM data"},
       [collect_command(self())]}

  defp request_refresh(%{data_mode: :live} = state), do: {state, []}

  defp request_refresh(%{data_mode: :snapshot} = state) do
    state = state |> apply_snapshot(SnapshotData.snapshot()) |> snapshot_status()
    {state, []}
  end

  defp apply_snapshot(state, snapshot) do
    page_states =
      state.page_states
      |> Map.update!(:overview, &Overview.set_snapshot(&1, snapshot))
      |> Map.update!(:content, &Content.set_snapshot(&1, snapshot))
      |> Map.update!(:beam, &Beam.set_snapshot(&1, snapshot))
      |> Map.update!(:controls, &Controls.tick/1)

    %{state | last_snapshot: snapshot, page_states: page_states}
  end

  defp live_status(state) do
    system = state.last_snapshot.system

    %{
      state
      | status:
          "Live: #{system.process_count} processes, run queue #{system.run_queue}, " <>
            "#{length(state.last_snapshot.cluster)} nodes"
    }
  end

  defp snapshot_status(state), do: %{state | status: "Fixed snapshot mode for tests and docs"}

  defp collect_command(runtime) do
    Command.async(fn -> LiveData.collect(runtime) end, &{:live_snapshot, &1})
  end

  defp refresh_timer, do: Command.timer(@refresh_interval, :refresh_timer)

  defp format_message({kind, value}) when kind in [:changed, :submit, :selected, :picked],
    do: "#{kind}: #{inspect(value, limit: 3)}"

  defp format_message(message), do: inspect(message, limit: 4)
end
