defmodule TermUI.Widget.Stream do
  @moduledoc """
  A pure bounded stream view.

  The parent supplies items with `push/2` or `push_many/2`. The overflow policy
  is part of widget state. Counters make data loss visible without adding a
  widget process.
  """

  @behaviour TermUI.Widget

  alias TermUI.{Event, Frame, Style}
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          items: [term()],
          limit: pos_integer(),
          paused: boolean(),
          offset: non_neg_integer(),
          page_size: pos_integer(),
          formatter: (term() -> iodata()),
          overflow: overflow(),
          received_count: non_neg_integer(),
          dropped_count: non_neg_integer(),
          rejected_count: non_neg_integer()
        }
  @type overflow :: :drop_oldest | :drop_newest | :reject
  @type offer_result :: %{
          accepted: non_neg_integer(),
          dropped: non_neg_integer(),
          rejected: non_neg_integer()
        }

  @overflows [:drop_oldest, :drop_newest, :reject]

  defstruct items: [],
            limit: 1_000,
            paused: false,
            offset: 0,
            page_size: 20,
            formatter: &__MODULE__.default_format/1,
            overflow: :drop_oldest,
            received_count: 0,
            dropped_count: 0,
            rejected_count: 0

  @impl true
  def init(opts) do
    limit = max(Keyword.get(opts, :limit, 1_000), 1)
    items = Keyword.get(opts, :items, [])

    %__MODULE__{
      items: Enum.take(items, -limit),
      limit: limit,
      page_size: max(Keyword.get(opts, :page_size, 20), 1),
      formatter: Keyword.get(opts, :formatter, &__MODULE__.default_format/1),
      overflow: overflow!(Keyword.get(opts, :overflow, :drop_oldest)),
      received_count: length(items),
      dropped_count: max(length(items) - limit, 0)
    }
  end

  @impl true
  def update(%Event.Key{key: :space}, state),
    do: {%{state | paused: not state.paused}, [{:paused, not state.paused}]}

  def update(%Event.Text{text: " "}, state),
    do: {%{state | paused: not state.paused}, [{:paused, not state.paused}]}

  def update(%Event.Key{key: :up}, state), do: scroll(state, -1)
  def update(%Event.Key{key: :down}, state), do: scroll(state, 1)
  def update(%Event.Key{key: :page_up}, state), do: scroll(state, -state.page_size)
  def update(%Event.Key{key: :page_down}, state), do: scroll(state, state.page_size)

  def update(%Event.Key{key: :end}, state),
    do: {%{state | offset: max(length(state.items) - state.page_size, 0)}, []}

  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, height} = dimensions) do
    status =
      if state.paused,
        do: [{" PAUSED ", Style.new(fg: :black, bg: :yellow, attrs: [:bold])}],
        else: [{" LIVE ", Style.new(fg: :black, bg: :green, attrs: [:bold])}]

    body_height = max(height - 1, 0)

    offset =
      if state.paused,
        do: min(state.offset, max(length(state.items) - body_height, 0)),
        else: max(length(state.items) - body_height, 0)

    rows =
      state.items
      |> Enum.slice(offset, body_height)
      |> Enum.flat_map(fn item ->
        item |> state.formatter.() |> IO.iodata_to_binary() |> Frame.wrap(width)
      end)
      |> Enum.take(body_height)

    Helpers.frame([status | rows], dimensions)
  end

  @doc "Appends one stream item unless the view is paused."
  @spec push(t(), term()) :: t()
  def push(%{paused: true} = state, _item), do: state
  def push(state, item), do: state |> offer_many([item]) |> elem(0)

  @doc "Appends a batch of stream items unless the view is paused."
  @spec push_many(t(), Enumerable.t()) :: t()
  def push_many(%{paused: true} = state, _items), do: state
  def push_many(state, items), do: state |> offer_many(items) |> elem(0)

  @doc "Offers a batch and returns per-call acceptance and data-loss counts."
  @spec offer_many(t(), Enumerable.t()) :: {t(), offer_result()}
  def offer_many(%{paused: true} = state, items) do
    count = items |> Enum.to_list() |> length()
    {state, %{accepted: 0, dropped: 0, rejected: count}}
  end

  def offer_many(state, items) do
    items = Enum.to_list(items)
    offered = length(items)
    {kept, accepted, dropped, rejected} = apply_overflow(state, items)

    next = %{
      state
      | items: kept,
        received_count: state.received_count + offered,
        dropped_count: state.dropped_count + dropped,
        rejected_count: state.rejected_count + rejected
    }

    {next, %{accepted: accepted, dropped: dropped, rejected: rejected}}
  end

  @doc "Removes all items while keeping lifetime counters."
  @spec clear(t()) :: t()
  def clear(state), do: %{state | items: [], offset: 0}

  @doc "Resets the lifetime stream counters."
  @spec reset_stats(t()) :: t()
  def reset_stats(state),
    do: %{state | received_count: 0, dropped_count: 0, rejected_count: 0}

  @doc "Changes the overflow policy."
  @spec set_overflow(t(), overflow()) :: t()
  def set_overflow(state, overflow), do: %{state | overflow: overflow!(overflow)}

  @doc "Returns bounded-buffer and lifetime counter data."
  @spec stats(t()) :: map()
  def stats(state) do
    %{
      buffered: length(state.items),
      limit: state.limit,
      received: state.received_count,
      dropped: state.dropped_count,
      rejected: state.rejected_count,
      overflow: state.overflow,
      paused: state.paused
    }
  end

  @doc false
  def default_format(item), do: to_string(item)

  defp scroll(state, delta) do
    offset = Helpers.scroll(state.offset, delta, length(state.items), state.page_size)
    {%{state | offset: offset, paused: true}, [{:scrolled, offset}]}
  end

  defp apply_overflow(%{overflow: :drop_oldest} = state, items) do
    combined = state.items ++ items
    dropped = max(length(combined) - state.limit, 0)
    {Enum.take(combined, -state.limit), length(items), dropped, 0}
  end

  defp apply_overflow(%{overflow: :drop_newest} = state, items) do
    accepted_items = Enum.take(items, max(state.limit - length(state.items), 0))
    dropped = length(items) - length(accepted_items)
    {state.items ++ accepted_items, length(accepted_items), dropped, 0}
  end

  defp apply_overflow(%{overflow: :reject} = state, items) do
    if length(state.items) + length(items) <= state.limit,
      do: {state.items ++ items, length(items), 0, 0},
      else: {state.items, 0, 0, length(items)}
  end

  defp overflow!(overflow) when overflow in @overflows, do: overflow

  defp overflow!(overflow) do
    raise ArgumentError,
          "stream overflow must be :drop_oldest, :drop_newest, or :reject, got: #{inspect(overflow)}"
  end
end
