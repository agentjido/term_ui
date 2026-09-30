defmodule TermUI.Widget.LineInput do
  @moduledoc "A labeled and validated pure single-line input."

  @behaviour TermUI.Widget

  alias TermUI.{DisplayWidth, Event, Frame, Style}
  alias TermUI.Widget.TextInput

  @type t :: %__MODULE__{
          label: String.t() | nil,
          prompt: String.t(),
          input: TextInput.t(),
          validator: (String.t() -> :ok | {:error, String.t()}) | nil,
          error: String.t() | nil
        }
  defstruct label: nil,
            prompt: "> ",
            input: %TextInput{},
            validator: nil,
            error: nil

  @impl true
  def init(opts),
    do: %__MODULE__{
      label: Keyword.get(opts, :label),
      prompt: Keyword.get(opts, :prompt, "> "),
      input: TextInput.init(opts),
      validator: Keyword.get(opts, :validator)
    }

  @impl true
  def update(event, state) do
    {input, messages} = TextInput.update(event, state.input)

    state = %{
      state
      | input: input,
        error: if(Enum.any?(messages, &match?({:changed, _}, &1)), do: nil, else: state.error)
    }

    if Enum.any?(messages, &match?({:submit, _}, &1)) do
      validate(state)
    else
      {state, messages}
    end
  end

  @impl true
  def mouse(%Event.Mouse{y: y} = event, state, {width, _height}) do
    input_row = if state.label, do: 1, else: 0

    if y == input_row do
      prompt_width = max(DisplayWidth.width(state.prompt), 0)
      input_width = max(width - prompt_width, 1)
      local_event = %{event | x: max(event.x - prompt_width, 0), y: 0}
      {input, messages} = TextInput.mouse(local_event, state.input, {input_width, 1})
      {%{state | input: input}, messages}
    else
      update(event, state)
    end
  end

  @impl true
  def view(state, {width, height}) do
    label_rows =
      if state.label, do: [[{state.label, Style.new(fg: :cyan, attrs: [:bold])}]], else: []

    label_height = length(label_rows)
    prompt_width = max(DisplayWidth.width(state.prompt), 0)
    input_width = max(width - prompt_width, 1)
    {spans, cursor} = TextInput.row_spans(state.input, input_width)
    input_row = [state.prompt | List.wrap(spans)]

    error_rows =
      if state.error && height > label_height + 1,
        do: [[{"  " <> state.error, Style.new(fg: :red)}]],
        else: []

    Frame.from_rows(label_rows ++ [input_row] ++ error_rows, width, height,
      cursor: {prompt_width + cursor, label_height + 1}
    )
  end

  @doc "Validates the current value."
  @spec validate(t()) :: {t(), [term()]}
  def validate(%{validator: nil} = state), do: {state, [{:submit, state.input.value}]}

  def validate(state) do
    case state.validator.(state.input.value) do
      :ok -> {%{state | error: nil}, [{:submit, state.input.value}]}
      {:error, error} -> {%{state | error: error}, [{:invalid, error}]}
    end
  end
end
