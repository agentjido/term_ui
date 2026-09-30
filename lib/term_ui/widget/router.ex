defmodule TermUI.Widget.Router do
  @moduledoc """
  Pure routing between a parent application and an embedded widget.

  A route identifies one child, locates its state in the parent model, and
  maps the child's messages to parent messages. The parent keeps all state.
  A route does not start a process and does not use a registry.

  Use the route ID with `focused?/2`, `region/6`, and `mouse/4`. Two routes can
  use the same widget module because their IDs and state paths are independent.
  """

  alias TermUI.{Event, Focus, Mouse}

  @type t :: %__MODULE__{
          id: term(),
          module: module(),
          path: [term()],
          map_message: (term(), term() -> term())
        }

  @schema Zoi.struct(__MODULE__, %{
            id: Zoi.any(),
            module: Zoi.atom(),
            path: Zoi.array(Zoi.any()),
            map_message: Zoi.function(arity: 2)
          })

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for widget routes."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a child route with a non-empty parent-state path."
  @spec new(term(), module(), [term()], keyword()) :: t()
  def new(id, module, path, opts \\ []) when is_atom(module) and is_list(path) do
    if path == [] do
      raise ArgumentError, "widget route path must not be empty"
    end

    map_message = Keyword.get(opts, :map_message, &default_message/2)

    @schema
    |> Zoi.parse!(%__MODULE__{
      id: id,
      module: module,
      path: path,
      map_message: map_message
    })
  end

  @doc "Updates the child and stores its new state in the parent model."
  @spec update(t(), Event.t(), term()) :: {term(), [term()]}
  def update(%__MODULE__{} = route, event, parent) do
    child = fetch_child!(parent, route.path)
    {child, messages} = route.module.update(event, child)
    {store_child!(parent, route.path, child), map_messages(route, messages)}
  end

  @doc "Applies a mouse route only when its ID belongs to this child."
  @spec mouse(
          t(),
          {:ok, term(), Event.Mouse.t()} | :none,
          term(),
          TermUI.Widget.dimensions()
        ) :: {term(), [term()]}
  def mouse(%__MODULE__{id: id} = route, {:ok, id, event}, parent, dimensions) do
    child = fetch_child!(parent, route.path)
    {child, messages} = TermUI.Widget.mouse(route.module, event, child, dimensions)
    {store_child!(parent, route.path, child), map_messages(route, messages)}
  end

  def mouse(%__MODULE__{}, _route_result, parent, _dimensions), do: {parent, []}

  @doc "Returns true when this child owns active focus."
  @spec focused?(t(), Focus.t()) :: boolean()
  def focused?(%__MODULE__{id: id}, %Focus{} = focus), do: Focus.focused?(focus, id)

  @doc "Creates a mouse region with this child's ID."
  @spec region(
          t(),
          non_neg_integer(),
          non_neg_integer(),
          pos_integer(),
          pos_integer(),
          keyword()
        ) :: Mouse.Region.t()
  def region(%__MODULE__{id: id}, x, y, width, height, opts \\ []),
    do: Mouse.region(id, x, y, width, height, opts)

  defp map_messages(route, messages) when is_list(messages),
    do: Enum.map(messages, &route.map_message.(route.id, &1))

  defp fetch_child!(model, [key]), do: Map.fetch!(model, key)
  defp fetch_child!(model, [key | path]), do: model |> Map.fetch!(key) |> fetch_child!(path)

  defp store_child!(model, [key], child), do: Map.put(model, key, child)

  defp store_child!(model, [key | path], child) do
    Map.put(model, key, model |> Map.fetch!(key) |> store_child!(path, child))
  end

  defp default_message(id, message), do: {:widget, id, message}
end
