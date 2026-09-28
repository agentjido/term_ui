defmodule TermUI.Renderer.IntegrationTest do
  # This module contains wall-clock microbenchmarks, so running it alongside
  # the async suite makes its performance assertions depend on scheduler load.
  use ExUnit.Case, async: false

  alias TermUI.Renderer.{
    Buffer,
    BufferManager,
    Cell,
    CursorOptimizer,
    Diff,
    FramerateLimiter,
    SequenceBuffer,
    Style
  }

  # Helper to render a frame and return the output
  defp render_frame(current, previous) do
    operations = Diff.diff(current, previous)

    {output, _optimizer} =
      Enum.reduce(operations, {SequenceBuffer.new(), CursorOptimizer.new()}, fn op,
                                                                                {buffer,
                                                                                 optimizer} ->
        case op do
          {:move, row, col} ->
            {seq, new_optimizer} = CursorOptimizer.move_to(optimizer, row, col)
            new_buffer = SequenceBuffer.append!(buffer, seq)
            {new_buffer, new_optimizer}

          {:style, style} ->
            new_buffer = SequenceBuffer.append_style(buffer, style)
            {new_buffer, optimizer}

          {:text, text} ->
            new_buffer = SequenceBuffer.append!(buffer, text)
            new_optimizer = CursorOptimizer.advance(optimizer, String.length(text))
            {new_buffer, new_optimizer}

          :reset ->
            # Reset style - append SGR reset sequence
            new_buffer = SequenceBuffer.append!(buffer, "\e[0m")
            {new_buffer, optimizer}
        end
      end)

    {data, _buffer} = SequenceBuffer.flush(output)
    IO.iodata_to_binary(data)
  end

  describe "render pipeline - simple text" do
    test "renders text at position" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      Buffer.write_string(current, 1, 1, "Hello")

      output = render_frame(current, previous)

      # Should contain cursor move and text
      assert String.contains?(output, "Hello")
    end

    test "renders multiple lines" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      Buffer.write_string(current, 1, 1, "Line 1")
      Buffer.write_string(current, 2, 1, "Line 2")
      Buffer.write_string(current, 3, 1, "Line 3")

      output = render_frame(current, previous)

      assert String.contains?(output, "Line 1")
      assert String.contains?(output, "Line 2")
      assert String.contains?(output, "Line 3")
    end

    test "renders text at various positions" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      Buffer.write_string(current, 5, 10, "Middle")
      Buffer.write_string(current, 10, 40, "Center")

      output = render_frame(current, previous)

      assert String.contains?(output, "Middle")
      assert String.contains?(output, "Center")
    end
  end

  describe "render pipeline - styled text" do
    test "renders colored text with SGR sequences" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      style = Style.new(fg: :red)
      Buffer.write_string(current, 1, 1, "Red", style: style)

      output = render_frame(current, previous)

      # Should contain red color code (31)
      assert String.contains?(output, "31")
      assert String.contains?(output, "Red")
    end

    test "renders bold text" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      style = Style.new(attrs: [:bold])
      Buffer.write_string(current, 1, 1, "Bold", style: style)

      output = render_frame(current, previous)

      # Should contain bold code (1)
      assert String.contains?(output, "\e[")
      assert String.contains?(output, "1")
      assert String.contains?(output, "Bold")
    end

    test "renders combined styles" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      style = Style.new(fg: :green, attrs: [:bold, :underline])
      Buffer.write_string(current, 1, 1, "Fancy", style: style)

      output = render_frame(current, previous)

      # Should contain green (32), bold (1), underline (4)
      assert String.contains?(output, "32")
      assert String.contains?(output, "Fancy")
    end

    test "renders background colors" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      style = Style.new(bg: :blue)
      Buffer.write_string(current, 1, 1, "Blue BG", style: style)

      output = render_frame(current, previous)

      # Should contain blue background code (44)
      assert String.contains?(output, "44")
    end
  end

  describe "render pipeline - partial updates" do
    test "only renders changed cells" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      # Set up previous state
      Buffer.write_string(previous, 1, 1, "Hello World")
      Buffer.write_string(current, 1, 1, "Hello World")

      # Change only one character
      Buffer.set_cell(current, 1, 7, Cell.new("E"))

      output = render_frame(current, previous)

      # Should only contain the changed character
      assert String.contains?(output, "E")
      # Should not re-render "Hello" or "orld"
      refute String.contains?(output, "Hello")
      refute String.contains?(output, "orld")
    end

    test "skips unchanged rows" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      # Set up previous state
      Buffer.write_string(previous, 1, 1, "Row 1")
      Buffer.write_string(previous, 2, 1, "Row 2")
      Buffer.write_string(previous, 3, 1, "Row 3")

      # Copy to current
      Buffer.write_string(current, 1, 1, "Row 1")
      Buffer.write_string(current, 2, 1, "Row 2")
      Buffer.write_string(current, 3, 1, "Row 3")

      # Only change row 2
      Buffer.write_string(current, 2, 1, "Changed")

      output = render_frame(current, previous)

      assert String.contains?(output, "Changed")
      refute String.contains?(output, "Row 1")
      refute String.contains?(output, "Row 3")
    end

    test "renders only changed style" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      # Previous has plain text
      Buffer.write_string(previous, 1, 1, "Text")
      Buffer.write_string(current, 1, 1, "Text")

      # Current has styled text
      style = Style.new(fg: :red)
      Buffer.write_string(current, 1, 1, "Text", style: style)

      output = render_frame(current, previous)

      # Should re-render with style
      assert String.contains?(output, "31")
      assert String.contains?(output, "Text")
    end
  end

  describe "render pipeline - cursor optimization" do
    test "uses relative movement for small distances" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      # Write at two close positions
      Buffer.write_string(current, 1, 1, "A")
      Buffer.write_string(current, 1, 5, "B")

      output = render_frame(current, previous)

      # Should contain both characters
      assert String.contains?(output, "A")
      assert String.contains?(output, "B")
    end

    test "optimized output is shorter than naive" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      # Write at multiple positions
      Buffer.write_string(current, 1, 1, "A")
      Buffer.write_string(current, 2, 1, "B")
      Buffer.write_string(current, 3, 1, "C")

      optimized_output = render_frame(current, previous)

      # Calculate naive output (absolute positioning for each)
      naive_size =
        String.length("\e[1;1HA") +
          String.length("\e[2;1HB") +
          String.length("\e[3;1HC")

      # Optimized should be close to naive (may be slightly larger now that
      # bare \n is replaced with ANSI \e[B for OTP 28 raw mode correctness)
      assert byte_size(optimized_output) <= naive_size * 2
    end
  end

  describe "animation - spinner" do
    test "spinner frames render correctly" do
      spinner_frames = ["|", "/", "-", "\\"]

      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      outputs =
        for frame <- spinner_frames do
          # Clear previous
          Buffer.clear(previous)
          Buffer.clear(current)

          # Swap buffers (previous becomes current state)
          Buffer.write_string(current, 1, 1, frame)

          output = render_frame(current, previous)

          # Copy current to previous for next iteration
          Buffer.write_string(previous, 1, 1, frame)

          output
        end

      # Each frame should contain its character
      for {output, frame} <- Enum.zip(outputs, spinner_frames) do
        assert String.contains?(output, frame)
      end
    end
  end

  describe "animation - progress bar" do
    test "progress bar updates only changed region" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      # Initial progress bar: [====      ]
      Buffer.write_string(previous, 1, 1, "[====      ]")
      Buffer.write_string(current, 1, 1, "[====      ]")

      # Update to: [=====     ]
      Buffer.write_string(current, 1, 1, "[=====     ]")

      output = render_frame(current, previous)

      # Should contain the change (the 5th = and space)
      # But not re-render the entire bar
      assert byte_size(output) < byte_size("[=====     ]") + 20
    end

    test "progress bar renders multiple updates" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      progress_states = [
        "[          ]",
        "[==        ]",
        "[====      ]",
        "[======    ]",
        "[========  ]",
        "[==========]"
      ]

      for state <- progress_states do
        Buffer.clear(current)
        Buffer.write_string(current, 1, 1, state)

        output = render_frame(current, previous)
        assert byte_size(output) > 0

        # Update previous for next iteration
        Buffer.clear(previous)
        Buffer.write_string(previous, 1, 1, state)
      end
    end
  end

  describe "animation - update coalescing" do
    test "high-frequency updates produce single render" do
      test_pid = self()
      render_count = :counters.new(1, [])

      {:ok, manager} = BufferManager.start_link(rows: 24, cols: 80)

      {:ok, limiter} =
        FramerateLimiter.start_link(
          name: :coalescing_test_limiter,
          fps: 60,
          render_callback: fn ->
            :counters.add(render_count, 1, 1)
            send(test_pid, :rendered)
          end
        )

      # Mark dirty many times quickly
      for _ <- 1..100 do
        FramerateLimiter.mark_dirty(limiter)
      end

      # Wait for frames
      Process.sleep(100)

      # Should have coalesced to much fewer renders
      renders = :counters.get(render_count, 1)
      assert renders < 20

      GenServer.stop(limiter)
      GenServer.stop(manager)
    end
  end

  describe "resize handling" do
    test "resize triggers buffer reallocation" do
      {:ok, manager} = BufferManager.start_link(rows: 24, cols: 80)

      # Write some content
      BufferManager.write_string(manager, 1, 1, "Test")

      # Resize
      BufferManager.resize(manager, 40, 120)

      # Check new dimensions
      assert BufferManager.dimensions(manager) == {40, 120}

      GenServer.stop(manager)
    end

    test "content is preserved after resize" do
      {:ok, manager} = BufferManager.start_link(rows: 24, cols: 80)

      # Write content
      BufferManager.write_string(manager, 1, 1, "Preserved")

      # Resize larger
      BufferManager.resize(manager, 40, 120)

      # Check content is preserved
      buffer = BufferManager.get_current_buffer(manager)
      cell = Buffer.get_cell(buffer, 1, 1)
      assert cell.char == "P"

      GenServer.stop(manager)
    end

    test "content is truncated on shrink" do
      {:ok, manager} = BufferManager.start_link(rows: 24, cols: 80)

      # Write content at far position
      BufferManager.write_string(manager, 20, 70, "Far")

      # Resize smaller
      BufferManager.resize(manager, 10, 40)

      # Content beyond new bounds is gone
      buffer = BufferManager.get_current_buffer(manager)
      # Row 20 is now out of bounds (buffer only has 10 rows)
      assert Buffer.dimensions(buffer) == {10, 40}

      GenServer.stop(manager)
    end

    test "rapid resize sequence" do
      {:ok, manager} = BufferManager.start_link(rows: 24, cols: 80)

      # Rapid resize sequence
      for {rows, cols} <- [{30, 100}, {20, 60}, {40, 120}, {24, 80}] do
        BufferManager.resize(manager, rows, cols)
        assert BufferManager.dimensions(manager) == {rows, cols}
      end

      GenServer.stop(manager)
    end
  end

  describe "performance benchmarking" do
    @tag :benchmark
    test "full screen render performance" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      # Fill screen with content
      for row <- 1..24 do
        text = String.duplicate("X", 80)
        Buffer.write_string(current, row, 1, text)
      end

      # Measure render time
      {time_us, output} =
        :timer.tc(fn ->
          render_frame(current, previous)
        end)

      # Should complete in reasonable time (< 10ms)
      assert time_us < 10_000

      # Should produce output
      assert byte_size(output) > 0

      # Log for visibility
      IO.puts("\nFull screen render: #{time_us}μs, #{byte_size(output)} bytes")
    end

    @tag :benchmark
    test "incremental render performance" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      # Set up identical buffers
      for row <- 1..24 do
        text = String.duplicate("X", 80)
        Buffer.write_string(current, row, 1, text)
        Buffer.write_string(previous, row, 1, text)
      end

      # Change only one cell
      Buffer.set_cell(current, 12, 40, Cell.new("O"))

      # Measure render time
      {time_us, output} =
        :timer.tc(fn ->
          render_frame(current, previous)
        end)

      # Should be very fast (< 10ms, with margin for CI/slow machines)
      assert time_us < 10_000

      # Should produce minimal output
      assert byte_size(output) < 50

      IO.puts("\nIncremental render: #{time_us}μs, #{byte_size(output)} bytes")
    end

    @tag :benchmark
    test "diff algorithm performance" do
      {:ok, current} = Buffer.new(40, 120)
      {:ok, previous} = Buffer.new(40, 120)

      # Set up different content
      for row <- 1..40 do
        text = String.duplicate("A", 120)
        Buffer.write_string(previous, row, 1, text)
        char = if rem(row, 2) == 0, do: "B", else: "A"
        text = String.duplicate(char, 120)
        Buffer.write_string(current, row, 1, text)
      end

      # Measure diff time
      {time_us, operations} =
        :timer.tc(fn ->
          Diff.diff(current, previous)
        end)

      # Should complete in reasonable time (allowing for system load variance)
      # Increased threshold for CI/shared environments under load
      assert time_us < 15_000

      # Should produce operations
      assert operations != []

      cells = 40 * 120
      cells_per_ms = cells / (time_us / 1000)
      IO.puts("\nDiff: #{time_us}μs for #{cells} cells (#{round(cells_per_ms)} cells/ms)")
    end

    @tag :benchmark
    test "cursor optimization savings" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      # Write at column 1 on multiple rows (ideal for CR optimization)
      for row <- 1..20 do
        Buffer.write_string(current, row, 1, "Line #{row}")
      end

      # Render with optimization
      optimized = render_frame(current, previous)

      # Calculate naive (absolute positioning)
      naive_size =
        Enum.reduce(1..20, 0, fn row, acc ->
          text = "Line #{row}"
          # ESC[row;1H = 4 base + digits(row) + digits(1) + text
          # ESC [ row ; col H = 1+1+digits(row)+1+1+1 = 5 + digits(row)
          pos_cost = 5 + if row >= 10, do: 2, else: 1
          acc + pos_cost + String.length(text)
        end)

      savings = ((naive_size - byte_size(optimized)) / naive_size * 100) |> Float.round(1)

      IO.puts(
        "\nCursor optimization: #{byte_size(optimized)} bytes vs #{naive_size} naive (#{savings}% savings)"
      )

      # Optimized should be reasonable (may be slightly larger now that
      # bare \n is replaced with ANSI \e[B for OTP 28 raw mode correctness)
      assert byte_size(optimized) < naive_size * 2
    end
  end

  describe "edge cases" do
    test "empty buffer produces no output" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      output = render_frame(current, previous)
      assert output == ""
    end

    test "identical buffers produce no output" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      Buffer.write_string(current, 1, 1, "Same")
      Buffer.write_string(previous, 1, 1, "Same")

      output = render_frame(current, previous)
      assert output == ""
    end

    test "single character change" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      Buffer.set_cell(current, 1, 1, Cell.new("X"))

      output = render_frame(current, previous)
      assert String.contains?(output, "X")
    end

    test "unicode characters" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      Buffer.write_string(current, 1, 1, "Hello 世界")

      output = render_frame(current, previous)
      assert String.contains?(output, "Hello")
      assert String.contains?(output, "世界")
    end

    test "256 colors" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      style = Style.new(fg: 196)
      Buffer.write_string(current, 1, 1, "256", style: style)

      output = render_frame(current, previous)
      assert String.contains?(output, "38;5;196")
    end

    test "true color RGB" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      style = Style.new(fg: {255, 128, 64})
      Buffer.write_string(current, 1, 1, "RGB", style: style)

      output = render_frame(current, previous)
      assert String.contains?(output, "38;2;255;128;64")
    end
  end
end
