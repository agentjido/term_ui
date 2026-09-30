defmodule TermUI.Widget.FormValidationTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}
  alias TermUI.Widget.FormBuilder

  test "field errors remain until the configured validator succeeds" do
    form =
      FormBuilder.init(
        fields: [
          %{
            id: :name,
            label: "Name",
            validators: [
              fn value -> if String.length(value) >= 3, do: :ok, else: {:error, "too short"} end
            ]
          }
        ],
        values: %{name: "a"}
      )
      |> FormBuilder.validate_field(:name)

    assert form.errors == %{name: "too short"}

    form = FormBuilder.put_value(form, :name, "ab")
    assert form.errors == %{name: "too short"}

    form = FormBuilder.put_value(form, :name, "Ada")
    assert form.errors == %{}
  end

  test "group validation attaches and clears a field-level error" do
    form = password_form()
    form = FormBuilder.validate_group(form, :passwords)

    assert form.errors == %{confirmation: "does not match"}
    assert Frame.row_text(FormBuilder.view(form, {30, 6}), 3) =~ "does not match"

    form = FormBuilder.put_value(form, :confirmation, "still wrong")
    assert form.errors == %{confirmation: "does not match"}

    form = FormBuilder.put_value(form, :confirmation, "secret")
    assert form.errors == %{}
  end

  test "submit validation focuses the first invalid field in explicit state" do
    form =
      FormBuilder.init(
        fields: [
          %{id: :name, label: "Name", required: true},
          %{id: :accepted, label: "Accepted", type: :checkbox}
        ],
        validators: [
          fn values ->
            if values.accepted,
              do: :ok,
              else: {:error, %{accepted: "must be accepted"}}
          end
        ]
      )

    form = %{form | active: 1}

    assert {form, [{:invalid, errors}]} = FormBuilder.update(Event.key(:enter), form)
    assert errors == %{name: "is required", accepted: "must be accepted"}
    assert form.active == 0
    assert FormBuilder.focused_field(form) == :name

    form = FormBuilder.put_value(form, :name, "Ada")
    form = FormBuilder.put_value(form, :accepted, true)

    assert {form, [{:submit, %{name: "Ada", accepted: true}}]} =
             FormBuilder.update(Event.key(:enter), form)

    assert form.errors == %{}
  end

  test "field, group, and submit sources do not clear each other" do
    form =
      FormBuilder.init(
        fields: [
          %{id: :left, label: "Left", required: true},
          %{id: :right, label: "Right"}
        ],
        groups: [
          %{
            id: :pair,
            fields: [:left, :right],
            validators: [fn _values -> {:error, :right, "group error"} end]
          }
        ],
        validators: [fn _values -> {:error, :left, "submit error"} end]
      )
      |> FormBuilder.validate()

    assert form.errors == %{left: "is required", right: "group error"}
    assert map_size(form.error_sources) == 3
    refute Enum.any?(Map.values(Map.from_struct(form)), &is_pid/1)
  end

  test "validation groups reject unknown field IDs" do
    assert_raise ArgumentError, "validation group contains an unknown field ID: :missing", fn ->
      FormBuilder.init(
        fields: [%{id: :known, label: "Known"}],
        groups: [%{id: :bad, fields: [:missing]}]
      )
    end
  end

  defp password_form do
    FormBuilder.init(
      fields: [
        %{id: :password, label: "Password"},
        %{id: :confirmation, label: "Confirm"}
      ],
      values: %{password: "secret", confirmation: "wrong"},
      groups: [
        %{
          id: :passwords,
          fields: [:password, :confirmation],
          validators: [
            fn values ->
              if values.password == values.confirmation,
                do: :ok,
                else: {:error, :confirmation, "does not match"}
            end
          ]
        }
      ]
    )
  end
end
