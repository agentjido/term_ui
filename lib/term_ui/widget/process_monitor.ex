defmodule TermUI.Widget.ProcessMonitor do
  @moduledoc "A pure process-snapshot table. It does not inspect processes itself."

  @behaviour TermUI.Widget

  alias TermUI.Event
  alias TermUI.Widget.Table
  alias TermUI.Widget.Table.Column

  @type snapshot :: %{
          required(:pid) => term(),
          optional(:name) => term(),
          optional(:memory) => non_neg_integer(),
          optional(:reductions) => non_neg_integer(),
          optional(:message_queue_len) => non_neg_integer()
        }
  @type t :: %__MODULE__{
          snapshots: [snapshot()],
          table: Table.t(),
          sort: atom(),
          descending: boolean()
        }
  defstruct snapshots: [],
            table: %Table{},
            sort: :memory,
            descending: true

  @impl true
  def init(opts) do
    snapshots = Keyword.get(opts, :snapshots, [])
    sort = Keyword.get(opts, :sort, :memory)
    descending = Keyword.get(opts, :descending, true)

    %__MODULE__{
      snapshots: snapshots,
      sort: sort,
      descending: descending,
      table: table(sorted(snapshots, sort, descending))
    }
  end

  @impl true
  def update(%Event.Text{text: "r"}, state), do: {state, [:refresh_requested]}
  def update(%Event.Text{text: "m"}, state), do: sort_by(state, :memory)
  def update(%Event.Text{text: "q"}, state), do: sort_by(state, :message_queue_len)
  def update(%Event.Text{text: "c"}, state), do: sort_by(state, :reductions)

  def update(event, state) do
    {table, messages} = Table.update(event, state.table)
    {%{state | table: table}, messages}
  end

  @impl true
  def mouse(event, state, dimensions) do
    {table, messages} = Table.mouse(event, state.table, dimensions)
    {%{state | table: table}, messages}
  end

  @impl true
  def view(state, dimensions), do: Table.view(state.table, dimensions)

  @doc "Replaces process snapshots supplied by the parent."
  @spec set_snapshots(t(), [snapshot()]) :: t()
  def set_snapshots(state, snapshots),
    do: %{
      state
      | snapshots: snapshots,
        table: state.table |> Table.set_rows(sorted(snapshots, state.sort, state.descending))
    }

  defp sort_by(state, key) do
    descending = if state.sort == key, do: not state.descending, else: true

    state = %{
      state
      | sort: key,
        descending: descending,
        table: Table.set_rows(state.table, sorted(state.snapshots, key, descending))
    }

    {state, [{:sorted, key, descending}]}
  end

  defp sorted(snapshots, key, true), do: Enum.sort_by(snapshots, &Map.get(&1, key, 0), :desc)
  defp sorted(snapshots, key, false), do: Enum.sort_by(snapshots, &Map.get(&1, key, 0), :asc)

  defp table(rows) do
    Table.init(
      columns: [
        Column.new(:pid, "PID", width: 16),
        Column.new(:name, "Name"),
        Column.new(:memory, "Memory", align: :right),
        Column.new(:reductions, "Reds", align: :right),
        Column.new(:message_queue_len, "Queue", align: :right)
      ],
      rows: rows
    )
  end
end
