defmodule TermUI.Widget do
  @moduledoc """
  The contract for pure, embedded widgets.

  A widget is not a process. Its parent stores its state, sends events to
  `update/2`, and composes the `TermUI.Frame` from `view/2` into the
  application frame. Widget messages are data for the parent application.

  All supplied widgets use this lifecycle:

      state = MyWidget.init(options)
      {state, messages} = MyWidget.update(event, state)
      {state, messages} = TermUI.Widget.mouse(MyWidget, local_mouse, state, {width, height})
      frame = MyWidget.view(state, {width, height})

  Use `TermUI.Frame.overlay/4` to compose widget frames. No widget starts a
  process or uses a global registry.

  Scrollable widgets can implement the optional `update/3` callback. Pass the
  same child dimensions used by `view/2` through `update/4` or the widget's
  `update/3`. `set_dimensions/2` stores that size for later `update/2` calls.
  `page_size` sets page movement only. Before a size is supplied, Viewport,
  LogViewer, and Stream use a one-row body for navigation bounds.

  The optional `mouse/3` callback receives zero-based local coordinates and
  widget dimensions. `mouse/4` uses the dimension-aware update path when a
  widget does not implement that callback.
  """

  alias TermUI.Event

  @type state :: term()
  @type message :: term()
  @type dimensions :: {width :: pos_integer(), height :: pos_integer()}
  @type renderable ::
          TermUI.Frame.t() | {module(), state()} | (dimensions() -> TermUI.Frame.t())

  @callback init(keyword()) :: state()
  @callback update(Event.t(), state()) :: {state(), [message()]}
  @callback update(Event.t(), state(), dimensions()) :: {state(), [message()]}
  @callback view(state(), dimensions()) :: TermUI.Frame.t()
  @callback mouse(Event.Mouse.t(), state(), dimensions()) :: {state(), [message()]}

  @optional_callbacks mouse: 3, update: 3

  @doc "Renders one widget through the common contract."
  @spec view(module(), state(), dimensions()) :: TermUI.Frame.t()
  def view(module, state, {width, height} = dimensions)
      when is_atom(module) and width > 0 and height > 0 do
    case module.view(state, dimensions) do
      %TermUI.Frame{} = frame ->
        frame

      other ->
        raise ArgumentError, "widget view returned #{inspect(other)}, expected TermUI.Frame"
    end
  end

  @doc "Delivers an event with the current child size, when supported."
  @spec update(module(), Event.t(), state(), dimensions()) :: {state(), [message()]}
  def update(module, event, state, {width, height} = dimensions)
      when is_atom(module) and width > 0 and height > 0 do
    if Code.ensure_loaded?(module) and function_exported?(module, :update, 3),
      do: module.update(event, state, dimensions),
      else: module.update(event, state)
  end

  @doc "Delivers a routed local mouse event with the widget dimensions."
  @spec mouse(module(), Event.Mouse.t(), state(), dimensions()) :: {state(), [message()]}
  def mouse(module, %Event.Mouse{} = event, state, {width, height} = dimensions)
      when is_atom(module) and width > 0 and height > 0 do
    if Code.ensure_loaded?(module) and function_exported?(module, :mouse, 3),
      do: module.mouse(event, state, dimensions),
      else: update(module, event, state, dimensions)
  end
end
