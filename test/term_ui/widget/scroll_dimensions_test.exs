defmodule TermUI.Widget.ScrollDimensionsTest do
  use ExUnit.Case, async: false

  alias TermUI.{Event, Frame, Widget}
  alias TermUI.Widget.{LogViewer, Router, Stream, StreamWidget, TextInput, Viewport}

  @rows Enum.map(1..20, &Integer.to_string/1)

  test "default page sizes reach the last row in a three row view" do
    for {module, state, maximum} <- [
          {Viewport, Viewport.init(content: @rows), 17},
          {LogViewer, LogViewer.init(entries: @rows, follow: false), 17},
          {Stream, %{Stream.init(items: @rows) | paused: true}, 18}
        ] do
      state =
        Enum.reduce(1..30, state, fn _, state ->
          Widget.update(module, Event.key(:down), state, {10, 3}) |> elem(0)
        end)

      assert offset(state) == maximum
      assert String.trim(Frame.row_text(module.view(state, {10, 3}), 3)) == "20"
      {state, _} = Widget.update(module, Event.key(:up), state, {10, 3})
      assert offset(state) == maximum - 1
    end
  end

  test "size updates preserve update/2 and views stay pure through resize" do
    state = Viewport.init(content: @rows) |> Viewport.set_dimensions({10, 3})

    state =
      Enum.reduce(1..17, state, fn _, state ->
        Viewport.update(Event.key(:down), state) |> elem(0)
      end)

    assert state.scroll_y == 17
    enlarged = Viewport.set_dimensions(state, {10, 8})
    assert enlarged.scroll_y == 12
    assert Frame.row_text(Viewport.view(state, {10, 8}), 1) == "13        "
    assert state.scroll_y == 17
    {shrunk, _} = Viewport.update(Event.key(:down), enlarged, {10, 2})
    assert shrunk.scroll_y == 13
    {paged, _} = Viewport.update(Event.key(:page_down), shrunk)
    assert paged.scroll_y == 18
    assert paged.page_size == 10
  end

  test "scrollbar geometry follows the displayed end and mouse movement uses body height" do
    rows = Enum.map(@rows, &(&1 <> String.duplicate("x", 30)))
    state = Viewport.init(content: rows, scrollbars: :both, follow_end: true)
    geometry = Viewport.geometry(state, {10, 3})
    assert geometry.viewport_height == 2
    assert geometry.viewport_width == 9
    assert geometry.scroll_y == geometry.max_scroll_y
    assert geometry.scroll_y == 18
    {state, _} = Viewport.update(Event.key(:up), state, {10, 3})
    assert state.scroll_y == 17
    refute state.follow_end
    {state, _} = Widget.mouse(Viewport, Event.mouse(:scroll_down, nil, 0, 0), state, {10, 3})
    assert state.scroll_y == 18
    {state, _} = Viewport.mouse(Event.mouse(:press, :left, 9, 1), state, {10, 3})
    assert state.scroll_y == 18
    assert state.dimensions == {10, 3}
    {state, _} = Viewport.update(Event.key(:right), state, {40, 5})
    assert state.scroll_x == 0
  end

  test "follow and live movement start from the visible final page" do
    {log, _} = LogViewer.update(Event.key(:up), LogViewer.init(entries: @rows), {10, 3})
    assert log.offset == 16
    refute log.follow
    log = LogViewer.append(log, "21")
    assert log.offset == 16
    {log, _} = LogViewer.update(Event.key(:end), log, {10, 3})
    assert log.offset == 18
    {log, _} = LogViewer.update(Event.text("f"), log)
    assert log.offset == 18
    refute log.follow
    log = log |> LogViewer.set_filter("2") |> LogViewer.set_dimensions({10, 2})
    assert log.offset == 0

    {stream, _} = Stream.update(Event.key(:up), Stream.init(items: @rows), {10, 3})
    assert stream.offset == 17
    assert stream.paused

    {paused, [{:paused, true}]} =
      Stream.update(Event.text(" "), Stream.init(items: @rows), {10, 3})

    assert paused.offset == 18
    {paused, _} = Stream.update(Event.key(:page_up), paused)
    assert paused.offset == 0
    {resized, _} = Stream.update(Event.key(:down), stream, {10, 8})
    assert resized.offset == 13
    assert %Frame{height: 1} = Stream.view(Stream.set_dimensions(resized, {10, 1}), {10, 1})
  end

  test "stream compatibility and route dispatch carry current dimensions" do
    route = Router.new(:stream, StreamWidget, [:stream])
    parent = %{stream: %{StreamWidget.init(items: @rows) | paused: true}}

    {parent, []} =
      Router.update(route, Event.key(:end), parent, {10, 3})

    assert parent.stream.offset == 18
    assert parent.stream.dimensions == {10, 3}
    assert StreamWidget.set_dimensions(parent.stream, {10, 6}).offset == 15
    input = TextInput.init([])

    assert {input, [{:changed, "x"}]} =
             Widget.update(TextInput, Event.text("x"), input, {10, 1})

    assert input.value == "x"
  end

  test "optional size callback is found in a compiled but unloaded widget" do
    directory =
      Path.join(System.tmp_dir!(), "term-ui-widget-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)

    [{module, beam}] =
      Code.compile_string(
        "defmodule TermUI.UnloadedSizedWidget do\ndef update(_, state), do: {state, [:legacy]}\ndef update(_, state, size), do: {state, [size]}\nend"
      )

    File.write!(Path.join(directory, Atom.to_string(module) <> ".beam"), beam)
    :code.purge(module)
    :code.delete(module)
    Code.prepend_path(directory)

    on_exit(fn ->
      Code.delete_path(directory)
      :code.purge(module)
      :code.delete(module)
      File.rm_rf!(directory)
    end)

    assert :code.is_loaded(module) == false
    assert {:state, [{10, 3}]} = Widget.update(module, Event.key(:down), :state, {10, 3})
  end

  defp offset(%Viewport{scroll_y: offset}), do: offset
  defp offset(%{offset: offset}), do: offset
end
