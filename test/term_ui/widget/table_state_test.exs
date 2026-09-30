defmodule TermUI.Widget.TableStateTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}
  alias TermUI.Widget.Table
  alias TermUI.Widget.Table.Column

  @rows [
    %{id: :a, name: "Alpha", score: 2, active: true},
    %{id: :b, name: "Beta", score: 1, active: true},
    %{id: :c, name: "Gamma", score: 1, active: false}
  ]

  @columns [
    Column.new(:name, "Name", width: 10),
    Column.new(:score, "Score", width: 8)
  ]

  test "sorting is stable and cycles through both directions and source order" do
    table = Table.init(columns: @columns, rows: @rows, row_id: :id)

    ascending = Table.toggle_sort(table, :score)
    assert ascending.sort_direction == :asc
    assert Enum.map(Table.display_rows(ascending), & &1.id) == [:b, :c, :a]

    descending = Table.toggle_sort(ascending, :score)
    assert descending.sort_direction == :desc
    assert Enum.map(Table.display_rows(descending), & &1.id) == [:a, :b, :c]

    source = Table.toggle_sort(descending, :score)
    assert source.sort_direction == nil
    assert Enum.map(Table.display_rows(source), & &1.id) == [:a, :b, :c]

    assert Frame.row_text(Table.view(ascending, {24, 4}), 1) =~ "Score ↑"
  end

  test "selection survives sorting and filtering and drops only removed row identities" do
    table =
      Table.init(
        columns: @columns,
        rows: @rows,
        row_id: :id,
        selection_mode: :multiple
      )
      |> Table.set_selection([:b, :c])
      |> Table.sort_by(:name, :desc)
      |> Table.set_filter(& &1.active)

    assert Table.selected_ids(table) == MapSet.new([:b, :c])
    assert Enum.map(Table.display_rows(table), & &1.id) == [:b, :a]

    changed_rows = [
      %{id: :a, name: "Alpha changed", score: 0, active: true},
      %{id: :c, name: "Gamma changed", score: 4, active: false}
    ]

    table = Table.set_rows(table, changed_rows)
    assert Table.selected_ids(table) == MapSet.new([:c])

    table = Table.set_filter(table, nil)
    assert Enum.map(Table.selected_rows(table), & &1.id) == [:c]
    assert Enum.map(Table.display_rows(table), & &1.id) == [:c, :a]
  end

  test "keyboard and mouse use the same multiple-selection transition" do
    initial =
      Table.init(
        columns: @columns,
        rows: @rows,
        row_id: :id,
        selection_mode: :multiple
      )

    {keyboard, []} = Table.update(Event.key(:down), initial)
    {keyboard, keyboard_messages} = Table.update(Event.text(" "), keyboard)

    {mouse, mouse_messages} =
      Table.mouse(Event.mouse(:release, :left, 0, 2), initial, {24, 4})

    assert mouse == keyboard
    assert mouse_messages == keyboard_messages
    assert mouse_messages == [{:selection_changed, [Enum.at(@rows, 1)]}]
  end

  test "view size changes do not change sorting, cursor, or selection state" do
    table =
      Table.init(columns: @columns, rows: @rows, row_id: :id)
      |> Table.sort_by(:score, :asc)

    {table, []} = Table.update(Event.key(:home), table)
    {table, [{:selected, %{id: :b}}]} = Table.update(Event.key(:enter), table)

    assert %Frame{} = Table.view(table, {24, 2})
    assert %Frame{} = Table.view(table, {80, 20})
    assert table.sort_direction == :asc
    assert table.cursor == 0
    assert Table.selected_ids(table) == MapSet.new([:b])
  end

  test "row identities must be unique" do
    assert_raise ArgumentError, "table row identities must be unique", fn ->
      Table.init(columns: @columns, rows: [%{id: 1}, %{id: 1}], row_id: :id)
    end
  end
end
