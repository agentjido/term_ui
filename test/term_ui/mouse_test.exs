defmodule TermUI.MouseTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Mouse}
  alias TermUI.Mouse.Tracker

  test "routes to the top region and creates local coordinates" do
    regions = [
      Mouse.region(:base, 0, 0, 20, 10),
      Mouse.region(:dialog, 5, 2, 8, 4, z_index: 10)
    ]

    event = Event.mouse(:press, :left, 7, 4)

    assert {:ok, :dialog, %Event.Mouse{x: 2, y: 2}} = Mouse.route(regions, event)
    assert {:ok, region, {2, 2}} = Mouse.hit_test(regions, 7, 4)
    assert region.id == :dialog
  end

  test "equal z-index uses the last composed region" do
    regions = [Mouse.region(:first, 0, 0, 5, 5), Mouse.region(:second, 0, 0, 5, 5)]

    assert {:ok, :second, _event} =
             Mouse.route(regions, Event.mouse(:release, :left, 1, 1))
  end

  test "route all preserves front-to-back order" do
    regions = [
      Mouse.region(:base, 0, 0, 10, 10),
      Mouse.region(:overlay, 0, 0, 10, 10, z_index: 1)
    ]

    assert [{:overlay, %Event.Mouse{}}, {:base, %Event.Mouse{}}] =
             Mouse.route_all(regions, Event.mouse(:move, nil, 2, 3))
  end

  test "tracker reports drag deltas and resets on release" do
    tracker = Tracker.new(drag_threshold: 1)

    {tracker, []} = Tracker.update(tracker, Event.mouse(:press, :left, 2, 3))

    {tracker, events} = Tracker.update(tracker, Event.mouse(:drag, :left, 4, 6))

    assert events == [
             {:drag_start, :left, 2, 3},
             {:drag, :left, 4, 6, 2, 3}
           ]

    assert Tracker.dragging?(tracker)

    {tracker, [{:drag_end, :left, 4, 6}]} =
      Tracker.update(tracker, Event.mouse(:release, :left, 4, 6))

    refute Tracker.dragging?(tracker)
  end

  test "tracker reports hover transitions without a process" do
    tracker = Tracker.new()
    {tracker, [{:hover_enter, :one}]} = Tracker.hover(tracker, :one)

    {tracker, [{:hover_leave, :one}, {:hover_enter, :two}]} =
      Tracker.hover(tracker, :two)

    assert Tracker.hovered(tracker) == :two
  end

  test "tracker handles movement, thresholds, fallback actions, and reset" do
    tracker = Tracker.new(drag_threshold: 2)
    {tracker, []} = Tracker.update(tracker, Event.mouse(:move, nil, 1, 1))
    refute Tracker.dragging?(tracker)
    {tracker, []} = Tracker.update(tracker, Event.mouse(:press, :left, 1, 1))
    {tracker, []} = Tracker.update(tracker, Event.mouse(:drag, :left, 2, 1))
    refute Tracker.dragging?(tracker)

    {tracker, [{:drag_start, :left, 1, 1}, {:drag, :left, 3, 1, 2, 0}]} =
      Tracker.update(tracker, Event.mouse(:drag, nil, 3, 1))

    assert {tracker, [{:drag, :left, 4, 3, 1, 2}]} =
             Tracker.update(tracker, Event.mouse(:move, nil, 4, 3))

    assert {^tracker, []} = Tracker.update(tracker, Event.mouse(:scroll_up, nil, 0, 0))
    reset = Tracker.reset_drag(tracker)
    assert reset.button_down == nil
    assert reset.last_position == nil
    refute reset.dragging
  end

  test "tracker release, repeated hover, and hover leave are no-ops or transitions" do
    tracker = Tracker.new()

    assert {released, []} = Tracker.update(tracker, Event.mouse(:release, :left, 2, 3))
    assert released.last_position == {2, 3}
    assert {tracker, [{:hover_enter, :target}]} = Tracker.hover(tracker, :target)
    assert {^tracker, []} = Tracker.hover(tracker, :target)
    assert {left, [{:hover_leave, :target}]} = Tracker.hover(tracker, nil)
    assert Tracker.hovered(left) == nil
  end

  test "regions transform, overlap, clip, and reject outside points" do
    region = Mouse.region(:one, 2, 3, 4, 5, metadata: %{role: :button})
    touching = Mouse.region(:touching, 6, 3, 2, 2)
    overlapping = Mouse.region(:overlap, 5, 6, 2, 2)

    assert region.metadata.role == :button
    assert Mouse.to_global(region, 1, 2) == {3, 5}
    assert Mouse.to_local(region, 3, 5) == {1, 2}
    assert Mouse.contains?(region, 2, 3)
    refute Mouse.contains?(region, 6, 3)
    refute Mouse.overlap?(region, touching)
    assert Mouse.overlap?(region, overlapping)
    assert Mouse.clip(region, -10, 99) == {2, 7}
    assert Mouse.hit_test([region], 0, 0) == :none
    assert Mouse.route([region], Event.mouse(:move, nil, 0, 0)) == :none
  end

  test "topmost routing preserves a higher z-index over a later lower region" do
    regions = [
      Mouse.region(:high, 0, 0, 2, 2, z_index: 5),
      Mouse.region(:outside, 5, 5, 2, 2, z_index: 10),
      Mouse.region(:low, 0, 0, 2, 2, z_index: 1)
    ]

    assert {:ok, :high, _event} = Mouse.route(regions, Event.mouse(:move, nil, 1, 1))
  end
end
