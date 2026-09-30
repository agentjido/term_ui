defmodule IExCounter.Recipes.Form do
  @moduledoc "A required field, a choice, and a checkbox in one pure form."

  use TermUI.Elm

  alias TermUI.{Command, Event, Frame}
  alias TermUI.Widget.FormBuilder

  @impl true
  def init(opts) do
    form =
      FormBuilder.init(
        fields: [
          %{id: :name, label: "Name", required: true},
          %{id: :role, label: "Role", type: :select, options: ["reader", "writer"]},
          %{id: :alerts, label: "Alerts", type: :checkbox}
        ]
      )

    %{dimensions: Keyword.fetch!(opts, :dimensions), form: form, status: "Enter: validate"}
  end

  @impl true
  def event_to_msg(%Event.Key{key: :escape}, _state), do: {:msg, :quit}

  def event_to_msg(%Event.Resize{width: width, height: height}, _state),
    do: {:msg, {:resize, width, height}}

  def event_to_msg(event, _state), do: {:msg, {:event, event}}

  @impl true
  def update(:quit, state), do: {state, [Command.shutdown()]}
  def update({:resize, width, height}, state), do: %{state | dimensions: {width, height}}

  def update({:event, event}, state) do
    {form, messages} = FormBuilder.update(event, state.form)

    status =
      Enum.reduce(messages, state.status, fn
        {:invalid, _errors}, _status -> "Fix the required fields"
        {:submit, values}, _status -> "Saved: #{values.name} (#{values.role})"
        _message, status -> status
      end)

    %{state | form: form, status: status}
  end

  @impl true
  def view(%{dimensions: {width, height}} = state) do
    Frame.new(width, height)
    |> Frame.overlay(FormBuilder.view(state.form, {width, max(height - 2, 1)}), 1, 1)
    |> Frame.put_row(max(height - 1, 1), state.status)
    |> Frame.put_row(height, "Tab: field   Space: choice   Esc: quit")
  end
end
