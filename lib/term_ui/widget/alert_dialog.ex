defmodule TermUI.Widget.AlertDialog do
  @moduledoc "A pure information, warning, error, or confirmation dialog."

  @behaviour TermUI.Widget

  alias TermUI.Widget.Dialog

  @type alert_type :: :info | :warning | :error | :confirm
  @type t :: %__MODULE__{type: alert_type(), dialog: Dialog.t()}
  defstruct type: :info,
            dialog: %Dialog{}

  @impl true
  def init(opts) do
    type = Keyword.get(opts, :type, :info)
    buttons = Keyword.get(opts, :buttons, default_buttons(type))
    title = Keyword.get(opts, :title, default_title(type))

    dialog =
      Dialog.init(
        title: title,
        content: Keyword.get(opts, :message, ""),
        buttons: buttons,
        dismiss_message: :cancel
      )

    %__MODULE__{type: type, dialog: dialog}
  end

  @impl true
  def update(event, state) do
    {dialog, messages} = Dialog.update(event, state.dialog)
    {%{state | dialog: dialog}, messages}
  end

  @impl true
  def mouse(event, state, dimensions) do
    {dialog, messages} = Dialog.mouse(event, state.dialog, dimensions)
    {%{state | dialog: dialog}, messages}
  end

  @impl true
  def view(state, dimensions), do: Dialog.view(state.dialog, dimensions)

  defp default_buttons(:confirm),
    do: [%{id: :yes, label: "Yes", message: :confirm}, %{id: :no, label: "No", message: :cancel}]

  defp default_buttons(_type), do: [%{id: :ok, label: "OK", message: :ok}]
  defp default_title(:warning), do: "Warning"
  defp default_title(:error), do: "Error"
  defp default_title(:confirm), do: "Confirm"
  defp default_title(:info), do: "Information"
end
