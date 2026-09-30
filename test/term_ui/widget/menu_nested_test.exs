defmodule TermUI.Widget.MenuNestedTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}
  alias TermUI.Widget.{ContextMenu, Menu}

  test "keyboard opens and closes one explicit submenu path at a time" do
    menu = nested_menu()

    assert {menu, []} = Menu.update(Event.key(:enter), menu)
    assert Menu.open_path(menu) == [:file]
    assert Menu.current(menu).id == :new

    assert {menu, []} = Menu.update(Event.key(:down), menu)
    assert {menu, []} = Menu.update(Event.key(:right), menu)
    assert Menu.open_path(menu) == [:file, :recent]
    assert Menu.current(menu).id == :document

    assert {menu, []} = Menu.update(Event.key(:escape), menu)
    assert Menu.open_path(menu) == [:file]
    assert Menu.current(menu).id == :recent

    assert {menu, []} = Menu.update(Event.key(:left), menu)
    assert Menu.open_path(menu) == []
    assert Menu.current(menu).id == :file

    assert {menu, [:dismissed]} = Menu.update(Event.key(:escape), menu)
    refute menu.visible
  end

  test "mouse and keyboard use the same nested open and action transitions" do
    initial = nested_menu()
    {keyboard, []} = Menu.update(Event.key(:enter), initial)
    {mouse, []} = Menu.mouse(Event.mouse(:release, :left, 1, 1), initial, {30, 8})
    assert mouse == keyboard

    {keyboard, []} = Menu.update(Event.key(:down), keyboard)
    {keyboard, []} = Menu.update(Event.key(:right), keyboard)
    {mouse, []} = Menu.mouse(Event.mouse(:release, :left, 1, 3), mouse, {30, 8})
    assert mouse == keyboard

    assert {keyboard, [{:selected, :document}]} = Menu.update(Event.key(:enter), keyboard)

    assert {mouse, [{:selected, :document}]} =
             Menu.mouse(Event.mouse(:release, :left, 1, 4), mouse, {30, 8})

    assert mouse == keyboard
  end

  test "nested view clips to its frame and all state stays in the menu value" do
    menu = nested_menu() |> Menu.open_submenu()
    {menu, []} = Menu.update(Event.key(:down), menu)
    menu = Menu.open_submenu(menu)
    frame = Menu.view(menu, {12, 4})

    assert %Frame{width: 12, height: 4} = frame
    assert Frame.row_text(frame, 2) =~ "File"
    assert Menu.open_path(menu) == [:file, :recent]
    refute contains_pid?(menu)
  end

  test "overlay placement handles the left, top, right, and bottom edges" do
    assert Menu.fit_overlay({-4, -2}, {20, 8}, {80, 24}) == {0, 0, 20, 8}
    assert Menu.fit_overlay({79, 23}, {20, 8}, {80, 24}) == {60, 16, 20, 8}
    assert Menu.fit_overlay({40, 12}, {100, 40}, {80, 24}) == {0, 0, 80, 24}

    context = ContextMenu.init(items: [Menu.action(:open, "Open")], position: {79, 23})
    assert ContextMenu.placement(context, {20, 8}, {80, 24}) == {60, 16, 20, 8}
  end

  test "submenu placement opens right when possible and left at the right edge" do
    assert Menu.fit_submenu({0, 0, 5, 1}, {10, 5}, {80, 24}) == {5, 0, 10, 5}
    assert Menu.fit_submenu({70, 23, 10, 1}, {20, 8}, {80, 24}) == {50, 16, 20, 8}
    assert Menu.fit_submenu({2, 2, 4, 1}, {100, 40}, {80, 24}) == {0, 0, 80, 24}
  end

  defp nested_menu do
    Menu.init(
      items: [
        Menu.submenu(:file, "File", [
          Menu.action(:new, "New"),
          Menu.submenu(:recent, "Recent", [
            Menu.action(:document, "Document")
          ])
        ]),
        Menu.action(:help, "Help")
      ]
    )
  end

  defp contains_pid?(term) when is_pid(term), do: true

  defp contains_pid?(term) when is_struct(term),
    do: term |> Map.from_struct() |> Map.values() |> Enum.any?(&contains_pid?/1)

  defp contains_pid?(term) when is_map(term),
    do: term |> Map.values() |> Enum.any?(&contains_pid?/1)

  defp contains_pid?(term) when is_list(term), do: Enum.any?(term, &contains_pid?/1)
  defp contains_pid?(_term), do: false
end
