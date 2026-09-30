defmodule TermUI.Widget.ToastManagerTest do
  use ExUnit.Case, async: true

  alias TermUI.Command
  alias TermUI.Widget.Toast
  alias TermUI.Widget.Toast.Manager

  test "explicit timer commands expire toasts in timer order" do
    manager = Manager.new(id: :primary, limit: 3)

    assert {manager, [%Command{kind: :timer, value: {100, slow_message}}]} =
             Manager.add_with_timer(manager, "Slow", :info, id: :slow, duration: 100)

    assert {manager, [%Command{kind: :timer, value: {10, fast_message}}]} =
             Manager.add_with_timer(manager, "Fast", :warning, id: :fast, duration: 10)

    assert Enum.map(manager.toasts, & &1.id) == [:fast, :slow]

    manager = Manager.expire(manager, fast_message)
    assert Enum.map(manager.toasts, & &1.id) == [:slow]

    manager = Manager.expire(manager, slow_message)
    assert manager.toasts == []
  end

  test "replacement invalidates the old timer token" do
    manager = Manager.new(id: :primary)

    {manager, [%Command{value: {_delay, old_message}}]} =
      Manager.add_with_timer(manager, "Old", :info, id: :notice, duration: 100)

    {manager, [%Command{value: {20, new_message}}]} =
      Manager.replace_with_timer(manager, :notice, "New", :success, duration: 20)

    assert [%Toast{id: :notice, message: "New", type: :success}] = manager.toasts
    assert Manager.expire(manager, old_message) == manager
    assert Manager.expire(manager, new_message).toasts == []
  end

  test "manual dismissal makes a late timer safe" do
    manager = Manager.new(id: :primary)

    {manager, [%Command{value: {_delay, message}}]} =
      Manager.add_with_timer(manager, "Dismiss", :info, id: :notice, duration: 10)

    manager = Manager.dismiss(manager, :notice)
    assert manager.toasts == []
    assert Manager.dismiss(manager, :missing) == manager
    assert Manager.expire(manager, message) == manager
  end

  test "count limits remove older toasts and ignore their pending timers" do
    manager = Manager.new(id: :primary, limit: 2)

    {manager, [%Command{value: {_delay, first_message}}]} =
      Manager.add_with_timer(manager, "One", :info, id: :one)

    {manager, _commands} = Manager.add_with_timer(manager, "Two", :info, id: :two)
    {manager, _commands} = Manager.add_with_timer(manager, "Three", :info, id: :three)

    assert Enum.map(manager.toasts, & &1.id) == [:three, :two]
    assert Manager.expire(manager, first_message) == manager

    manager = Manager.set_limit(manager, 1)
    assert manager.limit == 1
    assert Enum.map(manager.toasts, & &1.id) == [:three]
  end

  test "infinite toasts return no timer command" do
    manager = Manager.new(id: :primary)
    assert {manager, []} = Manager.add_with_timer(manager, "Pinned", :info, duration: :infinity)
    assert Manager.tick(manager, 10_000) == manager
  end

  test "independent toast areas ignore each other's timer messages" do
    left = Manager.new(id: :left)
    right = Manager.new(id: :right)

    {left, [%Command{value: {_delay, left_message}}]} =
      Manager.add_with_timer(left, "Left", :info, id: :notice)

    {right, [%Command{value: {_delay, right_message}}]} =
      Manager.add_with_timer(right, "Right", :info, id: :notice)

    assert Manager.expire(right, left_message) == right
    assert Manager.expire(left, right_message) == left
    assert Manager.expire(left, left_message).toasts == []
    assert Manager.expire(right, right_message).toasts == []
    refute is_pid(left.id)
    refute is_pid(right.id)
  end

  test "the existing add and tick path stays available" do
    manager = Manager.new(limit: 2) |> Manager.add("One", :error, id: :one, duration: 5)
    assert [%Toast{id: :one}] = manager.toasts
    assert Manager.tick(manager, 4).toasts != []
    assert Manager.tick(manager, 5).toasts == []
  end
end
