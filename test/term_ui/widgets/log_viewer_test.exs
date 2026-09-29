defmodule TermUI.Widgets.LogViewerTest do
  use ExUnit.Case, async: false

  alias TermUI.Event
  alias TermUI.Theme
  alias TermUI.Widgets.LogViewer

  setup do
    # Start Theme server for color support if not already started
    case Process.whereis(TermUI.Theme) do
      nil -> Theme.start_link(theme: :dark)
      pid -> {:ok, pid}
    end

    :ok
  end

  # Helper to create test area
  defp test_area(width, height) do
    %{x: 0, y: 0, width: width, height: height}
  end

  # Helper to create sample log lines
  defp sample_logs do
    [
      "2024-01-15T10:30:00Z [MyApp.Server] INFO: Server started on port 4000",
      "2024-01-15T10:30:01Z [MyApp.Server] DEBUG: Accepting connections",
      "2024-01-15T10:30:05Z [MyApp.Handler] INFO: New connection from 192.168.1.1",
      "2024-01-15T10:30:10Z [MyApp.Handler] WARNING: Slow response time: 500ms",
      "2024-01-15T10:30:15Z [MyApp.Database] ERROR: Connection pool exhausted",
      "2024-01-15T10:30:20Z [MyApp.Handler] INFO: Request completed successfully",
      "2024-01-15T10:30:25Z [MyApp.Server] CRITICAL: Out of memory",
      "2024-01-15T10:30:30Z [MyApp.Monitor] INFO: Health check passed"
    ]
  end

  describe "new/1" do
    test "creates props with defaults" do
      props = LogViewer.new([])
      assert props.lines == []
      assert props.max_lines == 100_000
      assert props.tail_mode == true
      assert props.wrap_lines == false
      assert props.show_line_numbers == true
      assert props.highlight_levels == true
    end

    test "creates props with custom options" do
      props =
        LogViewer.new(
          lines: sample_logs(),
          max_lines: 1000,
          tail_mode: false,
          wrap_lines: true
        )

      assert length(props.lines) == 8
      assert props.max_lines == 1000
      assert props.tail_mode == false
      assert props.wrap_lines == true
    end
  end

  describe "init/1" do
    test "initializes state from props" do
      props = LogViewer.new(lines: sample_logs())
      {:ok, state} = LogViewer.init(props)

      assert length(state.lines) == 8
      assert state.tail_mode == true
      assert state.bookmarks == MapSet.new()
      assert state.filter == nil
      assert state.search == nil
    end

    test "parses log entries" do
      props = LogViewer.new(lines: sample_logs())
      {:ok, state} = LogViewer.init(props)

      first_line = hd(state.lines)
      assert first_line.level == :info
      assert first_line.source == "MyApp.Server"
      assert first_line.raw =~ "Server started"
    end

    test "starts at bottom in tail mode" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: true)
      {:ok, state} = LogViewer.init(props)

      # Cursor should be at last line
      assert state.cursor == 7
    end

    test "starts at top without tail mode" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)

      assert state.cursor == 0
    end
  end

  describe "level detection" do
    test "detects DEBUG level" do
      props = LogViewer.new(lines: ["DEBUG: test message"])
      {:ok, state} = LogViewer.init(props)
      assert hd(state.lines).level == :debug
    end

    test "detects INFO level" do
      props = LogViewer.new(lines: ["INFO: test message"])
      {:ok, state} = LogViewer.init(props)
      assert hd(state.lines).level == :info
    end

    test "detects WARNING level" do
      props = LogViewer.new(lines: ["WARNING: test message"])
      {:ok, state} = LogViewer.init(props)
      assert hd(state.lines).level == :warning
    end

    test "detects WARN level" do
      props = LogViewer.new(lines: ["WARN: test message"])
      {:ok, state} = LogViewer.init(props)
      assert hd(state.lines).level == :warning
    end

    test "detects ERROR level" do
      props = LogViewer.new(lines: ["ERROR: test message"])
      {:ok, state} = LogViewer.init(props)
      assert hd(state.lines).level == :error
    end

    test "detects CRITICAL level" do
      props = LogViewer.new(lines: ["CRITICAL: test message"])
      {:ok, state} = LogViewer.init(props)
      assert hd(state.lines).level == :critical
    end

    test "returns nil for unknown level" do
      props = LogViewer.new(lines: ["Just a plain message"])
      {:ok, state} = LogViewer.init(props)
      assert hd(state.lines).level == nil
    end
  end

  describe "source detection" do
    test "extracts source from brackets" do
      props = LogViewer.new(lines: ["[MyModule] Some message"])
      {:ok, state} = LogViewer.init(props)
      assert hd(state.lines).source == "MyModule"
    end

    test "extracts source with dots" do
      props = LogViewer.new(lines: ["[MyApp.SubModule.Handler] Message"])
      {:ok, state} = LogViewer.init(props)
      assert hd(state.lines).source == "MyApp.SubModule.Handler"
    end

    test "returns nil when no source" do
      props = LogViewer.new(lines: ["No brackets here"])
      {:ok, state} = LogViewer.init(props)
      assert hd(state.lines).source == nil
    end
  end

  describe "navigation" do
    setup do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)
      {:ok, state: state}
    end

    test "down arrow moves cursor down", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :down}, state)
      assert state.cursor == 1
    end

    test "up arrow moves cursor up", %{state: state} do
      state = %{state | cursor: 5}
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :up}, state)
      assert state.cursor == 4
    end

    test "cursor stops at top", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :up}, state)
      assert state.cursor == 0
    end

    test "cursor stops at bottom", %{state: state} do
      state = %{state | cursor: 7}
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :down}, state)
      assert state.cursor == 7
    end

    test "home jumps to first line", %{state: state} do
      state = %{state | cursor: 5}
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :home}, state)
      assert state.cursor == 0
    end

    test "end jumps to last line", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :end}, state)
      assert state.cursor == 7
    end

    test "page down moves by page", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :page_down}, state)
      # Should move by page size but stop at end
      assert state.cursor == 7
    end

    test "manual navigation disables tail mode" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: true)
      {:ok, state} = LogViewer.init(props)
      assert state.tail_mode == true

      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :up}, state)
      assert state.tail_mode == false
    end
  end

  describe "search" do
    setup do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)
      {:ok, state: state}
    end

    test "/ starts search input mode", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "/"}, state)
      assert state.search_input == ""
    end

    test "typing in search mode accumulates input", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "/"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "E"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "R"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "R"}, state)
      assert state.search_input == "ERR"
    end

    test "escape cancels search input", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "/"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "t"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :escape}, state)
      assert state.search_input == nil
    end

    test "enter executes search", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "/"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "E"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "R"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "R"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :enter}, state)

      assert state.search != nil
      assert state.search_input == nil
      # Should find ERROR line
      assert state.search.matches != []
    end

    test "n goes to next match", %{state: state} do
      # First execute a search
      state = LogViewer.search(state, "INFO")
      initial_match = state.search.current_match

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "n"}, state)
      # Should advance to next match
      assert state.search.current_match != initial_match or length(state.search.matches) == 1
    end

    test "N goes to previous match", %{state: state} do
      state = LogViewer.search(state, "INFO")
      # Go to second match first
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "n"}, state)
      current = state.search.current_match

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "N"}, state)
      # Should go back
      assert state.search.current_match != current or length(state.search.matches) == 1
    end

    test "search finds regex patterns", %{state: state} do
      state = LogViewer.search(state, "\\d{3}ms")
      # Should find "500ms"
      assert state.search.matches != []
    end

    test "escape clears search", %{state: state} do
      state = LogViewer.search(state, "ERROR")
      assert state.search != nil

      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :escape}, state)
      assert state.search == nil
    end
  end

  describe "filtering" do
    setup do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)
      {:ok, state: state}
    end

    test "f starts filter input mode", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "f"}, state)
      assert state.filter_input == ""
    end

    test "enter executes filter", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "f"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "E"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "R"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "R"}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :enter}, state)

      assert state.filter != nil
      assert state.filtered_indices != nil
      # Should show fewer lines than total
      assert length(state.filtered_indices) < length(state.lines)
    end

    test "set_filter filters by level" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)

      filter = %{
        levels: [:error, :critical],
        source: nil,
        pattern: nil,
        bookmarks_only: false
      }

      state = LogViewer.set_filter(state, filter)

      # Should only show ERROR and CRITICAL lines
      assert length(state.filtered_indices) == 2
    end

    test "f clears filter when active", %{state: state} do
      filter = %{
        levels: [:error],
        source: nil,
        pattern: nil,
        bookmarks_only: false
      }

      state = LogViewer.set_filter(state, filter)
      assert state.filter != nil

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "f"}, state)
      assert state.filter == nil
      assert state.filtered_indices == nil
    end

    test "clear_filter removes filter" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)

      filter = %{levels: [:error], source: nil, pattern: nil, bookmarks_only: false}
      state = LogViewer.set_filter(state, filter)
      assert state.filter != nil

      state = LogViewer.clear_filter(state)
      assert state.filter == nil
    end
  end

  describe "bookmarking" do
    setup do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)
      {:ok, state: state}
    end

    test "b toggles bookmark on current line", %{state: state} do
      assert MapSet.size(state.bookmarks) == 0

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "b"}, state)
      assert MapSet.member?(state.bookmarks, 0)

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "b"}, state)
      refute MapSet.member?(state.bookmarks, 0)
    end

    test "B jumps to next bookmark", %{state: state} do
      # Add some bookmarks
      state = %{state | bookmarks: MapSet.new([2, 5])}

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "B"}, state)
      assert state.cursor == 2

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "B"}, state)
      assert state.cursor == 5

      # Should wrap around
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "B"}, state)
      assert state.cursor == 2
    end

    test "get_bookmarks returns sorted list" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)

      state = %{state | bookmarks: MapSet.new([5, 2, 7])}
      bookmarks = LogViewer.get_bookmarks(state)

      assert bookmarks == [2, 5, 7]
    end
  end

  describe "tail mode" do
    test "t toggles tail mode" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: true)
      {:ok, state} = LogViewer.init(props)
      assert state.tail_mode == true

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "t"}, state)
      assert state.tail_mode == false

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "t"}, state)
      assert state.tail_mode == true
    end

    test "enabling tail mode jumps to end" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)
      assert state.cursor == 0

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "t"}, state)
      assert state.cursor == 7
    end

    test "tail_mode? returns current state" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: true)
      {:ok, state} = LogViewer.init(props)
      assert LogViewer.tail_mode?(state) == true

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "t"}, state)
      assert LogViewer.tail_mode?(state) == false
    end
  end

  describe "wrap mode" do
    test "w toggles wrap mode" do
      props = LogViewer.new(lines: sample_logs(), wrap_lines: false)
      {:ok, state} = LogViewer.init(props)
      assert state.wrap_lines == false

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "w"}, state)
      assert state.wrap_lines == true

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: "w"}, state)
      assert state.wrap_lines == false
    end
  end

  describe "selection" do
    setup do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)
      {:ok, state: state}
    end

    test "space starts selection", %{state: state} do
      assert state.selection_start == nil

      {:ok, state} = LogViewer.handle_event(%Event.Key{char: " "}, state)
      assert state.selection_start == 0
      assert state.selection_end == 0
    end

    test "space extends selection", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: " "}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :down}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :down}, state)
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: " "}, state)

      assert state.selection_start == 0
      assert state.selection_end == 2
    end

    test "escape clears selection", %{state: state} do
      {:ok, state} = LogViewer.handle_event(%Event.Key{char: " "}, state)
      assert state.selection_start != nil

      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :escape}, state)
      assert state.selection_start == nil
      assert state.selection_end == nil
    end

    test "get_selected_text returns selected lines" do
      props = LogViewer.new(lines: ["Line 1", "Line 2", "Line 3"], tail_mode: false)
      {:ok, state} = LogViewer.init(props)

      state = %{state | selection_start: 0, selection_end: 1}
      text = LogViewer.get_selected_text(state)

      assert text == "Line 1\nLine 2"
    end

    test "get_selected_text handles reverse selection" do
      props = LogViewer.new(lines: ["Line 1", "Line 2", "Line 3"], tail_mode: false)
      {:ok, state} = LogViewer.init(props)

      state = %{state | selection_start: 2, selection_end: 0}
      text = LogViewer.get_selected_text(state)

      assert text == "Line 1\nLine 2\nLine 3"
    end
  end

  describe "add_line/2 and add_lines/2" do
    test "add_line appends single line" do
      props = LogViewer.new(lines: ["Line 1"])
      {:ok, state} = LogViewer.init(props)

      state = LogViewer.add_line(state, "Line 2")
      assert length(state.lines) == 2
      assert List.last(state.lines).raw == "Line 2"
    end

    test "add_lines appends multiple lines" do
      props = LogViewer.new(lines: ["Line 1"])
      {:ok, state} = LogViewer.init(props)

      state = LogViewer.add_lines(state, ["Line 2", "Line 3"])
      assert length(state.lines) == 3
    end

    test "add_lines respects max_lines" do
      props = LogViewer.new(lines: ["Line 1", "Line 2"], max_lines: 3)
      {:ok, state} = LogViewer.init(props)

      state = LogViewer.add_lines(state, ["Line 3", "Line 4"])
      assert length(state.lines) == 3
      # Oldest line should be dropped
      refute Enum.any?(state.lines, &(&1.raw == "Line 1"))
    end

    test "add_lines auto-scrolls in tail mode" do
      props = LogViewer.new(lines: ["Line 1"], tail_mode: true)
      {:ok, state} = LogViewer.init(props)

      state = LogViewer.add_lines(state, ["Line 2", "Line 3"])
      # Cursor should be at last line
      assert state.cursor == 2
    end
  end

  describe "clear/1" do
    test "removes all lines" do
      props = LogViewer.new(lines: sample_logs())
      {:ok, state} = LogViewer.init(props)

      state = LogViewer.clear(state)
      assert state.lines == []
      assert state.cursor == 0
    end

    test "clears selection and search" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)

      state = LogViewer.search(state, "ERROR")
      state = %{state | selection_start: 0, selection_end: 2}

      state = LogViewer.clear(state)
      assert state.search == nil
      assert state.selection_start == nil
    end
  end

  describe "line_count/1 and visible_line_count/1" do
    test "line_count returns total lines" do
      props = LogViewer.new(lines: sample_logs())
      {:ok, state} = LogViewer.init(props)

      assert LogViewer.line_count(state) == 8
    end

    test "visible_line_count returns filtered count" do
      props = LogViewer.new(lines: sample_logs())
      {:ok, state} = LogViewer.init(props)

      assert LogViewer.visible_line_count(state) == 8

      filter = %{levels: [:error], source: nil, pattern: nil, bookmarks_only: false}
      state = LogViewer.set_filter(state, filter)

      assert LogViewer.visible_line_count(state) == 1
    end
  end

  describe "rendering" do
    test "render produces output" do
      props = LogViewer.new(lines: sample_logs())
      {:ok, state} = LogViewer.init(props)

      render = LogViewer.render(state, test_area(80, 24))
      assert render != nil
    end

    test "render handles empty lines" do
      props = LogViewer.new(lines: [])
      {:ok, state} = LogViewer.init(props)

      render = LogViewer.render(state, test_area(80, 24))
      assert render != nil
    end

    test "render handles very long lines" do
      long_line = String.duplicate("X", 500)
      props = LogViewer.new(lines: [long_line])
      {:ok, state} = LogViewer.init(props)

      render = LogViewer.render(state, test_area(80, 24))
      assert render != nil
    end
  end

  describe "goto_line/2" do
    test "jumps to specific line" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)

      {:ok, state} = LogViewer.goto_line(state, 5)
      assert state.cursor == 5
    end

    test "clamps to valid range" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: false)
      {:ok, state} = LogViewer.init(props)

      {:ok, state} = LogViewer.goto_line(state, 100)
      assert state.cursor == 7

      {:ok, state} = LogViewer.goto_line(state, -5)
      assert state.cursor == 0
    end

    test "disables tail mode" do
      props = LogViewer.new(lines: sample_logs(), tail_mode: true)
      {:ok, state} = LogViewer.init(props)

      {:ok, state} = LogViewer.goto_line(state, 2)
      assert state.tail_mode == false
    end
  end

  describe "edge cases" do
    test "handles empty lines list" do
      props = LogViewer.new(lines: [])
      {:ok, state} = LogViewer.init(props)

      # Navigation should not crash
      {:ok, _state} = LogViewer.handle_event(%Event.Key{key: :down}, state)
      {:ok, _state} = LogViewer.handle_event(%Event.Key{key: :up}, state)
    end

    test "handles single line" do
      props = LogViewer.new(lines: ["Single line"])
      {:ok, state} = LogViewer.init(props)

      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :down}, state)
      assert state.cursor == 0

      {:ok, state} = LogViewer.handle_event(%Event.Key{key: :up}, state)
      assert state.cursor == 0
    end

    test "unhandled event returns unchanged state" do
      props = LogViewer.new(lines: sample_logs())
      {:ok, state} = LogViewer.init(props)

      {:ok, new_state} = LogViewer.handle_event(%Event.Key{key: :f1}, state)
      assert new_state == state
    end
  end
end
