defmodule TermUI.RoutingAndThemeTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Focus, Shortcut, Style, Theme}

  test "theme values provide variants, merge overrides, and capability conversion" do
    default = Theme.default()
    assert Theme.style(default, :control, :focused).fg == :cyan
    assert Theme.value(default, :spacing) == 1

    base =
      Theme.new(
        name: :base,
        styles: %{panel: %{normal: Style.new(fg: {:rgb, 255, 0, 0}, attrs: [:bold])}},
        values: %{padding: 1}
      )

    override =
      Theme.new(
        name: :review,
        styles: %{panel: %{normal: Style.new(bg: :black)}},
        values: %{padding: 2}
      )

    theme = Theme.merge(base, override) |> Theme.put_value(:border, :rounded)
    panel = Theme.style(theme, :panel)

    assert theme.name == :review
    assert panel.fg == {:rgb, 255, 0, 0}
    assert panel.bg == :black
    assert :bold in panel.attrs
    assert Theme.value(theme, :padding) == 2
    assert Theme.value(theme, :border) == :rounded

    color_256 = Theme.for_capabilities(theme, %{colors: :color_256})
    assert Theme.style(color_256, :panel).fg == {:indexed, 196}

    monochrome = Theme.for_capabilities(theme, %{colors: :monochrome})
    assert Theme.style(monochrome, :panel).fg == nil
    assert Theme.style(monochrome, :panel).bg == nil
    assert :bold in Theme.style(monochrome, :panel).attrs
  end

  test "focus routing skips disabled items and reports pure transitions" do
    focus = Focus.new([:one, %{id: :two, disabled: true}, :three])
    assert Focus.focused?(focus, :one)

    assert {focus, [{:focus_changed, :one, :three}]} = Focus.route(Event.key(:tab), focus)
    assert {focus, [{:focus_changed, :three, :one}]} = Focus.route(Event.key(:tab), focus)

    assert {focus, [{:focus_changed, :one, :three}]} =
             Focus.route(Event.key(:tab, modifiers: [:shift]), focus)

    assert {focus, [{:focus_changed, :three, :one}]} = Focus.route(Event.key(:home), focus)
    assert {focus, [{:focus_changed, :one, :three}]} = Focus.route(Event.key(:end), focus)

    assert {focus, [{:focus_active, false}]} = Focus.route(Event.focus(:lost), focus)
    refute Focus.focused?(focus, :three)
    assert {focus, [{:focus_active, true}]} = Focus.route(Event.focus(:gained), focus)
    assert Focus.focused?(focus, :three)

    focus = focus |> Focus.enable(:two) |> Focus.focus(:two) |> Focus.disable(:two)
    refute focus.current == :two
  end

  test "focus routing can stop at an edge instead of wrapping" do
    focus = Focus.new([:one, :two], current: :two, wrap: false)
    assert Focus.next(focus) == focus
    assert Focus.previous(focus).current == :one
    assert Focus.focus(focus, :missing) == focus
  end

  test "shortcut routing supports chords and timestamp-bounded sequences" do
    shortcuts =
      Shortcut.new(
        [
          {"ctrl+s", :save},
          {["g", "g"], :top},
          {{:enter, [:alt]}, :alternate_submit}
        ],
        timeout: 500
      )

    assert {_shortcuts, [:save]} =
             Shortcut.route(Event.key("s", modifiers: [:ctrl], timestamp: 10), shortcuts)

    assert {shortcuts, []} = Shortcut.route(Event.text("g", timestamp: 100), shortcuts)
    assert length(shortcuts.pending) == 1
    assert {shortcuts, [:top]} = Shortcut.route(Event.text("g", timestamp: 200), shortcuts)
    assert shortcuts.pending == []

    assert {_shortcuts, [:alternate_submit]} =
             Shortcut.route(Event.key(:enter, modifiers: [:alt], timestamp: 300), shortcuts)

    assert {shortcuts, []} = Shortcut.route(Event.text("g", timestamp: 400), shortcuts)
    assert {shortcuts, []} = Shortcut.route(Event.text("g", timestamp: 1_000), shortcuts)
    assert length(shortcuts.pending) == 1
    assert {_shortcuts, [:top]} = Shortcut.route(Event.text("g", timestamp: 1_100), shortcuts)
  end

  test "disabled shortcuts and non-key events do not route" do
    shortcuts = Shortcut.new([{"ctrl+s", :save}]) |> Shortcut.disable()
    assert {^shortcuts, []} = Shortcut.route(Event.key("s", modifiers: [:ctrl]), shortcuts)

    shortcuts = Shortcut.enable(shortcuts)
    assert {^shortcuts, []} = Shortcut.route(Event.resize(80, 24), shortcuts)
    assert Shortcut.reset(shortcuts).pending == []

    assert_raise ArgumentError, fn -> Shortcut.new([{"hyper+s", :save}]) end
    assert_raise ArgumentError, fn -> Theme.new(styles: %{bad: :not_a_style}) end
  end

  test "shortcut fallback restarts a sequence from the current stroke" do
    shortcuts = Shortcut.new([{["g", "g"], :top}, {"x", :single}, {["x", "y"], :xy}])
    assert {shortcuts, []} = Shortcut.route(Event.text("g", timestamp: 10), shortcuts)
    assert {_shortcuts, [:single]} = Shortcut.route(Event.text("x", timestamp: 20), shortcuts)

    shortcuts = Shortcut.new([{["g", "g"], :top}, {["x", "y"], :xy}])
    assert {shortcuts, []} = Shortcut.route(Event.text("g", timestamp: 30), shortcuts)
    assert {shortcuts, []} = Shortcut.route(Event.text("x", timestamp: 40), shortcuts)
    assert length(shortcuts.pending) == 1
    assert {_shortcuts, [:xy]} = Shortcut.route(Event.text("y", timestamp: 50), shortcuts)
  end

  test "shortcut normalization accepts maps and all documented modifier names" do
    bindings = [
      %{sequence: %{key: "Enter", modifiers: [:meta]}, message: :mapped},
      {{"x", [:super]}, :super_x},
      {"alt+shift+meta+super+X", :all_modifiers}
    ]

    shortcuts = Shortcut.new(bindings)

    assert {_state, [:mapped]} =
             Shortcut.route(Event.key(:enter, modifiers: [:meta]), shortcuts)

    assert {_state, [:super_x]} = Shortcut.route(Event.key("x", modifiers: [:super]), shortcuts)

    assert Shortcut.key("alt+shift+meta+super+X") == %{
             key: "X",
             modifiers: [:alt, :meta, :shift, :super]
           }

    assert_raise ArgumentError, ~r/shortcut bindings must contain/, fn -> Shortcut.new([:bad]) end
  end

  test "zero timestamps do not expire an active shortcut sequence" do
    shortcuts = Shortcut.new([{["g", "g"], :top}], timeout: 1)
    assert {shortcuts, []} = Shortcut.route(Event.text("g", timestamp: 10), shortcuts)
    assert {_shortcuts, [:top]} = Shortcut.route(Event.text("g", timestamp: 0), shortcuts)
  end
end
