defmodule TermUI.Widget.RouterTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Focus, Mouse}
  alias TermUI.Widget.{Checkbox, Router}

  defmodule Parent do
    defstruct form: %{}
  end

  test "updates one child in parent state and maps child commands to parent messages" do
    parent = %Parent{
      form: %{
        primary: Checkbox.init(id: :shared),
        secondary: Checkbox.init(id: :shared)
      }
    }

    primary =
      Router.new(:primary, Checkbox, [:form, :primary],
        map_message: fn id, message -> {:form_child, id, message} end
      )

    secondary = Router.new(:secondary, Checkbox, [:form, :secondary])

    assert {parent, [{:form_child, :primary, {:changed, :shared, true}}]} =
             Router.update(primary, Event.key(:space), parent)

    assert parent.form.primary.checked
    refute parent.form.secondary.checked

    assert {parent, [{:widget, :secondary, {:changed, :shared, true}}]} =
             Router.update(secondary, Event.key(:space), parent)

    assert parent.form.primary.checked
    assert parent.form.secondary.checked
  end

  test "uses the child ID for focus identity" do
    primary = Router.new(:primary, Checkbox, [:primary])
    secondary = Router.new(:secondary, Checkbox, [:secondary])
    focus = Focus.new([:primary, :secondary], current: :secondary)

    refute Router.focused?(primary, focus)
    assert Router.focused?(secondary, focus)
  end

  test "uses the child ID for mouse regions and delivery" do
    primary = Router.new(:primary, Checkbox, [:primary])
    secondary = Router.new(:secondary, Checkbox, [:secondary])

    parent = %{
      primary: Checkbox.init(id: :shared),
      secondary: Checkbox.init(id: :shared)
    }

    regions = [
      Router.region(primary, 0, 0, 10, 1),
      Router.region(secondary, 12, 0, 10, 1)
    ]

    routed = Mouse.route(regions, Event.mouse(:release, :left, 14, 0))

    assert {^parent, []} = Router.mouse(primary, routed, parent, {10, 1})

    assert {parent, [{:widget, :secondary, {:changed, :shared, true}}]} =
             Router.mouse(secondary, routed, parent, {10, 1})

    refute parent.primary.checked
    assert parent.secondary.checked
  end

  test "requires explicit valid route data" do
    send(self(), {:route_path, []})
    assert_receive {:route_path, invalid_path}

    assert_raise ArgumentError, ~r/path must not be empty/, fn ->
      Router.new(:child, Checkbox, invalid_path)
    end

    assert_raise Zoi.ParseError, fn ->
      Router.new(:child, Checkbox, [:child], map_message: :invalid)
    end
  end
end
