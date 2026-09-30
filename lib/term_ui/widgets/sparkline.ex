defmodule TermUI.Widgets.Sparkline do
  @moduledoc """
  Deprecated plural name for the pure v2 `TermUI.Widget.Sparkline`.

  This is the only plural widget facade because the old sparkline has no
  process, event, selection, or mutable state contract. The facade returns a
  v2 `TermUI.Frame`; it does not restore the old render-node type.

  New code must initialize and render the singular module directly:

      state = TermUI.Widget.Sparkline.init(values: [1, 3, 2])
      frame = TermUI.Widget.Sparkline.view(state, {3, 1})

  `render/1` and `render_labeled/1` infer a frame size for source migrations.
  Pass `:width` or `:height` to override that inferred size.
  """

  import Kernel, except: [to_string: 1]

  @behaviour TermUI.Widget

  alias TermUI.Widget.Sparkline

  @replacement "Use TermUI.Widget.Sparkline instead."

  @deprecated @replacement
  defdelegate init(opts), to: Sparkline

  @deprecated @replacement
  defdelegate update(event, state), to: Sparkline

  @deprecated @replacement
  defdelegate view(state, dimensions), to: Sparkline

  @deprecated @replacement
  defdelegate push(state, value, limit \\ 1_000), to: Sparkline

  @deprecated "Use TermUI.Widget.Sparkline.value_to_bar/3 instead."
  defdelegate value_to_bar(value, minimum, maximum), to: Sparkline

  @deprecated "Use TermUI.Widget.Sparkline.bar_characters/0 instead."
  defdelegate bar_characters(), to: Sparkline

  @deprecated "Use TermUI.Widget.Sparkline.to_sparkline/2 instead."
  defdelegate to_sparkline(values, opts \\ []), to: Sparkline

  @doc false
  @deprecated "Use TermUI.Widget.Sparkline.to_sparkline/2 instead."
  @spec to_string(term(), keyword()) :: String.t()
  def to_string(values, opts \\ []), do: Sparkline.to_sparkline(values, opts)

  @doc "Returns a pure v2 frame with an inferred or explicit size."
  @deprecated "Use TermUI.Widget.Sparkline.init/1 and view/2 instead."
  @spec render(keyword()) :: TermUI.Frame.t()
  def render(opts) do
    state = Sparkline.init(opts)
    Sparkline.view(state, dimensions(state, opts))
  end

  @doc "Returns a labeled pure v2 frame with optional minimum and maximum labels."
  @deprecated "Use TermUI.Widget.Sparkline.init/1 and view/2 instead."
  @spec render_labeled(keyword()) :: TermUI.Frame.t()
  def render_labeled(opts) do
    opts = Keyword.put_new(opts, :show_range, true)
    state = Sparkline.init(opts)
    Sparkline.view(state, dimensions(state, opts))
  end

  defp dimensions(state, opts) do
    width = opts |> Keyword.get(:width, Sparkline.natural_width(state)) |> max(1)
    height = opts |> Keyword.get(:height, 1) |> max(1)
    {width, height}
  end
end
