defmodule TermUI.Widget.LogViewer do
  @moduledoc "A pure bounded and scrollable log viewer."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Frame, Style}
  alias TermUI.Widget.Helpers

  @type entry :: %{
          required(:message) => String.t(),
          optional(:level) => atom(),
          optional(:timestamp) => term()
        }
  @type t :: %__MODULE__{
          entries: [entry()],
          limit: pos_integer(),
          offset: non_neg_integer(),
          follow: boolean(),
          filter: String.t() | nil,
          page_size: pos_integer()
        }
  defstruct entries: [],
            limit: 10_000,
            offset: 0,
            follow: true,
            filter: nil,
            page_size: 20

  @impl true
  def init(opts) do
    %__MODULE__{
      entries:
        opts
        |> Keyword.get(:entries, [])
        |> Enum.map(&normalize/1)
        |> Enum.take(-max(Keyword.get(opts, :limit, 10_000), 1)),
      limit: max(Keyword.get(opts, :limit, 10_000), 1),
      follow: Keyword.get(opts, :follow, true),
      filter: Keyword.get(opts, :filter),
      page_size: max(Keyword.get(opts, :page_size, 20), 1)
    }
  end

  @impl true
  def update(%Event.Key{key: :up}, state), do: scroll(state, -1)
  def update(%Event.Key{key: :down}, state), do: scroll(state, 1)
  def update(%Event.Key{key: :page_up}, state), do: scroll(state, -state.page_size)
  def update(%Event.Key{key: :page_down}, state), do: scroll(state, state.page_size)
  def update(%Event.Key{key: :home}, state), do: {%{state | offset: 0, follow: false}, []}

  def update(%Event.Key{key: :end}, state),
    do: {%{state | offset: max(length(filtered(state)) - state.page_size, 0), follow: true}, []}

  def update(%Event.Text{text: "f"}, state),
    do: {%{state | follow: not state.follow}, [{:follow, not state.follow}]}

  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, height} = dimensions) do
    entries = filtered(state)

    offset =
      if state.follow,
        do: max(length(entries) - height, 0),
        else: min(state.offset, max(length(entries) - height, 0))

    rows =
      entries
      |> Enum.slice(offset, height)
      |> Enum.flat_map(fn entry ->
        prefix = prefix(entry)
        style = level_style(Map.get(entry, :level, :info))
        Frame.wrap(prefix <> entry.message, width) |> Enum.map(&[{&1, style}])
      end)
      |> Enum.take(height)

    Helpers.frame(rows, dimensions)
  end

  @doc "Appends one entry and applies the configured bound."
  @spec append(t(), entry() | iodata()) :: t()
  def append(state, entry) do
    entries = Enum.take(state.entries ++ [normalize(entry)], -state.limit)

    %{
      state
      | entries: entries,
        offset:
          if(state.follow, do: max(length(entries) - state.page_size, 0), else: state.offset)
    }
  end

  @doc "Changes the case-insensitive text filter."
  @spec set_filter(t(), String.t() | nil) :: t()
  def set_filter(state, filter), do: %{state | filter: filter, offset: 0}

  defp scroll(state, delta) do
    offset = Helpers.scroll(state.offset, delta, length(filtered(state)), state.page_size)

    {%{
       state
       | offset: offset,
         follow: offset == Helpers.max_scroll(length(filtered(state)), state.page_size)
     }, [{:scrolled, offset}]}
  end

  defp filtered(%{filter: filter} = state) when filter in [nil, ""], do: state.entries

  defp filtered(state),
    do:
      Enum.filter(
        state.entries,
        &String.contains?(String.downcase(&1.message), String.downcase(state.filter))
      )

  defp normalize(%{message: message} = entry),
    do: entry |> Map.put(:message, to_string(message)) |> Map.put_new(:level, :info)

  defp normalize(message), do: %{message: IO.iodata_to_binary(message), level: :info}
  defp prefix(%{timestamp: timestamp}) when not is_nil(timestamp), do: "#{timestamp} "
  defp prefix(_entry), do: ""
  defp level_style(:debug), do: Style.new(fg: :bright_black)
  defp level_style(:warning), do: Style.new(fg: :yellow)
  defp level_style(:error), do: Style.new(fg: :red)
  defp level_style(_level), do: Style.new()
end
