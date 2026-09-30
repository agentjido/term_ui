defmodule TermUI.Widget.Toast do
  @moduledoc "A pure dismissible notification and bounded toast collection."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Style}
  alias TermUI.Widget.Helpers

  @type toast_type :: :info | :success | :warning | :error
  @type t :: %__MODULE__{
          id: term(),
          message: String.t(),
          type: toast_type(),
          visible: boolean(),
          duration: pos_integer() | :infinity,
          elapsed: non_neg_integer(),
          expiry_token: reference() | nil
        }
  defstruct id: nil,
            message: "",
            type: :info,
            visible: true,
            duration: 5_000,
            elapsed: 0,
            expiry_token: nil

  @impl true
  def init(opts),
    do: %__MODULE__{
      id: Keyword.get(opts, :id, make_ref()),
      message: opts |> Keyword.get(:message, "") |> to_string(),
      type: Keyword.get(opts, :type, :info),
      duration: normalize_duration(Keyword.get(opts, :duration, 5_000)),
      expiry_token: make_ref()
    }

  @impl true
  def update(%Event.Key{key: :escape}, state),
    do: {%{state | visible: false}, [{:dismissed, state.id}]}

  def update(%Event.Mouse{action: :release, button: :left}, state),
    do: {%{state | visible: false}, [{:dismissed, state.id}]}

  def update(_event, state), do: {state, []}

  @impl true
  def view(%{visible: false}, dimensions), do: Helpers.frame([], dimensions)

  def view(state, dimensions) do
    {icon, color} =
      case state.type do
        :success -> {"✓", :green}
        :warning -> {"!", :yellow}
        :error -> {"×", :red}
        :info -> {"i", :cyan}
      end

    rows =
      Helpers.border(
        [[{icon <> " ", Style.new(fg: color, attrs: [:bold])}, state.message]],
        dimensions
      )

    Helpers.frame(rows, dimensions)
  end

  @doc "Advances the toast clock and hides an expired toast."
  @spec tick(t(), non_neg_integer()) :: t()
  def tick(%{duration: :infinity} = state, _elapsed), do: state

  def tick(state, elapsed) do
    elapsed = state.elapsed + max(elapsed, 0)
    %{state | elapsed: elapsed, visible: elapsed < state.duration}
  end

  defp normalize_duration(:infinity), do: :infinity
  defp normalize_duration(duration) when is_integer(duration) and duration > 0, do: duration
  defp normalize_duration(_invalid), do: 5_000

  defmodule Manager do
    @moduledoc """
    A pure bounded toast collection with explicit expiration commands.

    Each manager has an ID so an application can keep independent toast areas.
    Timer messages include the manager ID and a unique toast expiry token.
    This makes late messages safe after dismissal, replacement, or limit
    removal.
    """

    alias TermUI.Command
    alias TermUI.Widget.Toast

    @type expiry_message ::
            {:term_ui_toast_expire, manager_id :: term(), toast_id :: term(), reference()}
    @type t :: %__MODULE__{id: term(), toasts: [Toast.t()], limit: pos_integer()}
    defstruct id: nil,
              toasts: [],
              limit: 5

    @doc "Creates an empty bounded toast manager."
    @spec new(keyword()) :: t()
    def new(opts \\ []),
      do: %__MODULE__{
        id: Keyword.get(opts, :id, make_ref()),
        limit: positive_limit(Keyword.get(opts, :limit, 5))
      }

    @doc "Adds one toast and removes entries beyond the manager limit."
    @spec add(t(), iodata(), Toast.toast_type(), keyword()) :: t()
    def add(manager, message, type \\ :info, opts \\ []) do
      {manager, _toast} = put(manager, message, type, opts, :add)
      manager
    end

    @doc "Adds one toast and returns its explicit expiration timer command."
    @spec add_with_timer(t(), iodata(), Toast.toast_type(), keyword()) ::
            {t(), [Command.timer_command()]}
    def add_with_timer(manager, message, type \\ :info, opts \\ []) do
      {manager, toast} = put(manager, message, type, opts, :add)
      {manager, timer_commands(manager, toast)}
    end

    @doc "Replaces a toast by ID, or adds it when the ID does not exist."
    @spec replace(t(), term(), iodata(), Toast.toast_type(), keyword()) :: t()
    def replace(manager, id, message, type \\ :info, opts \\ []) do
      {manager, _toast} = put(manager, message, type, Keyword.put(opts, :id, id), :replace)
      manager
    end

    @doc "Replaces a toast and returns a new explicit expiration timer command."
    @spec replace_with_timer(t(), term(), iodata(), Toast.toast_type(), keyword()) ::
            {t(), [Command.timer_command()]}
    def replace_with_timer(manager, id, message, type \\ :info, opts \\ []) do
      {manager, toast} = put(manager, message, type, Keyword.put(opts, :id, id), :replace)
      {manager, timer_commands(manager, toast)}
    end

    @doc "Removes a toast by ID. Missing IDs are safe."
    @spec dismiss(t(), term()) :: t()
    def dismiss(manager, id),
      do: %{manager | toasts: Enum.reject(manager.toasts, &(&1.id == id))}

    @doc "Applies one expiration timer message when its area and token still match."
    @spec expire(t(), term()) :: t()
    def expire(
          %{id: manager_id} = manager,
          {:term_ui_toast_expire, manager_id, toast_id, expiry_token}
        ) do
      %{
        manager
        | toasts:
            Enum.reject(
              manager.toasts,
              &(&1.id == toast_id and &1.expiry_token == expiry_token)
            )
      }
    end

    def expire(manager, _late_or_foreign_message), do: manager

    @doc "Changes the maximum count and immediately removes older entries."
    @spec set_limit(t(), pos_integer()) :: t()
    def set_limit(manager, limit) do
      limit = positive_limit(limit)
      %{manager | limit: limit, toasts: Enum.take(manager.toasts, limit)}
    end

    @doc "Advances all toast clocks and removes expired entries."
    @spec tick(t(), non_neg_integer()) :: t()
    def tick(manager, elapsed),
      do: %{
        manager
        | toasts:
            manager.toasts
            |> Enum.map(&Toast.tick(&1, elapsed))
            |> Enum.filter(& &1.visible)
      }

    defp put(manager, message, type, opts, mode) do
      toast = Toast.init(Keyword.merge(opts, message: message, type: type))

      toasts =
        case {mode, Enum.find_index(manager.toasts, &(&1.id == toast.id))} do
          {:replace, index} when is_integer(index) ->
            List.replace_at(manager.toasts, index, toast)

          _add_or_missing ->
            [toast | Enum.reject(manager.toasts, &(&1.id == toast.id))]
        end

      {%{manager | toasts: Enum.take(toasts, manager.limit)}, toast}
    end

    defp timer_commands(_manager, %{duration: :infinity}), do: []

    defp timer_commands(manager, toast) do
      message = {:term_ui_toast_expire, manager.id, toast.id, toast.expiry_token}
      [Command.timer(toast.duration, message)]
    end

    defp positive_limit(limit) when is_integer(limit) and limit > 0, do: limit
    defp positive_limit(_invalid), do: 5
  end
end
