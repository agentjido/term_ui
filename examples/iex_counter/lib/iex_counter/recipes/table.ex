defmodule IExCounter.Recipes.Table do
  @moduledoc "A table whose selection survives a sort, filter, and row refresh."

  use TermUI.Elm

  alias TermUI.{Command, Event, Frame}
  alias TermUI.Widget.Table
  alias TermUI.Widget.Table.Column

  @impl true
  def init(opts) do
    table =
      Table.init(
        columns: [Column.new(:id, "ID", width: 4), Column.new(:name, "Name")],
        rows: [%{id: 1, name: "Ada"}, %{id: 2, name: "Bea"}, %{id: 3, name: "Cy"}],
        row_id: :id
      )

    %{dimensions: Keyword.fetch!(opts, :dimensions), table: table, filtered: false}
  end

  @impl true
  def event_to_msg(%Event.Key{key: :escape}, _state), do: {:msg, :quit}

  def event_to_msg(%Event.Resize{width: width, height: height}, _state),
    do: {:msg, {:resize, width, height}}

  def event_to_msg(%Event.Text{text: text}, _state) when text in ["s", "S"], do: {:msg, :sort}
  def event_to_msg(%Event.Text{text: text}, _state) when text in ["r", "R"], do: {:msg, :refresh}
  def event_to_msg(%Event.Text{text: text}, _state) when text in ["h", "H"], do: {:msg, :filter}
  def event_to_msg(event, _state), do: {:msg, {:event, event}}

  @impl true
  def update(:quit, state), do: {state, [Command.shutdown()]}
  def update({:resize, width, height}, state), do: %{state | dimensions: {width, height}}
  def update(:sort, state), do: %{state | table: Table.toggle_sort(state.table, :name)}

  def update(:refresh, state) do
    rows = [%{id: 3, name: "Cy"}, %{id: 2, name: "Bea updated"}, %{id: 1, name: "Ada"}]
    %{state | table: Table.set_rows(state.table, rows)}
  end

  def update(:filter, state) do
    filter = if state.filtered, do: nil, else: &(&1.id != 2)
    %{state | table: Table.set_filter(state.table, filter), filtered: not state.filtered}
  end

  def update({:event, event}, state) do
    {table, _messages} = Table.update(event, state.table)
    %{state | table: table}
  end

  @impl true
  def view(%{dimensions: {width, height}} = state) do
    selected = state.table |> Table.selected_ids() |> Enum.sort()

    Frame.new(width, height)
    |> Frame.overlay(Table.view(state.table, {width, max(height - 2, 1)}), 1, 1)
    |> Frame.put_row(max(height - 1, 1), "Selected IDs: #{inspect(selected)}")
    |> Frame.put_row(height, "S: sort   H: hide Bea   R: refresh   Esc: quit")
  end
end
