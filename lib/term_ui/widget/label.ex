defmodule TermUI.Widget.Label do
  @moduledoc "A pure text label with wrapping, alignment, and style."

  @behaviour TermUI.Widget

  alias TermUI.{Frame, Style}
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          text: String.t(),
          align: :left | :center | :right,
          wrap: boolean(),
          style: Style.t()
        }
  defstruct text: "",
            align: :left,
            wrap: true,
            style: %Style{}

  @impl true
  def init(opts) do
    %__MODULE__{
      text: opts |> Keyword.get(:text, "") |> to_string(),
      align: Keyword.get(opts, :align, :left),
      wrap: Keyword.get(opts, :wrap, true),
      style: Keyword.get(opts, :style, Style.new())
    }
  end

  @impl true
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, _height} = dimensions) do
    lines = if state.wrap, do: Frame.wrap(state.text, width), else: [state.text]

    rows =
      Enum.map(lines, fn line -> [{Helpers.align(line, width, state.align), state.style}] end)

    Helpers.frame(rows, dimensions)
  end

  @doc "Replaces the label text."
  @spec set_text(t(), iodata()) :: t()
  def set_text(state, text), do: %{state | text: IO.iodata_to_binary(text)}
end
