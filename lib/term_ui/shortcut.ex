defmodule TermUI.Shortcut do
  @moduledoc """
  Keyboard shortcut registry and matching.

  Provides a system for registering keyboard shortcuts with actions,
  matching key events against registered shortcuts, and executing
  the associated actions.

  This registry is opt-in. `TermUI.Runtime` does not start it, register
  shortcuts, or route root events through it; an application must perform that
  integration explicitly.

  ## Usage

      # Create a registry
      {:ok, registry} = Shortcut.start_link()

      # Register shortcuts
      Shortcut.register(registry, %Shortcut{
        key: :q,
        modifiers: [:ctrl],
        action: {:message, :root, :quit},
        scope: :global,
        description: "Quit application"
      })

      # Match key event
      case Shortcut.match(registry, key_event, context) do
        {:ok, shortcut} -> Shortcut.execute(shortcut)
        :no_match -> :ignore
      end
  """

  use GenServer

  alias TermUI.Event

  # Dialyzer: Functions with unmatched return values in side-effect calls
  @dialyzer {:nowarn_function, match: 3, handle_cast: 2, handle_call: 3, check_sequence_match: 2}

  @type scope :: :global | {:mode, atom()} | {:component, atom()}

  @type action ::
          {:function, (-> any())}
          | {:message, atom(), term()}
          | {:command, term()}

  @type t :: %__MODULE__{
          key: atom() | String.t(),
          modifiers: [atom()],
          action: action(),
          scope: scope(),
          priority: integer(),
          description: String.t() | nil,
          sequence: [atom() | String.t()] | nil
        }

  defstruct [
    :key,
    :action,
    :description,
    :sequence,
    modifiers: [],
    scope: :global,
    priority: 0
  ]

  # --- Public API ---

  @doc """
  Starts the shortcut registry.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Registers a shortcut.
  """
  @spec register(GenServer.server(), t()) :: :ok
  def register(registry, %__MODULE__{} = shortcut) do
    GenServer.call(registry, {:register, shortcut})
  end

  @doc """
  Unregisters a shortcut by key and modifiers.
  """
  @spec unregister(GenServer.server(), atom() | String.t(), [atom()]) :: :ok
  def unregister(registry, key, modifiers \\ []) do
    GenServer.call(registry, {:unregister, key, modifiers})
  end

  @doc """
  Matches a key event against registered shortcuts.

  Returns `{:ok, shortcut}` if a match is found, or `:no_match`.
  The context determines which scopes are active.
  """
  @spec match(GenServer.server(), Event.Key.t(), map()) :: {:ok, t()} | :no_match
  def match(registry, %Event.Key{} = event, context \\ %{}) do
    GenServer.call(registry, {:match, event, context})
  end

  @doc """
  Executes a shortcut's action.

  Returns the result of the action execution.
  """
  @spec execute(t()) :: term()
  def execute(%__MODULE__{action: {:function, fun}}) when is_function(fun, 0) do
    fun.()
  end

  def execute(%__MODULE__{action: {:message, component_id, message}}) do
    {:send_message, component_id, message}
  end

  def execute(%__MODULE__{action: {:command, command}}) do
    {:execute_command, command}
  end

  @doc """
  Lists all registered shortcuts.
  """
  @spec list(GenServer.server()) :: [t()]
  def list(registry) do
    GenServer.call(registry, :list)
  end

  @doc """
  Lists shortcuts for a specific scope.
  """
  @spec list_for_scope(GenServer.server(), scope()) :: [t()]
  def list_for_scope(registry, scope) do
    GenServer.call(registry, {:list_for_scope, scope})
  end

  @doc """
  Formats a shortcut for display.

  ## Examples

      iex> Shortcut.format(%Shortcut{key: :s, modifiers: [:ctrl]})
      "Ctrl+S"

      iex> Shortcut.format(%Shortcut{key: :q, modifiers: [:ctrl, :shift]})
      "Ctrl+Shift+Q"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{key: key, modifiers: modifiers}) do
    parts =
      modifiers
      |> Enum.sort_by(&modifier_order/1)
      |> Enum.map(&format_modifier/1)

    key_str = format_key(key)
    Enum.join(parts ++ [key_str], "+")
  end

  @doc """
  Clears the partial sequence state.
  """
  @spec clear_sequence(GenServer.server()) :: :ok
  def clear_sequence(registry) do
    GenServer.cast(registry, :clear_sequence)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    state = %{
      shortcuts: [],
      sequence_state: nil,
      sequence_timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register, shortcut}, _from, state) do
    shortcuts = [shortcut | state.shortcuts]
    {:reply, :ok, %{state | shortcuts: shortcuts}}
  end

  @impl true
  def handle_call({:unregister, key, modifiers}, _from, state) do
    modifiers = Enum.sort(modifiers)

    shortcuts =
      Enum.reject(state.shortcuts, fn s ->
        s.key == key and Enum.sort(s.modifiers) == modifiers
      end)

    {:reply, :ok, %{state | shortcuts: shortcuts}}
  end

  @impl true
  def handle_call({:match, event, context}, _from, state) do
    {result, state} = do_match(event, context, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, state.shortcuts, state}
  end

  @impl true
  def handle_call({:list_for_scope, scope}, _from, state) do
    filtered = Enum.filter(state.shortcuts, fn s -> s.scope == scope end)
    {:reply, filtered, state}
  end

  @impl true
  def handle_cast(:clear_sequence, state) do
    if state.sequence_timer, do: Process.cancel_timer(state.sequence_timer)
    {:noreply, %{state | sequence_state: nil, sequence_timer: nil}}
  end

  @impl true
  def handle_info(:sequence_timeout, state) do
    {:noreply, %{state | sequence_state: nil, sequence_timer: nil}}
  end

  # --- Private Functions ---

  defp do_match(event, context, state) do
    # Check for sequence shortcuts first
    {sequence_match, state} = check_sequence_match(event, state)

    case sequence_match do
      {:ok, _} = result ->
        {result, state}

      :no_match ->
        # Check for regular shortcuts
        result = check_regular_match(event, context, state.shortcuts)
        {result, state}
    end
  end

  defp check_sequence_match(event, state) do
    # Build current sequence
    current_key = event.key
    current_seq = (state.sequence_state || []) ++ [current_key]

    # Find sequence shortcuts that match or could match
    sequence_shortcuts =
      Enum.filter(state.shortcuts, fn s ->
        s.sequence != nil and List.starts_with?(s.sequence, current_seq)
      end)

    cond do
      # Exact sequence match
      Enum.any?(sequence_shortcuts, fn s -> s.sequence == current_seq end) ->
        shortcut = Enum.find(sequence_shortcuts, fn s -> s.sequence == current_seq end)

        if state.sequence_timer, do: Process.cancel_timer(state.sequence_timer)
        state = %{state | sequence_state: nil, sequence_timer: nil}
        {{:ok, shortcut}, state}

      # Partial sequence match - wait for more keys
      sequence_shortcuts != [] ->
        if state.sequence_timer, do: Process.cancel_timer(state.sequence_timer)
        timer = Process.send_after(self(), :sequence_timeout, 1000)
        state = %{state | sequence_state: current_seq, sequence_timer: timer}
        {:no_match, state}

      # No sequence match
      true ->
        if state.sequence_timer, do: Process.cancel_timer(state.sequence_timer)
        state = %{state | sequence_state: nil, sequence_timer: nil}
        {:no_match, state}
    end
  end

  defp check_regular_match(event, context, shortcuts) do
    # Filter by key and modifiers
    matching =
      shortcuts
      |> Enum.filter(fn s ->
        s.sequence == nil and
          matches_key?(s, event) and
          matches_modifiers?(s, event) and
          scope_active?(s.scope, context)
      end)
      |> Enum.sort_by(fn s -> -s.priority end)

    case matching do
      [shortcut | _] -> {:ok, shortcut}
      [] -> :no_match
    end
  end

  defp matches_key?(shortcut, event) do
    shortcut.key == event.key or shortcut.key == :any
  end

  defp matches_modifiers?(shortcut, event) do
    required = MapSet.new(shortcut.modifiers)
    actual = MapSet.new(event.modifiers)
    MapSet.equal?(required, actual)
  end

  defp scope_active?(:global, _context), do: true

  defp scope_active?({:mode, mode}, context) do
    Map.get(context, :mode) == mode
  end

  defp scope_active?({:component, component_id}, context) do
    Map.get(context, :focused_component) == component_id
  end

  defp modifier_order(:ctrl), do: 0
  defp modifier_order(:alt), do: 1
  defp modifier_order(:shift), do: 2
  defp modifier_order(:meta), do: 3
  defp modifier_order(_), do: 4

  defp format_modifier(:ctrl), do: "Ctrl"
  defp format_modifier(:alt), do: "Alt"
  defp format_modifier(:shift), do: "Shift"
  defp format_modifier(:meta), do: "Meta"
  defp format_modifier(other), do: to_string(other)

  defp format_key(key) when is_atom(key) do
    key
    |> to_string()
    |> String.upcase()
  end

  defp format_key(key) when is_binary(key) do
    String.upcase(key)
  end
end
