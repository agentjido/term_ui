defmodule TermUI.Mouse.Region do
  @moduledoc "A zero-based screen region for pure mouse routing."

  @type t :: %__MODULE__{
          id: term(),
          x: non_neg_integer(),
          y: non_neg_integer(),
          width: pos_integer(),
          height: pos_integer(),
          z_index: integer(),
          metadata: map()
        }

  @schema Zoi.struct(__MODULE__, %{
            id: Zoi.any(),
            x: Zoi.integer() |> Zoi.non_negative(),
            y: Zoi.integer() |> Zoi.non_negative(),
            width: Zoi.integer() |> Zoi.positive(),
            height: Zoi.integer() |> Zoi.positive(),
            z_index: Zoi.integer() |> Zoi.default(0),
            metadata: Zoi.map() |> Zoi.default(%{})
          })

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for mouse regions."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema
end

defmodule TermUI.Mouse.Tracker do
  @moduledoc "Pure drag and hover state for one Elm application."

  alias TermUI.Event

  @type t :: %__MODULE__{
          button_down: Event.Mouse.button(),
          press_position: {integer(), integer()} | nil,
          last_position: {integer(), integer()} | nil,
          dragging: boolean(),
          hovered: term(),
          drag_threshold: non_neg_integer()
        }

  defstruct button_down: nil,
            press_position: nil,
            last_position: nil,
            dragging: false,
            hovered: nil,
            drag_threshold: 1

  @doc "Creates tracker state. The drag threshold is measured in terminal cells."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{drag_threshold: max(Keyword.get(opts, :drag_threshold, 1), 0)}
  end

  @doc "Updates drag state and returns generated drag messages."
  @spec update(t(), Event.Mouse.t()) :: {t(), [term()]}
  def update(tracker, %Event.Mouse{action: :press, button: button, x: x, y: y}) do
    {%{
       tracker
       | button_down: button,
         press_position: {x, y},
         last_position: {x, y},
         dragging: false
     }, []}
  end

  def update(tracker, %Event.Mouse{action: :release, button: button, x: x, y: y}) do
    events = if tracker.dragging, do: [{:drag_end, button || tracker.button_down, x, y}], else: []

    {%{
       tracker
       | button_down: nil,
         press_position: nil,
         last_position: {x, y},
         dragging: false
     }, events}
  end

  def update(tracker, %Event.Mouse{action: action, button: button, x: x, y: y})
      when action in [:move, :drag] do
    update_motion(tracker, button || tracker.button_down, x, y)
  end

  def update(tracker, %Event.Mouse{}), do: {tracker, []}

  @doc "Updates the hovered region identifier."
  @spec hover(t(), term()) :: {t(), [term()]}
  def hover(%__MODULE__{hovered: target} = tracker, target), do: {tracker, []}

  def hover(%__MODULE__{hovered: nil} = tracker, target),
    do: {%{tracker | hovered: target}, [{:hover_enter, target}]}

  def hover(%__MODULE__{hovered: previous} = tracker, nil),
    do: {%{tracker | hovered: nil}, [{:hover_leave, previous}]}

  def hover(%__MODULE__{hovered: previous} = tracker, target),
    do: {%{tracker | hovered: target}, [{:hover_leave, previous}, {:hover_enter, target}]}

  @doc "Returns true during a drag."
  @spec dragging?(t()) :: boolean()
  def dragging?(%__MODULE__{dragging: dragging}), do: dragging

  @doc "Returns the hovered region identifier."
  @spec hovered(t()) :: term()
  def hovered(%__MODULE__{hovered: hovered}), do: hovered

  @doc "Clears drag state, such as after terminal focus is lost."
  @spec reset_drag(t()) :: t()
  def reset_drag(tracker),
    do: %{tracker | button_down: nil, press_position: nil, last_position: nil, dragging: false}

  defp update_motion(%{button_down: nil} = tracker, nil, x, y),
    do: {%{tracker | last_position: {x, y}}, []}

  defp update_motion(%{press_position: nil} = tracker, _button, x, y),
    do: {%{tracker | last_position: {x, y}}, []}

  defp update_motion(%{dragging: true} = tracker, button, x, y) do
    {dx, dy} = delta(tracker.last_position, {x, y})
    {%{tracker | last_position: {x, y}}, [{:drag, button, x, y, dx, dy}]}
  end

  defp update_motion(tracker, button, x, y) do
    {press_x, press_y} = tracker.press_position

    if abs(x - press_x) >= tracker.drag_threshold or
         abs(y - press_y) >= tracker.drag_threshold do
      {%{tracker | dragging: true, last_position: {x, y}},
       [
         {:drag_start, button, press_x, press_y},
         {:drag, button, x, y, x - press_x, y - press_y}
       ]}
    else
      {%{tracker | last_position: {x, y}}, []}
    end
  end

  defp delta(nil, _position), do: {0, 0}
  defp delta({old_x, old_y}, {x, y}), do: {x - old_x, y - old_y}
end

defmodule TermUI.Mouse do
  @moduledoc """
  Pure mouse hit testing and local-coordinate routing.

  The Elm application creates regions from its current layout and stores any
  `TermUI.Mouse.Tracker` state. No registry, process, or global spatial index is
  used. Coordinates are zero-based because terminal mouse events are zero-based.
  """

  alias TermUI.Event
  alias TermUI.Mouse.Region

  @doc "Creates a routing region. Later equal-z regions are treated as topmost."
  @spec region(
          term(),
          non_neg_integer(),
          non_neg_integer(),
          pos_integer(),
          pos_integer(),
          keyword()
        ) ::
          Region.t()
  def region(id, x, y, width, height, opts \\ [])
      when is_integer(x) and x >= 0 and is_integer(y) and y >= 0 and is_integer(width) and
             width > 0 and is_integer(height) and height > 0 do
    %Region{
      id: id,
      x: x,
      y: y,
      width: width,
      height: height,
      z_index: region_z_index!(opts),
      metadata: region_metadata!(opts)
    }
  end

  @doc "Returns the topmost region and local coordinates at a screen position."
  @spec hit_test([Region.t()], integer(), integer()) ::
          {:ok, Region.t(), {integer(), integer()}} | :none
  def hit_test(regions, x, y) when is_list(regions) and is_integer(x) and is_integer(y) do
    regions
    |> topmost_region(x, y)
    |> case do
      nil -> :none
      region -> {:ok, region, to_local(region, x, y)}
    end
  end

  @doc "Routes a mouse event to the topmost region with local coordinates."
  @spec route([Region.t()], Event.Mouse.t()) :: {:ok, term(), Event.Mouse.t()} | :none
  def route(regions, %Event.Mouse{x: x, y: y} = event) do
    case hit_test(regions, x, y) do
      {:ok, region, {local_x, local_y}} ->
        {:ok, region.id, %{event | x: local_x, y: local_y}}

      :none ->
        :none
    end
  end

  @doc "Routes a mouse event to all matching regions in front-to-back order."
  @spec route_all([Region.t()], Event.Mouse.t()) :: [{term(), Event.Mouse.t()}]
  def route_all(regions, %Event.Mouse{x: x, y: y} = event) do
    Enum.map(matching_regions(regions, x, y), fn region ->
      {local_x, local_y} = to_local(region, x, y)
      {region.id, %{event | x: local_x, y: local_y}}
    end)
  end

  @doc "Transforms global coordinates to region-local coordinates."
  @spec to_local(Region.t(), integer(), integer()) :: {integer(), integer()}
  def to_local(%Region{} = region, x, y), do: {x - region.x, y - region.y}

  @doc "Transforms region-local coordinates to global coordinates."
  @spec to_global(Region.t(), integer(), integer()) :: {integer(), integer()}
  def to_global(%Region{} = region, x, y), do: {x + region.x, y + region.y}

  @doc "Returns true when a point is inside a region."
  @spec contains?(Region.t(), integer(), integer()) :: boolean()
  def contains?(%Region{} = region, x, y) do
    x >= region.x and x < region.x + region.width and y >= region.y and
      y < region.y + region.height
  end

  @doc "Returns true when two regions overlap."
  @spec overlap?(Region.t(), Region.t()) :: boolean()
  def overlap?(%Region{} = first, %Region{} = second) do
    not (first.x + first.width <= second.x or second.x + second.width <= first.x or
           first.y + first.height <= second.y or second.y + second.height <= first.y)
  end

  @doc "Clips global coordinates to a region."
  @spec clip(Region.t(), integer(), integer()) :: {integer(), integer()}
  def clip(%Region{} = region, x, y) do
    {
      x |> max(region.x) |> min(region.x + region.width - 1),
      y |> max(region.y) |> min(region.y + region.height - 1)
    }
  end

  defp matching_regions(regions, x, y) do
    regions
    |> Enum.with_index()
    |> Enum.filter(fn {region, _index} -> contains?(region, x, y) end)
    |> Enum.sort_by(fn {region, index} -> {region.z_index, index} end, :desc)
    |> Enum.map(&elem(&1, 0))
  end

  defp topmost_region(regions, x, y) do
    Enum.reduce(regions, nil, fn region, current ->
      cond do
        not contains?(region, x, y) -> current
        is_nil(current) -> region
        region.z_index >= current.z_index -> region
        true -> current
      end
    end)
  end

  defp region_z_index!(opts) do
    case Keyword.get(opts, :z_index, 0) do
      z_index when is_integer(z_index) -> z_index
      _other -> raise ArgumentError, "mouse region z_index must be an integer"
    end
  end

  defp region_metadata!(opts) do
    case Keyword.get(opts, :metadata, %{}) do
      metadata when is_map(metadata) -> metadata
      _other -> raise ArgumentError, "mouse region metadata must be a map"
    end
  end
end
