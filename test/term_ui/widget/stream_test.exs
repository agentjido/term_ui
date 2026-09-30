defmodule TermUI.Widget.StreamTest do
  use ExUnit.Case, async: true

  alias TermUI.Widget.Stream

  test "batch push keeps drop-oldest bounds and lifetime counters" do
    state = Stream.init(items: [1, 2, 3], limit: 2)

    assert Stream.stats(state) == %{
             buffered: 2,
             limit: 2,
             received: 3,
             dropped: 1,
             rejected: 0,
             overflow: :drop_oldest,
             paused: false
           }

    assert {state, %{accepted: 2, dropped: 2, rejected: 0}} =
             Stream.offer_many(state, [4, 5])

    assert state.items == [4, 5]
    assert state.received_count == 5
    assert state.dropped_count == 3
  end

  test "drop-newest keeps buffered items and rejects only the batch tail" do
    state = Stream.init(items: [1], limit: 3, overflow: :drop_newest)

    assert {state, %{accepted: 2, dropped: 1, rejected: 0}} =
             Stream.offer_many(state, [2, 3, 4])

    assert state.items == [1, 2, 3]
    assert Stream.stats(state).dropped == 1
  end

  test "reject policy accepts a complete batch or leaves state data unchanged" do
    state = Stream.init(items: [1], limit: 2, overflow: :reject)

    assert {state, %{accepted: 0, dropped: 0, rejected: 2}} =
             Stream.offer_many(state, [2, 3])

    assert state.items == [1]
    assert state.rejected_count == 2

    assert Stream.push_many(state, [2]).items == [1, 2]
  end

  test "pause preserves compatibility and maintenance functions stay pure" do
    state = Stream.init(items: [1], overflow: :drop_newest)
    paused = %{state | paused: true}

    assert Stream.push_many(paused, [2, 3]) == paused

    assert {^paused, %{accepted: 0, dropped: 0, rejected: 2}} =
             Stream.offer_many(paused, [2, 3])

    assert paused |> Stream.clear() |> Map.fetch!(:items) == []

    reset = paused |> Stream.set_overflow(:reject) |> Stream.reset_stats()
    assert reset.overflow == :reject
    assert reset.received_count == 0
    assert reset.dropped_count == 0
    assert reset.rejected_count == 0

    assert_raise ArgumentError, fn -> Stream.set_overflow(state, :unbounded) end
  end
end
