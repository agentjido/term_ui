defmodule TermUI.Stream.ProducerAdapterTest do
  use ExUnit.Case, async: true

  alias TermUI.Stream.ProducerAdapter

  test "one acknowledged batch bounds the consumer mailbox" do
    assert {:ok, adapter} =
             ProducerAdapter.start_link(consumer: self(), limit: 4, batch_size: 2)

    assert :ok = ProducerAdapter.push_many(adapter, [1, 2])
    assert_receive {:term_ui_stream, ^adapter, first_ref, [1, 2]}

    assert :ok = ProducerAdapter.push_many(adapter, [3, 4, 5, 6])
    refute_receive {:term_ui_stream, ^adapter, _reference, _items}

    assert ProducerAdapter.stats(adapter) == %{
             buffered: 2,
             in_flight: 2,
             limit: 4,
             batch_size: 2,
             overflow: :drop_oldest,
             paused: false,
             received: 6,
             dropped: 2,
             rejected: 0
           }

    assert {:error, :unknown_batch} = ProducerAdapter.ack(adapter, make_ref())
    assert :ok = ProducerAdapter.ack(adapter, first_ref)
    assert_receive {:term_ui_stream, ^adapter, second_ref, [5, 6]}
    assert :ok = ProducerAdapter.ack(adapter, second_ref)
  end

  test "pause and drop-newest keep the earliest bounded items" do
    assert {:ok, adapter} =
             ProducerAdapter.start_link(
               consumer: self(),
               limit: 2,
               batch_size: 2,
               overflow: :drop_newest
             )

    assert :ok = ProducerAdapter.pause(adapter)
    assert :ok = ProducerAdapter.push_many(adapter, [1, 2, 3, 4])
    assert ProducerAdapter.stats(adapter).dropped == 2
    refute_receive {:term_ui_stream, ^adapter, _reference, _items}

    assert :ok = ProducerAdapter.resume(adapter)
    assert_receive {:term_ui_stream, ^adapter, reference, [1, 2]}
    assert :ok = ProducerAdapter.ack(adapter, reference)
  end

  test "reject policy reports a full buffer without accepting part of a batch" do
    assert {:ok, adapter} =
             ProducerAdapter.start_link(consumer: self(), limit: 2, overflow: :reject)

    assert :ok = ProducerAdapter.pause(adapter)
    assert {:error, :buffer_full} = ProducerAdapter.push_many(adapter, [1, 2, 3])
    assert %{buffered: 0, rejected: 3, received: 3} = ProducerAdapter.stats(adapter)
  end

  test "producer failure becomes application data" do
    assert {:ok, adapter} = ProducerAdapter.start_link(consumer: self(), tag: :assistant_tokens)
    producer = spawn(fn -> Process.sleep(:infinity) end)

    assert :ok = ProducerAdapter.monitor_producer(adapter, producer)
    Process.exit(producer, :source_failed)

    assert_receive {:assistant_tokens, ^adapter, {:producer_down, ^producer, :source_failed}}
  end

  test "validates bounded options" do
    assert_raise ArgumentError, fn -> ProducerAdapter.start_link(limit: 0) end
    assert_raise ArgumentError, fn -> ProducerAdapter.start_link(batch_size: 0) end
    assert_raise ArgumentError, fn -> ProducerAdapter.start_link(overflow: :unbounded) end
    assert_raise ArgumentError, fn -> ProducerAdapter.start_link(consumer: :registered_name) end
    assert_raise ArgumentError, fn -> ProducerAdapter.start_link(tag: {:stream, :tokens}) end
  end
end
