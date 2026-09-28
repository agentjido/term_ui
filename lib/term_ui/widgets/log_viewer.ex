defmodule TermUI.Widgets.LogViewer do
  @moduledoc """
  LogViewer widget for displaying real-time logs with virtual scrolling.

  LogViewer efficiently displays large log files (millions of lines) using
  virtual scrolling, with support for search, filtering, syntax highlighting,
  and bookmarking.

  ## Usage

      LogViewer.new(
        lines: log_lines,
        tail_mode: true,
        highlight_levels: true
      )

  ## Features

  - Virtual scrolling for efficient rendering of large datasets
  - Tail mode for live log monitoring
  - Search with regex support and match highlighting
  - Syntax highlighting for log levels and timestamps
  - Filtering by level, source, or pattern
  - Line bookmarking
  - Selection and copy functionality
  - Wrap/truncate toggle for long lines

  ## Keyboard Controls

  - Up/Down: Move cursor
  - PageUp/PageDown: Scroll by page
  - Home/End: Jump to first/last line
  - /: Start search
  - n/N: Next/previous search match
  - f: Toggle filter mode
  - b: Toggle bookmark on current line
  - B: Jump to next bookmark
  - t: Toggle tail mode
  - w: Toggle wrap mode
  - Space: Start/extend selection
  - Escape: Clear search/filter/selection
  """

  use TermUI.StatefulComponent

  alias TermUI.Event
  alias TermUI.Renderer.Style
  alias TermUI.Theme

  # Dialyzer: Suppress opaque type warnings for Style helpers and contract warnings for specific map types
  @dialyzer {:nowarn_function,
             fg_semantic: 1,
             fg_color: 1,
             fg_dim_semantic: 1,
             fg_bg_semantic: 2,
             new: 1,
             add_line: 2,
             clear: 1,
             clear_filter: 1}

  @type log_level ::
          :debug | :info | :notice | :warning | :error | :critical | :alert | :emergency

  @type log_entry :: %{
          id: non_neg_integer(),
          timestamp: DateTime.t() | nil,
          level: log_level() | nil,
          source: String.t() | nil,
          message: String.t(),
          raw: String.t()
        }

  @type filter_spec :: %{
          levels: [log_level()] | nil,
          source: String.t() | nil,
          pattern: Regex.t() | String.t() | nil,
          bookmarks_only: boolean()
        }

  @type search_state :: %{
          pattern: Regex.t() | String.t(),
          matches: [non_neg_integer()],
          current_match: non_neg_integer(),
          highlight: boolean()
        }

  # NOTE: Regex patterns defined as functions rather than module attributes because
  # compiled Regex structs contain references that cannot be injected into function bodies.
  defp level_patterns do
    [
      {:emergency, ~r/\b(EMERGENCY|EMERG)\b/i},
      {:alert, ~r/\b(ALERT)\b/i},
      {:critical, ~r/\b(CRITICAL|CRIT|FATAL)\b/i},
      {:error, ~r/\b(ERROR|ERR)\b/i},
      {:warning, ~r/\b(WARNING|WARN)\b/i},
      {:notice, ~r/\b(NOTICE)\b/i},
      {:info, ~r/\b(INFO)\b/i},
      {:debug, ~r/\b(DEBUG|DBG)\b/i}
    ]
  end

  defp timestamp_pattern,
    do: ~r/\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?/

  defp source_pattern, do: ~r/\[([^\]]+)\]/

  @page_size 20

  # ----------------------------------------------------------------------------
  # Style Helper Functions
  # ----------------------------------------------------------------------------

  @spec fg_semantic(atom()) :: Style.t()
  defp fg_semantic(color) when is_atom(color),
    do: Style.new() |> Style.fg(color)

  @spec fg_color(atom()) :: Style.t()
  defp fg_color(color) when is_atom(color),
    do: Style.new() |> Style.fg(color)

  @spec fg_dim_semantic(atom()) :: Style.t()
  defp fg_dim_semantic(color) when is_atom(color),
    do: Style.new() |> Style.fg(color) |> Style.dim()

  @spec fg_bg_semantic(atom(), atom()) :: Style.t()
  defp fg_bg_semantic(fg, bg) when is_atom(fg) and is_atom(bg),
    do: Style.new() |> Style.fg(fg) |> Style.bg(bg)

  # ----------------------------------------------------------------------------
  # Props
  # ----------------------------------------------------------------------------

  @doc """
  Creates new LogViewer widget props.

  ## Options

  - `:lines` - Initial log lines (strings or log entries)
  - `:max_lines` - Maximum lines to keep in buffer (default: 100_000)
  - `:tail_mode` - Auto-scroll to new lines (default: true)
  - `:wrap_lines` - Wrap long lines (default: false)
  - `:show_line_numbers` - Display line numbers (default: true)
  - `:show_timestamps` - Display timestamps column (default: false)
  - `:show_levels` - Display level column (default: true)
  - `:highlight_levels` - Color-code by level (default: true)
  - `:on_select` - Callback when lines are selected
  - `:on_copy` - Callback when copy is requested
  - `:parser` - Custom log parser function
  """
  @spec new(keyword()) :: map()
  def new(opts) do
    %{
      lines: Keyword.get(opts, :lines, []),
      max_lines: Keyword.get(opts, :max_lines, 100_000),
      tail_mode: Keyword.get(opts, :tail_mode, true),
      wrap_lines: Keyword.get(opts, :wrap_lines, false),
      show_line_numbers: Keyword.get(opts, :show_line_numbers, true),
      show_timestamps: Keyword.get(opts, :show_timestamps, false),
      show_levels: Keyword.get(opts, :show_levels, true),
      highlight_levels: Keyword.get(opts, :highlight_levels, true),
      on_select: Keyword.get(opts, :on_select),
      on_copy: Keyword.get(opts, :on_copy),
      parser: Keyword.get(opts, :parser, &default_parser/1)
    }
  end

  # ----------------------------------------------------------------------------
  # StatefulComponent Callbacks
  # ----------------------------------------------------------------------------

  @impl true
  def init(props) do
    # Parse initial lines
    lines =
      props.lines
      |> Enum.with_index()
      |> Enum.map(fn {line, idx} ->
        parse_line(line, idx, props.parser)
      end)

    state = %{
      lines: lines,
      max_lines: props.max_lines,
      scroll_offset: 0,
      cursor: 0,
      selection_start: nil,
      selection_end: nil,
      bookmarks: MapSet.new(),
      filter: nil,
      filtered_indices: nil,
      search: nil,
      search_input: nil,
      filter_input: nil,
      tail_mode: props.tail_mode,
      wrap_lines: props.wrap_lines,
      show_line_numbers: props.show_line_numbers,
      show_timestamps: props.show_timestamps,
      show_levels: props.show_levels,
      highlight_levels: props.highlight_levels,
      on_select: props.on_select,
      on_copy: props.on_copy,
      parser: props.parser,
      viewport_height: 20,
      viewport_width: 80,
      last_area: nil
    }

    # Start at bottom if tail mode
    state =
      if props.tail_mode and lines != [] do
        %{
          state
          | cursor: length(lines) - 1,
            scroll_offset: max(0, length(lines) - state.viewport_height)
        }
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def handle_event(%Event.Key{key: :up}, state)
      when state.search_input == nil and state.filter_input == nil do
    move_cursor(state, -1)
  end

  def handle_event(%Event.Key{key: :down}, state)
      when state.search_input == nil and state.filter_input == nil do
    move_cursor(state, 1)
  end

  def handle_event(%Event.Key{key: :page_up}, state)
      when state.search_input == nil and state.filter_input == nil do
    move_cursor(state, -@page_size)
  end

  def handle_event(%Event.Key{key: :page_down}, state)
      when state.search_input == nil and state.filter_input == nil do
    move_cursor(state, @page_size)
  end

  def handle_event(%Event.Key{key: :home}, state)
      when state.search_input == nil and state.filter_input == nil do
    goto_line(state, 0)
  end

  def handle_event(%Event.Key{key: :end}, state)
      when state.search_input == nil and state.filter_input == nil do
    visible_lines = get_visible_line_indices(state)
    goto_line(state, length(visible_lines) - 1)
  end

  # Start search
  def handle_event(%Event.Key{char: "/"}, state)
      when state.search_input == nil and state.filter_input == nil do
    {:ok, %{state | search_input: ""}}
  end

  # Search input mode
  def handle_event(%Event.Key{key: :enter}, state) when state.search_input != nil do
    execute_search(state, state.search_input)
  end

  def handle_event(%Event.Key{key: :escape}, state) when state.search_input != nil do
    {:ok, %{state | search_input: nil}}
  end

  def handle_event(%Event.Key{key: :backspace}, state) when state.search_input != nil do
    input = String.slice(state.search_input, 0..-2//1)
    {:ok, %{state | search_input: input}}
  end

  def handle_event(%Event.Key{char: char}, state)
      when state.search_input != nil and char != nil do
    {:ok, %{state | search_input: state.search_input <> char}}
  end

  # Filter input mode
  def handle_event(%Event.Key{key: :enter}, state) when state.filter_input != nil do
    execute_filter(state, state.filter_input)
  end

  def handle_event(%Event.Key{key: :escape}, state) when state.filter_input != nil do
    {:ok, %{state | filter_input: nil}}
  end

  def handle_event(%Event.Key{key: :backspace}, state) when state.filter_input != nil do
    input = String.slice(state.filter_input, 0..-2//1)
    {:ok, %{state | filter_input: input}}
  end

  def handle_event(%Event.Key{char: char}, state)
      when state.filter_input != nil and char != nil do
    {:ok, %{state | filter_input: state.filter_input <> char}}
  end

  # Next/previous search match
  def handle_event(%Event.Key{char: "n"}, state)
      when state.search != nil and state.search_input == nil do
    next_search_match(state, 1)
  end

  def handle_event(%Event.Key{char: "N"}, state)
      when state.search != nil and state.search_input == nil do
    next_search_match(state, -1)
  end

  # Toggle filter mode
  def handle_event(%Event.Key{char: "f"}, state)
      when state.search_input == nil and state.filter_input == nil do
    if state.filter do
      # Clear filter
      {:ok, %{state | filter: nil, filtered_indices: nil}}
    else
      # Start filter input
      {:ok, %{state | filter_input: ""}}
    end
  end

  # Toggle bookmark
  def handle_event(%Event.Key{char: "b"}, state)
      when state.search_input == nil and state.filter_input == nil do
    line_idx = get_actual_line_index(state, state.cursor)

    bookmarks =
      if MapSet.member?(state.bookmarks, line_idx) do
        MapSet.delete(state.bookmarks, line_idx)
      else
        MapSet.put(state.bookmarks, line_idx)
      end

    {:ok, %{state | bookmarks: bookmarks}}
  end

  # Jump to next bookmark
  def handle_event(%Event.Key{char: "B"}, state)
      when state.search_input == nil and state.filter_input == nil do
    jump_to_next_bookmark(state)
  end

  # Toggle tail mode
  def handle_event(%Event.Key{char: "t"}, state)
      when state.search_input == nil and state.filter_input == nil do
    state = %{state | tail_mode: not state.tail_mode}

    state =
      if state.tail_mode do
        # Jump to end when enabling tail mode
        visible_lines = get_visible_line_indices(state)
        last = max(0, length(visible_lines) - 1)

        %{
          state
          | cursor: last,
            scroll_offset: max(0, length(visible_lines) - state.viewport_height)
        }
      else
        state
      end

    {:ok, state}
  end

  # Toggle wrap mode
  def handle_event(%Event.Key{char: "w"}, state)
      when state.search_input == nil and state.filter_input == nil do
    {:ok, %{state | wrap_lines: not state.wrap_lines}}
  end

  # Selection with Space
  def handle_event(%Event.Key{char: " "}, state)
      when state.search_input == nil and state.filter_input == nil do
    line_idx = get_actual_line_index(state, state.cursor)

    state =
      cond do
        state.selection_start == nil ->
          # Start selection
          %{state | selection_start: line_idx, selection_end: line_idx}

        state.selection_start != nil ->
          # Extend selection
          %{state | selection_end: line_idx}
      end

    {:ok, state}
  end

  # Copy with 'y'
  def handle_event(%Event.Key{char: "y"}, state)
      when state.search_input == nil and state.filter_input == nil do
    if state.selection_start != nil and state.on_copy do
      text = get_selected_text(state)
      state.on_copy.(text)
    end

    {:ok, state}
  end

  # Clear search/filter/selection with Escape
  def handle_event(%Event.Key{key: :escape}, state)
      when state.search_input == nil and state.filter_input == nil do
    state =
      cond do
        state.selection_start != nil ->
          %{state | selection_start: nil, selection_end: nil}

        state.search != nil ->
          %{state | search: nil}

        state.filter != nil ->
          %{state | filter: nil, filtered_indices: nil}

        true ->
          state
      end

    {:ok, state}
  end

  def handle_event(_event, state) do
    {:ok, state}
  end

  @impl true
  def render(state, area) do
    # Update viewport dimensions
    state = %{
      state
      | viewport_height: area.height - 2,
        viewport_width: area.width,
        last_area: area
    }

    visible_lines = get_visible_line_indices(state)
    total_lines = length(visible_lines)

    # Calculate visible range
    start_idx = state.scroll_offset
    end_idx = min(start_idx + state.viewport_height, total_lines)

    # Build line renders
    line_renders =
      start_idx..(end_idx - 1)//1
      |> Enum.map(fn visible_idx ->
        actual_idx = Enum.at(visible_lines, visible_idx, visible_idx)
        line = Enum.at(state.lines, actual_idx)

        if line do
          render_line(state, line, visible_idx, actual_idx)
        else
          text("", nil)
        end
      end)

    # Add status bar
    status_bar = render_status_bar(state, total_lines)

    # Add input bar if in input mode
    input_bar = render_input_bar(state)

    stack(:vertical, line_renders ++ [status_bar] ++ input_bar)
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Adds a single log line to the viewer.
  """
  @spec add_line(map(), String.t() | log_entry()) :: map()
  def add_line(state, line) do
    add_lines(state, [line])
  end

  @doc """
  Adds multiple log lines to the viewer.
  """
  @spec add_lines(map(), [String.t() | log_entry()]) :: map()
  def add_lines(state, new_lines) do
    base_id = length(state.lines)

    parsed_lines =
      new_lines
      |> Enum.with_index()
      |> Enum.map(fn {line, idx} ->
        parse_line(line, base_id + idx, state.parser)
      end)

    lines = state.lines ++ parsed_lines

    # Trim if exceeds max
    lines =
      if length(lines) > state.max_lines do
        Enum.drop(lines, length(lines) - state.max_lines)
      else
        lines
      end

    # Update filtered indices if filter is active
    state =
      if state.filter do
        filtered = filter_lines(lines, state.filter, state.bookmarks)
        %{state | filtered_indices: filtered}
      else
        state
      end

    # Auto-scroll if in tail mode
    state =
      if state.tail_mode do
        visible_lines = get_visible_line_indices(%{state | lines: lines})
        new_cursor = max(0, length(visible_lines) - 1)
        new_offset = max(0, length(visible_lines) - state.viewport_height)
        %{state | cursor: new_cursor, scroll_offset: new_offset}
      else
        state
      end

    %{state | lines: lines}
  end

  @doc """
  Clears all log lines.
  """
  @spec clear(map()) :: map()
  def clear(state) do
    %{
      state
      | lines: [],
        cursor: 0,
        scroll_offset: 0,
        selection_start: nil,
        selection_end: nil,
        search: nil,
        filtered_indices: nil
    }
  end

  @doc """
  Gets the currently selected text.
  """
  @spec get_selected_text(map()) :: String.t()
  def get_selected_text(state) do
    if state.selection_start != nil and state.selection_end != nil do
      start_idx = min(state.selection_start, state.selection_end)
      end_idx = max(state.selection_start, state.selection_end)

      state.lines
      |> Enum.slice(start_idx..end_idx)
      |> Enum.map_join("\n", & &1.raw)
    else
      ""
    end
  end

  @doc """
  Sets a filter on the log viewer.
  """
  @spec set_filter(map(), filter_spec()) :: map()
  def set_filter(state, filter) do
    filtered = filter_lines(state.lines, filter, state.bookmarks)
    %{state | filter: filter, filtered_indices: filtered, cursor: 0, scroll_offset: 0}
  end

  @doc """
  Clears the current filter.
  """
  @spec clear_filter(map()) :: map()
  def clear_filter(state) do
    %{state | filter: nil, filtered_indices: nil}
  end

  @doc """
  Starts a search with the given pattern.
  """
  @spec search(map(), String.t()) :: map()
  def search(state, pattern) do
    {:ok, state} = execute_search(state, pattern)
    state
  end

  @doc """
  Jumps to a specific line number.
  """
  @spec goto_line(map(), non_neg_integer()) :: {:ok, map()}
  def goto_line(state, line_num) do
    visible_lines = get_visible_line_indices(state)
    max_line = max(0, length(visible_lines) - 1)
    new_cursor = max(0, min(line_num, max_line))

    # Adjust scroll to keep cursor visible
    scroll_offset =
      cond do
        new_cursor < state.scroll_offset ->
          new_cursor

        new_cursor >= state.scroll_offset + state.viewport_height ->
          new_cursor - state.viewport_height + 1

        true ->
          state.scroll_offset
      end

    # Disable tail mode on manual navigation
    {:ok, %{state | cursor: new_cursor, scroll_offset: scroll_offset, tail_mode: false}}
  end

  @doc """
  Gets the list of bookmarked line indices.
  """
  @spec get_bookmarks(map()) :: [non_neg_integer()]
  def get_bookmarks(state) do
    MapSet.to_list(state.bookmarks) |> Enum.sort()
  end

  @doc """
  Gets the current search matches.
  """
  @spec get_search_matches(map()) :: [non_neg_integer()]
  def get_search_matches(state) do
    if state.search do
      state.search.matches
    else
      []
    end
  end

  @doc """
  Checks if tail mode is enabled.
  """
  @spec tail_mode?(map()) :: boolean()
  def tail_mode?(state), do: state.tail_mode

  @doc """
  Gets the total number of lines.
  """
  @spec line_count(map()) :: non_neg_integer()
  def line_count(state), do: length(state.lines)

  @doc """
  Gets the number of visible lines (after filtering).
  """
  @spec visible_line_count(map()) :: non_neg_integer()
  def visible_line_count(state) do
    length(get_visible_line_indices(state))
  end

  # ----------------------------------------------------------------------------
  # Private: Navigation
  # ----------------------------------------------------------------------------

  defp move_cursor(state, delta) do
    visible_lines = get_visible_line_indices(state)
    max_cursor = max(0, length(visible_lines) - 1)
    new_cursor = max(0, min(state.cursor + delta, max_cursor))

    # Adjust scroll to keep cursor visible
    scroll_offset =
      cond do
        new_cursor < state.scroll_offset ->
          new_cursor

        new_cursor >= state.scroll_offset + state.viewport_height ->
          new_cursor - state.viewport_height + 1

        true ->
          state.scroll_offset
      end

    # Disable tail mode on manual navigation (except down at end)
    tail_mode =
      if delta < 0 do
        false
      else
        state.tail_mode
      end

    {:ok, %{state | cursor: new_cursor, scroll_offset: scroll_offset, tail_mode: tail_mode}}
  end

  defp get_actual_line_index(state, visible_cursor) do
    visible_lines = get_visible_line_indices(state)
    Enum.at(visible_lines, visible_cursor, visible_cursor)
  end

  defp get_visible_line_indices(state) do
    if state.filtered_indices do
      state.filtered_indices
    else
      Enum.to_list(0..(length(state.lines) - 1)//1)
    end
  end

  # ----------------------------------------------------------------------------
  # Private: Search
  # ----------------------------------------------------------------------------

  defp execute_search(state, pattern) when pattern == "" do
    {:ok, %{state | search: nil, search_input: nil}}
  end

  defp execute_search(state, pattern) do
    regex =
      case Regex.compile(pattern, "i") do
        {:ok, r} -> r
        {:error, _} -> ~r/#{Regex.escape(pattern)}/i
      end

    matches =
      state.lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _idx} ->
        Regex.match?(regex, line.raw)
      end)
      |> Enum.map(fn {_line, idx} -> idx end)

    search_state = %{
      pattern: regex,
      matches: matches,
      current_match: 0,
      highlight: true
    }

    # Jump to first match if any
    state =
      if matches != [] do
        first_match = hd(matches)
        visible_lines = get_visible_line_indices(state)
        visible_idx = Enum.find_index(visible_lines, &(&1 == first_match)) || 0

        %{
          state
          | cursor: visible_idx,
            scroll_offset: max(0, visible_idx - div(state.viewport_height, 2))
        }
      else
        state
      end

    {:ok, %{state | search: search_state, search_input: nil}}
  end

  defp next_search_match(state, direction) do
    if state.search && state.search.matches != [] do
      matches = state.search.matches
      current = state.search.current_match
      next_idx = rem(current + direction + length(matches), length(matches))
      match_line = Enum.at(matches, next_idx)

      visible_lines = get_visible_line_indices(state)
      visible_idx = Enum.find_index(visible_lines, &(&1 == match_line)) || 0

      search = %{state.search | current_match: next_idx}
      new_scroll = max(0, visible_idx - div(state.viewport_height, 2))

      {:ok,
       %{state | search: search, cursor: visible_idx, scroll_offset: new_scroll, tail_mode: false}}
    else
      {:ok, state}
    end
  end

  # ----------------------------------------------------------------------------
  # Private: Filtering
  # ----------------------------------------------------------------------------

  defp execute_filter(state, pattern) when pattern == "" do
    {:ok, %{state | filter: nil, filtered_indices: nil, filter_input: nil}}
  end

  defp execute_filter(state, pattern) do
    # Simple pattern filter on message
    regex =
      case Regex.compile(pattern, "i") do
        {:ok, r} -> r
        {:error, _} -> ~r/#{Regex.escape(pattern)}/i
      end

    filter = %{
      levels: nil,
      source: nil,
      pattern: regex,
      bookmarks_only: false
    }

    filtered = filter_lines(state.lines, filter, state.bookmarks)

    {:ok,
     %{
       state
       | filter: filter,
         filtered_indices: filtered,
         filter_input: nil,
         cursor: 0,
         scroll_offset: 0
     }}
  end

  defp filter_lines(lines, filter, bookmarks) do
    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, idx} ->
      matches_filter?(line, idx, filter, bookmarks)
    end)
    |> Enum.map(fn {_line, idx} -> idx end)
  end

  defp matches_filter?(line, idx, filter, bookmarks) do
    level_match?(line, filter) and
      source_match?(line, filter) and
      pattern_match?(line, filter) and
      bookmark_match?(idx, filter, bookmarks)
  end

  defp level_match?(line, filter) do
    filter.levels == nil or line.level in filter.levels
  end

  defp source_match?(line, filter) do
    filter.source == nil or
      (line.source != nil and String.contains?(line.source, filter.source))
  end

  defp pattern_match?(line, filter) do
    filter.pattern == nil or matches_regex_pattern?(line, filter) or
      matches_string_pattern?(line, filter)
  end

  defp matches_regex_pattern?(line, %{pattern: %Regex{} = regex}),
    do: Regex.match?(regex, line.raw)

  defp matches_regex_pattern?(_line, _filter), do: false

  defp matches_string_pattern?(line, %{pattern: pattern}) when is_binary(pattern) do
    String.contains?(line.raw, pattern)
  end

  defp matches_string_pattern?(_line, _filter), do: false

  defp bookmark_match?(idx, filter, bookmarks) do
    not filter.bookmarks_only or MapSet.member?(bookmarks, idx)
  end

  # ----------------------------------------------------------------------------
  # Private: Bookmarks
  # ----------------------------------------------------------------------------

  defp jump_to_next_bookmark(state) do
    if MapSet.size(state.bookmarks) == 0 do
      {:ok, state}
    else
      current_actual = get_actual_line_index(state, state.cursor)
      sorted = Enum.sort(MapSet.to_list(state.bookmarks))

      # Find next bookmark after current position
      next =
        Enum.find(sorted, fn b -> b > current_actual end) ||
          hd(sorted)

      visible_lines = get_visible_line_indices(state)
      visible_idx = Enum.find_index(visible_lines, &(&1 == next)) || state.cursor
      new_scroll = max(0, visible_idx - div(state.viewport_height, 2))

      {:ok, %{state | cursor: visible_idx, scroll_offset: new_scroll, tail_mode: false}}
    end
  end

  # ----------------------------------------------------------------------------
  # Private: Parsing
  # ----------------------------------------------------------------------------

  defp parse_line(line, id, parser) when is_binary(line) do
    parser.(line) |> Map.put(:id, id)
  end

  defp parse_line(%{} = entry, id, _parser) do
    Map.put(entry, :id, id)
  end

  @doc false
  def default_parser(line) do
    timestamp = extract_timestamp(line)
    level = extract_level(line)
    source = extract_source(line)

    %{
      timestamp: timestamp,
      level: level,
      source: source,
      message: line,
      raw: line
    }
  end

  defp extract_timestamp(line) do
    case Regex.run(timestamp_pattern(), line) do
      [match | _] ->
        case DateTime.from_iso8601(match) do
          {:ok, dt, _} -> dt
          _ -> nil
        end

      nil ->
        nil
    end
  end

  defp extract_level(line) do
    Enum.find_value(level_patterns(), fn {level, pattern} ->
      if Regex.match?(pattern, line), do: level, else: nil
    end)
  end

  defp extract_source(line) do
    case Regex.run(source_pattern(), line) do
      [_, source | _] -> source
      nil -> nil
    end
  end

  # ----------------------------------------------------------------------------
  # Private: Rendering
  # ----------------------------------------------------------------------------

  defp render_line(state, line, visible_idx, actual_idx) do
    is_cursor = visible_idx == state.cursor
    is_selected = in_selection?(state, actual_idx)
    is_bookmarked = MapSet.member?(state.bookmarks, actual_idx)
    is_search_match = state.search && actual_idx in state.search.matches

    # Build line parts
    parts = []

    # Line number
    parts =
      if state.show_line_numbers do
        num_str = String.pad_leading("#{actual_idx + 1}", 5)
        num_style = fg_dim_semantic(Theme.get_semantic(:muted))
        parts ++ [text(num_str <> " ", num_style)]
      else
        parts
      end

    # Bookmark indicator
    parts =
      if is_bookmarked do
        bookmark_style = fg_semantic(Theme.get_semantic(:warning))
        parts ++ [text("*", bookmark_style)]
      else
        parts ++ [text(" ", nil)]
      end

    # Level indicator
    parts =
      if state.show_levels && line.level do
        level_str = String.pad_trailing(level_abbrev(line.level), 5)
        level_style = fg_color(level_color(line.level))
        parts ++ [text(level_str <> " ", level_style)]
      else
        parts
      end

    # Message
    message = truncate_line(line.raw, state)
    message_style = get_message_style(state, line, is_cursor, is_selected, is_search_match)
    parts = parts ++ [text(message, message_style)]

    stack(:horizontal, parts)
  end

  defp level_color(:debug), do: Theme.get_semantic(:info)
  defp level_color(:info), do: Theme.get_semantic(:success)
  defp level_color(:notice), do: Theme.get_color(:primary)
  defp level_color(:warning), do: Theme.get_semantic(:warning)
  defp level_color(:error), do: Theme.get_semantic(:error)
  defp level_color(:critical), do: Theme.get_color(:accent)
  defp level_color(:alert), do: Theme.get_semantic(:error)
  defp level_color(:emergency), do: Theme.get_semantic(:error)
  defp level_color(_), do: Theme.get_color(:foreground)

  defp level_abbrev(:debug), do: "DEBUG"
  defp level_abbrev(:info), do: "INFO"
  defp level_abbrev(:notice), do: "NOTIC"
  defp level_abbrev(:warning), do: "WARN"
  defp level_abbrev(:error), do: "ERROR"
  defp level_abbrev(:critical), do: "CRIT"
  defp level_abbrev(:alert), do: "ALERT"
  defp level_abbrev(:emergency), do: "EMERG"
  defp level_abbrev(_), do: ""

  defp truncate_line(line, state) do
    max_width = state.viewport_width - 15

    if state.wrap_lines do
      line
    else
      if String.length(line) > max_width do
        String.slice(line, 0, max_width - 3) <> "..."
      else
        line
      end
    end
  end

  defp get_message_style(state, line, is_cursor, is_selected, is_search_match) do
    base_color =
      if state.highlight_levels && line.level do
        level_color(line.level)
      else
        Theme.get_color(:foreground)
      end

    cond do
      is_cursor ->
        Theme.get_component_style(:item, :focused)

      is_selected ->
        Theme.get_component_style(:item, :selected)

      is_search_match ->
        fg_bg_semantic(base_color, Theme.get_semantic(:warning))

      true ->
        fg_color(base_color)
    end
  end

  defp in_selection?(state, line_idx) do
    if state.selection_start != nil and state.selection_end != nil do
      start_idx = min(state.selection_start, state.selection_end)
      end_idx = max(state.selection_start, state.selection_end)
      line_idx >= start_idx and line_idx <= end_idx
    else
      false
    end
  end

  defp render_status_bar(state, _total_lines) do
    visible_lines = get_visible_line_indices(state)
    actual_idx = get_actual_line_index(state, state.cursor)

    parts = [
      "Line #{actual_idx + 1}/#{length(state.lines)}"
    ]

    parts =
      if state.filter do
        parts ++ [" | Filtered: #{length(visible_lines)}"]
      else
        parts
      end

    parts =
      if state.search do
        match_count = length(state.search.matches)
        current = state.search.current_match + 1
        parts ++ [" | Search: #{current}/#{match_count}"]
      else
        parts
      end

    parts =
      if MapSet.size(state.bookmarks) > 0 do
        parts ++ [" | Bookmarks: #{MapSet.size(state.bookmarks)}"]
      else
        parts
      end

    parts =
      if state.tail_mode do
        parts ++ [" | TAIL"]
      else
        parts
      end

    parts =
      if state.wrap_lines do
        parts ++ [" | WRAP"]
      else
        parts
      end

    status = Enum.join(parts, "")
    status_style = fg_dim_semantic(Theme.get_semantic(:info))
    text(status, status_style)
  end

  defp render_input_bar(state) do
    cond do
      state.search_input != nil ->
        search_style = fg_semantic(Theme.get_semantic(:warning))
        [text("Search: " <> state.search_input <> "_", search_style)]

      state.filter_input != nil ->
        filter_style = fg_semantic(Theme.get_semantic(:success))
        [text("Filter: " <> state.filter_input <> "_", filter_style)]

      true ->
        []
    end
  end
end
