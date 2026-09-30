defmodule IExCounter.RecipesTest do
  use ExUnit.Case, async: true

  alias IExCounter.Recipes
  alias TermUI.{Command, Event, Frame}
  alias TermUI.Widget.Table

  test "text and paste go to the focused input; only it owns the cursor" do
    state = Recipes.InputFocus.init(dimensions: {40, 8})
    state = event(Recipes.InputFocus, state, Event.text("Ada"))
    state = event(Recipes.InputFocus, state, Event.key(:tab))
    state = event(Recipes.InputFocus, state, Event.paste("Zürich\n"))
    frame = Recipes.InputFocus.view(state)
    assert String.trim(Frame.row_text(frame, 2)) == "Ada"
    assert String.trim(Frame.row_text(frame, 4)) == "Zürich"
    assert frame.cursor == {7, 4}

    state = event(Recipes.InputFocus, state, Event.key(:tab, modifiers: [:shift]))
    assert Recipes.InputFocus.view(state).cursor == {4, 2}
  end

  test "a form rejects empty input then submits its edited values" do
    state = Recipes.Form.init(dimensions: {40, 8})
    state = event(Recipes.Form, state, Event.key(:enter))
    assert state.form.errors.name == "is required"
    assert Frame.row_text(Recipes.Form.view(state), 7) =~ "Fix the required fields"

    state = event(Recipes.Form, state, Event.paste("Ada"))
    state = event(Recipes.Form, state, Event.key(:tab))
    state = event(Recipes.Form, state, Event.key(:right))
    state = event(Recipes.Form, state, Event.key(:tab))
    state = event(Recipes.Form, state, Event.text(" "))
    state = event(Recipes.Form, state, Event.key(:enter))
    assert state.form.values == %{name: "Ada", role: "writer", alerts: true}
    assert state.form.errors == %{}
    assert Frame.row_text(Recipes.Form.view(state), 7) =~ "Saved: Ada (writer)"
  end

  test "table selection follows the row id through refresh, sort, and filter" do
    state = Recipes.Table.init(dimensions: {60, 8})
    state = event(Recipes.Table, state, Event.key(:down))
    state = event(Recipes.Table, state, Event.key(:enter))
    state = event(Recipes.Table, state, Event.text("r"))
    state = event(Recipes.Table, state, Event.text("s"))
    assert Table.selected_rows(state.table) == [%{id: 2, name: "Bea updated"}]
    assert Frame.row_text(Recipes.Table.view(state), 3) =~ "Bea updated"

    state = event(Recipes.Table, state, Event.text("h"))
    refute Enum.any?(Table.display_rows(state.table), &(&1.id == 2))
    assert Frame.row_text(Recipes.Table.view(state), 7) =~ "Selected IDs: [2]"
    state = event(Recipes.Table, state, Event.text("h"))
    assert Enum.any?(Table.display_rows(state.table), &(&1.id == 2))
  end

  test "stream commands map one outer result and report bounded data loss" do
    state = Recipes.Stream.init(dimensions: {60, 8})

    {loading, [%Command{kind: :async, value: {function, mapper}}]} =
      Recipes.Stream.update(:load, state)

    state = Recipes.Stream.update(mapper.({:ok, function.()}), loading)
    assert state.stream.items == ["beta", "gamma", "delta"]
    assert state.stream.dropped_count == 1
    assert Frame.row_text(Recipes.Stream.view(state), 7) =~ "Accepted: 4 Dropped: 1"

    state = event(Recipes.Stream, state, Event.text(" "))
    state = Recipes.Stream.update({:loaded, {:ok, ["hidden"]}}, state)
    assert state.stream.items == ["beta", "gamma", "delta"]
    assert Frame.row_text(Recipes.Stream.view(state), 7) =~ "Rejected: 1"
  end

  test "a failed stream load retains data and permits a retry" do
    state = Recipes.Stream.init(dimensions: {60, 8})
    state = Recipes.Stream.update({:loaded, {:ok, ["kept"]}}, state)
    state = Recipes.Stream.update({:loaded, {:error, :unavailable}}, state)
    assert Frame.row_text(Recipes.Stream.view(state), 2) =~ "kept"
    assert Frame.row_text(Recipes.Stream.view(state), 7) =~ "Load failed"
    assert {%{loading: true}, [%Command{kind: :async}]} = Recipes.Stream.update(:load, state)
  end

  test "each recipe resizes to one bounded frame and returns shutdown data" do
    for app <- [Recipes.InputFocus, Recipes.Form, Recipes.Table, Recipes.Stream] do
      state = app.init(dimensions: {60, 8})
      state = event(app, state, Event.resize(3, 1))
      frame = app.view(state)
      assert {frame.width, frame.height} == {3, 1}
      assert {:ok, _frame} = Zoi.parse(Frame.schema(), frame)
      assert {^state, [%Command{kind: :shutdown, value: :normal}]} = app.update(:quit, state)
    end
  end

  defp event(app, state, event) do
    {:msg, message} = app.event_to_msg(event, state)

    case app.update(message, state) do
      {next, _commands} -> next
      next -> next
    end
  end
end
