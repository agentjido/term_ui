defmodule TermUI.SourceConventionsTest do
  use ExUnit.Case, async: true

  alias TermUI.{Cell, Command, Event, Frame, Mouse, Selection, Style}
  alias TermUI.Clipboard.Operation
  alias TermUI.Mouse.Region
  alias TermUI.Widget.Router
  alias TermUI.Widget.Table.Column

  @source_files Path.wildcard("lib/**/*.ex")
  @zoi_boundary_struct_counts %{
    "lib/term_ui/cell.ex" => 1,
    "lib/term_ui/clipboard/operation.ex" => 1,
    "lib/term_ui/command.ex" => 1,
    "lib/term_ui/event.ex" => 6,
    "lib/term_ui/frame.ex" => 1,
    "lib/term_ui/mouse.ex" => 1,
    "lib/term_ui/selection.ex" => 1,
    "lib/term_ui/style.ex" => 1,
    "lib/term_ui/widget/router.ex" => 1,
    "lib/term_ui/widget/table/column.ex" => 1
  }

  test "only public boundary structs derive their shape from Zoi" do
    actual =
      @source_files
      |> Map.new(fn path ->
        count =
          path
          |> File.read!()
          |> String.split("\n")
          |> Enum.count(&String.contains?(&1, "defstruct Zoi.Struct.struct_fields("))

        {path, count}
      end)
      |> Map.reject(fn {_path, count} -> count == 0 end)

    assert actual == @zoi_boundary_struct_counts
  end

  test "boundary schemas define their struct fields and defaults" do
    boundary_schemas()
    |> Enum.each(fn {module, schema} ->
      expected =
        schema
        |> Zoi.Struct.struct_fields()
        |> Map.new(fn
          {field, default} -> {field, default}
          field -> {field, nil}
        end)

      assert Map.from_struct(module.__struct__()) == expected
    end)
  end

  test "public data schemas accept constructor output" do
    values = [
      {Cell.schema(), Cell.new("A")},
      {Cell.schema(), Cell.wide_placeholder(Cell.new("界"))},
      {Style.schema(), Style.new(fg: {:rgb, 1, 2, 3})},
      {Frame.schema(), Frame.new(20, 5, cells: %{{1, 1} => Cell.new("A")}, cursor: {1, 1})},
      {Event.schema(), Event.key(:enter)},
      {Event.schema(), Event.text("x")},
      {Event.schema(), Event.paste("pasted")},
      {Event.schema(), Event.mouse(:press, :left, 4, 5)},
      {Event.schema(), Event.resize(20, 5)},
      {Event.schema(), Event.focus(:gained)},
      {Command.schema(), Command.message(:ready)},
      {Command.schema(), Command.send(self(), :ready)},
      {Command.schema(), Command.timer(10, :ready)},
      {Command.schema(), Command.async(fn -> :ok end)},
      {Command.schema(), Command.clipboard(TermUI.Clipboard.operation("text"))},
      {Command.schema(), Command.shutdown()},
      {Operation.schema(), TermUI.Clipboard.operation("text")},
      {Region.schema(), Mouse.region(:button, 0, 0, 4, 1)},
      {Router.schema(), Router.new(:child, TermUI.Widget.Checkbox, [:child])},
      {Selection.schema(), Selection.new() |> Selection.start(0) |> Selection.extend(1)},
      {Column.schema(), Column.new(:name, "Name")}
    ]

    Enum.each(values, fn {schema, value} ->
      assert {:ok, ^value} = Zoi.parse(schema, value)
    end)
  end

  test "public data schemas reject invalid boundary data" do
    invalid = [
      {Cell.schema(), %Cell{fg: :unknown}},
      {Cell.schema(), %Cell{char: "two", width: 1}},
      {Style.schema(), %Style{fg: {:rgb, 256, 0, 0}}},
      {Style.schema(), %Style{attrs: MapSet.new([:unknown])}},
      {Frame.schema(), %Frame{width: 0, height: 1}},
      {Frame.schema(), %Frame{width: 1, height: 1, cursor: {2, 1}}},
      {Frame.schema(), %Frame{width: 1, height: 1, cells: %{{1, 1} => :not_a_cell}}},
      {Event.schema(), %Event.Resize{width: 0, height: 1}},
      {Command.schema(), %Command{kind: :send, value: {:not_a_pid, :message}}},
      {Command.schema(), %Command{kind: :timer, value: {-1, :message}}},
      {Operation.schema(), %Operation{kind: :write, max_bytes: 0}},
      {Region.schema(), %Region{id: :bad, x: 0, y: 0, width: 0, height: 1}},
      {Router.schema(), %Router{id: :bad, module: :not_a_module, path: [], map_message: :bad}},
      {Selection.schema(), %Selection{anchor: -1}},
      {Column.schema(), %Column{key: :name, label: "Name", align: :diagonal}}
    ]

    Enum.each(invalid, fn {schema, value} ->
      assert {:error, [_error | _rest]} = Zoi.parse(schema, value)
    end)
  end

  test "public boundary constructors reject invalid options" do
    assert_raise ArgumentError, fn -> Style.new(fg: {:rgb, 256, 0, 0}) end
    assert_raise ArgumentError, fn -> Style.new(attrs: [:unknown]) end
    assert_raise ArgumentError, fn -> Mouse.region(:bad, 0, 0, 1, 1, z_index: :front) end
    assert_raise ArgumentError, fn -> Mouse.region(:bad, 0, 0, 1, 1, metadata: :none) end
    assert_raise Zoi.ParseError, fn -> Column.new(:bad, "Bad", width: 0) end
    assert_raise Zoi.ParseError, fn -> Column.new(:bad, "Bad", align: :diagonal) end
  end

  test "normalized event constructors keep their public types and modifiers" do
    events = [
      Event.key(:enter, modifiers: [:ctrl, :ctrl], timestamp: 1),
      Event.text("x", timestamp: 2),
      Event.paste("pasted", timestamp: 3),
      Event.mouse(:press, :left, 4, 5, modifiers: [:shift, :shift], timestamp: 4),
      Event.resize(80, 24, timestamp: 5),
      Event.focus(:gained, timestamp: 6)
    ]

    assert Enum.map(events, &Event.type/1) == [:key, :text, :paste, :mouse, :resize, :focus]
    assert Event.has_modifier?(hd(events), :ctrl)
    assert hd(events).modifiers == [:ctrl]
    assert Enum.at(events, 3).modifiers == [:shift]
  end

  defp boundary_schemas do
    [
      {Cell, Cell.schema()},
      {Operation, Operation.schema()},
      {Command, command_struct_schema()},
      {Event.Key, Event.Key.schema()},
      {Event.Text, Event.Text.schema()},
      {Event.Paste, Event.Paste.schema()},
      {Event.Mouse, Event.Mouse.schema()},
      {Event.Resize, Event.Resize.schema()},
      {Event.Focus, Event.Focus.schema()},
      {Frame, Frame.schema()},
      {Region, Region.schema()},
      {Router, Router.schema()},
      {Selection, Selection.schema()},
      {Style, Style.schema()},
      {Column, Column.schema()}
    ]
  end

  defp command_struct_schema do
    Zoi.struct(Command, %{
      kind: Zoi.enum([:message, :send, :timer, :async, :clipboard, :shutdown]),
      value: Zoi.any()
    })
  end
end
