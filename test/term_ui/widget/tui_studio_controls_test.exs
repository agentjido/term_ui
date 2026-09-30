defmodule TermUI.Widget.TUIStudioControlsTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}

  alias TermUI.Widget.{Breadcrumb, Checkbox, RadioGroup, Select, Spinner, Toggle}

  test "checkbox supports keys, text space, mouse, focus, and disabled state" do
    checkbox = Checkbox.init(id: :logs, label: "Logs")
    assert Frame.row_text(Checkbox.view(checkbox, {12, 1}), 1) == "[ ] Logs    "

    assert {checkbox, [{:changed, :logs, true}]} =
             Checkbox.update(Event.key(:space), checkbox)

    assert checkbox.checked
    assert {checkbox, [{:changed, :logs, false}]} = Checkbox.update(Event.text(" "), checkbox)

    {checkbox, []} = Checkbox.mouse(Event.mouse(:press, :left, 1, 0), checkbox, {12, 1})
    assert checkbox.focused

    assert {_checkbox, [{:changed, :logs, true}]} =
             Checkbox.mouse(Event.mouse(:release, :left, 1, 0), checkbox, {12, 1})

    disabled = Checkbox.init(id: :logs, disabled: true)
    assert {^disabled, []} = Checkbox.update(Event.key(:enter), disabled)
    assert {^disabled, []} = Checkbox.mouse(Event.mouse(:release, :left, 0, 0), disabled, {4, 1})
    assert {^disabled, []} = Checkbox.update(Event.focus(:gained), disabled)
    assert Frame.row_text(Checkbox.view(disabled, {4, 1}), 1) == "[ ] "

    custom = Checkbox.init(checked: true, show_brackets: false, checked_icon: "✓")
    assert Frame.row_text(Checkbox.view(custom, {3, 1}), 1) == "✓  "
    assert {^custom, []} = Checkbox.mouse(Event.mouse(:release, :right, 0, 0), custom, {3, 1})
    assert {^custom, []} = Checkbox.mouse(Event.mouse(:release, :left, 4, 0), custom, {3, 1})
  end

  test "toggle keeps its parent-facing change contract" do
    toggle = Toggle.init(id: :live, label: "Live", checked: true)
    assert Frame.row_text(Toggle.view(toggle, {14, 1}), 1) == "[ ON ] Live   "
    assert {toggle, [{:changed, :live, false}]} = Toggle.update(Event.key(:enter), toggle)
    refute toggle.checked
    assert Toggle.set_checked(toggle, true).checked
    assert Toggle.focus(toggle).focused

    assert {toggle, [{:changed, :live, true}]} = Toggle.update(Event.text(" "), toggle)
    assert Frame.row_text(Toggle.view(toggle, {14, 1}), 1) == "[ ON ] Live   "

    {toggle, []} = Toggle.mouse(Event.mouse(:press, :left, 0, 0), toggle, {14, 1})
    assert toggle.focused

    assert {_toggle, [{:changed, :live, false}]} =
             Toggle.mouse(Event.mouse(:release, :left, 0, 0), toggle, {14, 1})

    disabled = Toggle.init(disabled: true)
    assert {^disabled, []} = Toggle.update(Event.key(:space), disabled)
    assert {^disabled, []} = Toggle.mouse(Event.mouse(:release, :left, 0, 0), disabled, {8, 1})
    assert {^disabled, []} = Toggle.update(Event.focus(:lost), disabled)
  end

  test "radio group skips disabled options and selects with keyboard and mouse" do
    radio =
      RadioGroup.init(
        id: :mode,
        options: [
          RadioGroup.option(:auto, "Auto"),
          RadioGroup.option(:manual, "Manual", disabled: true),
          RadioGroup.option(:safe, "Safe")
        ],
        selected: :auto
      )

    assert {radio, []} = RadioGroup.update(Event.key(:down), radio)
    assert radio.cursor == 2
    assert {radio, [{:selected, :mode, :safe}]} = RadioGroup.update(Event.text(" "), radio)
    assert RadioGroup.selected(radio) == :safe

    assert {radio, []} =
             RadioGroup.mouse(Event.mouse(:press, :left, 0, 0), radio, {20, 3})

    assert {_radio, [{:selected, :mode, :auto}]} =
             RadioGroup.mouse(Event.mouse(:release, :left, 0, 0), radio, {20, 3})

    horizontal = RadioGroup.init(options: [{:one, "界"}, {:two, "Two"}], orientation: :horizontal)

    assert {horizontal, [{:selected, nil, :two}]} =
             RadioGroup.mouse(Event.mouse(:release, :left, 7, 0), horizontal, {20, 1})

    assert horizontal.selected == :two
  end

  test "radio group handles edges, empty data, horizontal gaps, and setters" do
    radio =
      RadioGroup.init(
        options: [
          %{value: :one, label: "One", disabled: false},
          %{value: :two, label: "Two", disabled: true},
          :three,
          {:one, "Duplicate"}
        ],
        selected: :one,
        orientation: :horizontal
      )

    assert length(radio.options) == 3
    assert {radio, []} = RadioGroup.update(Event.key(:end), radio)
    assert radio.cursor == 2
    assert {radio, []} = RadioGroup.update(Event.key(:home), radio)
    assert radio.cursor == 0
    assert {radio, []} = RadioGroup.update(Event.key(:left), radio)
    assert radio.cursor == 2
    assert {radio, [{:selected, nil, :three}]} = RadioGroup.update(Event.key(:enter), radio)
    assert Frame.row_text(RadioGroup.view(radio, {30, 1}), 1) =~ "three"
    assert RadioGroup.select(radio, :two) == radio
    assert RadioGroup.select(radio, :one).selected == :one
    assert RadioGroup.focus(radio).focused

    assert {^radio, []} =
             RadioGroup.mouse(Event.mouse(:release, :left, 8, 0), radio, {30, 1})

    assert {^radio, []} =
             RadioGroup.mouse(Event.mouse(:release, :left, 40, 0), radio, {30, 1})

    disabled = RadioGroup.init(options: [:one], disabled: true)
    assert {^disabled, []} = RadioGroup.update(Event.key(:down), disabled)

    assert {^disabled, []} =
             RadioGroup.mouse(Event.mouse(:release, :left, 0, 0), disabled, {8, 1})

    assert Frame.cell(RadioGroup.view(disabled, {8, 1}), 1, 1).fg == :bright_black

    empty = RadioGroup.init(options: [])
    assert {^empty, []} = RadioGroup.update(Event.key(:down), empty)
    assert {^empty, []} = RadioGroup.update(Event.key(:enter), empty)
    assert %Frame{} = RadioGroup.view(empty, {1, 1})

    nil_value =
      RadioGroup.init(
        options: [
          RadioGroup.option(nil, "Blocked", disabled: true),
          RadioGroup.option(:ready, "Ready")
        ]
      )

    assert nil_value.cursor == 1

    gap = RadioGroup.init(options: [:a, :b], orientation: :horizontal)

    assert {^gap, []} =
             RadioGroup.mouse(Event.mouse(:release, :left, 5, 0), gap, {20, 1})
  end

  test "select opens, scrolls, chooses, closes, and rejects disabled options" do
    select =
      Select.init(
        id: :region,
        options: [
          Select.option(:one, "One"),
          Select.option(:two, "Two", disabled: true),
          Select.option(:three, "Three")
        ],
        page_size: 2
      )

    assert Select.open(select).open
    assert {select, []} = Select.update(Event.key(:enter), select)
    assert select.open
    assert {select, []} = Select.update(Event.key(:down), select)
    assert select.cursor == 2

    assert {select, [{:selected, :region, :three}]} =
             Select.update(Event.key(:space), select)

    refute select.open
    assert Select.selected(select) == :three
    assert Frame.row_text(Select.view(select, {12, 3}), 1) =~ "Three"
    refute Select.select(select, :two).selected == :two

    closed = Select.close(select)

    assert {opened, []} =
             Select.mouse(Event.mouse(:release, :left, 1, 0), closed, {12, 3})

    assert opened.open
    assert {^opened, []} = Select.mouse(Event.mouse(:release, :left, 20, 0), opened, {12, 3})

    disabled = Select.init(options: [{:one, "One"}], disabled: true, open: true)
    refute disabled.open
    assert Select.open(disabled) == disabled
  end

  test "select covers cancel, edge keys, mouse rows, replacement, and empty data" do
    select =
      Select.init(
        id: :choice,
        options: [:one, Select.option(:two, "Two", disabled: true), {:three, "Three"}],
        open: true,
        page_size: 1
      )

    assert Frame.row_text(Select.view(select, {10, 3}), 2) =~ "one"
    assert {select, []} = Select.update(Event.key(:end), select)
    assert select.cursor == 2
    assert select.offset == 2
    assert {select, []} = Select.update(Event.key(:home), select)
    assert select.cursor == 0
    assert {select, []} = Select.update(Event.key(:up), select)
    assert select.cursor == 2
    assert {select, []} = Select.update(Event.key(:escape), select)
    refute select.open
    assert {select, []} = Select.update(Event.text(" "), select)
    assert select.open

    {select, []} = Select.mouse(Event.mouse(:press, :left, 1, 1), select, {10, 3})
    assert select.focused

    assert {select, [{:selected, :choice, :three}]} =
             Select.mouse(Event.mouse(:release, :left, 1, 1), select, {10, 3})

    refute select.open
    assert select.selected == :three

    select =
      Select.set_options(select, [{:next, "Next"}, Select.option(:off, "Off", disabled: true)])

    assert select.selected == nil
    assert select.cursor == 0
    assert Select.select(select, :next).selected == :next

    empty = Select.init(options: [])
    assert Select.open(empty) == empty
    assert Select.set_options(select, []).options == []
    assert {^empty, []} = Select.update(Event.key(:enter), empty)
    assert %Frame{} = Select.view(empty, {1, 1})

    disabled = Select.init(options: [:one], disabled: true)
    assert {^disabled, []} = Select.update(Event.key(:enter), disabled)
    assert {^disabled, []} = Select.mouse(Event.mouse(:release, :left, 0, 0), disabled, {8, 2})

    all_disabled = Select.init(options: [Select.option(:off, "Off", disabled: true)])
    assert Select.open(all_disabled) == all_disabled
    assert {^all_disabled, []} = Select.update(Event.key(:enter), all_disabled)

    assert {^all_disabled, []} =
             Select.mouse(Event.mouse(:release, :left, 0, 0), all_disabled, {8, 2})
  end

  test "select mouse geometry uses the same compact offset as view" do
    select = Select.init(id: :number, options: Enum.to_list(1..6), page_size: 6, open: true)
    {select, []} = Select.update(Event.key(:end), select)

    assert Frame.row_text(Select.view(select, {8, 3}), 2) =~ "5"

    assert {_select, [{:selected, :number, 5}]} =
             Select.mouse(Event.mouse(:release, :left, 1, 1), select, {8, 3})

    short = Select.init(id: :short, options: [:one, :two], page_size: 1, open: true)

    assert {^short, []} =
             Select.mouse(Event.mouse(:release, :left, 1, 2), short, {8, 4})
  end

  test "spinner advances only when the parent calls tick" do
    spinner = Spinner.init(label: "Loading", character_set: :ascii, phase: 3)
    assert Frame.row_text(Spinner.view(spinner, {12, 1}), 1) == "\\ Loading   "
    assert {^spinner, []} = Spinner.update(Event.key(:enter), spinner)

    spinner = Spinner.tick(spinner)
    assert spinner.phase == 0
    assert Frame.row_text(Spinner.view(spinner, {12, 1}), 1) == "| Loading   "
    assert Spinner.set_label(spinner, "Ready").label == "Ready"

    custom = Spinner.init(frames: ["a", "b"], phase: 1)
    assert Frame.row_text(Spinner.view(custom, {1, 1}), 1) == "b"
    assert Spinner.init(frames: [], character_set: :ascii).frames == ["|", "/", "-", "\\"]
  end

  test "breadcrumb keeps the current item and compacts the middle" do
    breadcrumb =
      Breadcrumb.init(items: [{"⌂", "Home"}, "Projects", %{label: "TermUI", icon: "◆"}])

    assert Frame.row_text(Breadcrumb.view(breadcrumb, {40, 1}), 1) =~
             "⌂ Home / Projects / ◆ TermUI"

    assert Frame.row_text(Breadcrumb.view(breadcrumb, {16, 1}), 1) == "⌂ Home / … / ◆ T"
    assert Breadcrumb.set_items(breadcrumb, ["One"]).items == [%{label: "One", icon: ""}]
    assert Breadcrumb.item("Docs", icon: "◆") == %{label: "Docs", icon: "◆"}
    assert {^breadcrumb, []} = Breadcrumb.update(Event.key(:enter), breadcrumb)

    single = Breadcrumb.init(items: [Breadcrumb.item("Long current item")])
    assert Frame.row_text(Breadcrumb.view(single, {5, 1}), 1) == "Long "

    assert Frame.cells(Breadcrumb.view(Breadcrumb.init(items: []), {5, 1})) == []

    narrow = Breadcrumb.init(items: ["Very long first", "Middle", "Last"])
    assert Frame.row_text(Breadcrumb.view(narrow, {4, 1}), 1) == "Last"
  end
end
