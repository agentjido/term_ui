defmodule TermUI.Widget.Spinner do
  @moduledoc "A pure animated spinner. The parent application owns timer effects."

  @behaviour TermUI.Widget

  alias TermUI.{CharacterSet, Style}
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          frames: [String.t()],
          phase: non_neg_integer(),
          label: String.t(),
          character_set: CharacterSet.charset(),
          style: Style.t()
        }

  defstruct frames: [],
            phase: 0,
            label: "",
            character_set: :unicode,
            style: %Style{}

  @impl true
  def init(opts) do
    character_set = Keyword.get(opts, :character_set, CharacterSet.current())
    default_frames = CharacterSet.get(character_set).spinner_frames
    frames = normalize_frames(Keyword.get(opts, :frames, default_frames), default_frames)

    %__MODULE__{
      frames: frames,
      phase: max(Keyword.get(opts, :phase, 0), 0),
      label: opts |> Keyword.get(:label, "") |> to_string(),
      character_set: character_set,
      style: Keyword.get(opts, :style, Style.new())
    }
  end

  @impl true
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, dimensions) do
    frame = Enum.at(state.frames, rem(state.phase, length(state.frames)))
    text = if state.label == "", do: frame, else: frame <> " " <> state.label
    Helpers.frame([[{text, state.style}]], dimensions)
  end

  @doc "Advances the spinner by one frame."
  @spec tick(t()) :: t()
  def tick(state), do: %{state | phase: rem(state.phase + 1, length(state.frames))}

  @doc "Replaces the spinner label."
  @spec set_label(t(), iodata()) :: t()
  def set_label(state, label), do: %{state | label: IO.iodata_to_binary(label)}

  defp normalize_frames([], fallback), do: fallback
  defp normalize_frames(frames, _fallback), do: Enum.map(frames, &to_string/1)
end
