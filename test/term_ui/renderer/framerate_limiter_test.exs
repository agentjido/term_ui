defmodule TermUI.Renderer.FramerateLimiterTest do
  use ExUnit.Case, async: true

  alias TermUI.Renderer.FramerateLimiter

  describe "new/1 and start_link/1" do
    test "creates limiter with default 60 FPS" do
      {:ok, pid} = FramerateLimiter.start_link(render_callback: fn -> :ok end)
      assert FramerateLimiter.get_fps(pid) == 60
      GenServer.stop(pid)
    end

    test "creates limiter with custom FPS" do
      {:ok, pid} = FramerateLimiter.start_link(fps: 120, render_callback: fn -> :ok end)
      assert FramerateLimiter.get_fps(pid) == 120
      GenServer.stop(pid)
    end

    test "requires render_callback" do
      Process.flag(:trap_exit, true)

      assert {:error, {%KeyError{key: :render_callback}, _}} =
               FramerateLimiter.start_link([])
    end
  end

  describe "dirty flag" do
    test "starts not dirty" do
      {:ok, pid} = FramerateLimiter.start_link(render_callback: fn -> :ok end)
      refute FramerateLimiter.dirty?(pid)
      GenServer.stop(pid)
    end

    test "mark_dirty sets flag" do
      {:ok, pid} = FramerateLimiter.start_link(render_callback: fn -> :ok end)
      FramerateLimiter.mark_dirty(pid)
      assert FramerateLimiter.dirty?(pid)
      GenServer.stop(pid)
    end

    test "clear_dirty clears flag" do
      {:ok, pid} = FramerateLimiter.start_link(render_callback: fn -> :ok end)
      FramerateLimiter.mark_dirty(pid)
      FramerateLimiter.clear_dirty(pid)
      refute FramerateLimiter.dirty?(pid)
      GenServer.stop(pid)
    end

    test "concurrent dirty flag writes don't lose updates" do
      {:ok, pid} = FramerateLimiter.start_link(render_callback: fn -> :ok end)

      # Spawn multiple processes to mark dirty concurrently
      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            FramerateLimiter.mark_dirty(pid)
          end)
        end

      Task.await_many(tasks)

      # Flag should be set
      assert FramerateLimiter.dirty?(pid)

      GenServer.stop(pid)
    end
  end

  describe "frame timing" do
    test "frame timer fires at correct intervals" do
      test_pid = self()
      counter = :counters.new(1, [])

      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 60,
          render_callback: fn ->
            :counters.add(counter, 1, 1)
            send(test_pid, :rendered)
          end
        )

      # Mark dirty and wait for render
      FramerateLimiter.mark_dirty(pid)

      # Wait for at least one render
      assert_receive :rendered, 100

      # Verify render happened
      assert :counters.get(counter, 1) >= 1

      GenServer.stop(pid)
    end

    test "render is triggered only when buffer is dirty" do
      test_pid = self()
      counter = :counters.new(1, [])

      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 60,
          render_callback: fn ->
            :counters.add(counter, 1, 1)
            send(test_pid, :rendered)
          end
        )

      # Don't mark dirty - should not render
      Process.sleep(50)
      refute_received :rendered

      # Now mark dirty
      FramerateLimiter.mark_dirty(pid)
      assert_receive :rendered, 100

      GenServer.stop(pid)
    end

    test "clean frames are skipped without rendering" do
      test_pid = self()

      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 60,
          render_callback: fn ->
            send(test_pid, :rendered)
          end
        )

      # Mark dirty once
      FramerateLimiter.mark_dirty(pid)
      assert_receive :rendered, 100

      # Wait for a few more ticks without marking dirty
      Process.sleep(100)

      # Check stats - should have skipped frames
      stats = FramerateLimiter.stats(pid)
      assert stats.skipped_frames > 0

      GenServer.stop(pid)
    end
  end

  describe "immediate mode" do
    test "render_immediate renders without waiting for tick" do
      test_pid = self()
      counter = :counters.new(1, [])

      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 30,
          render_callback: fn ->
            :counters.add(counter, 1, 1)
            send(test_pid, :rendered)
          end
        )

      # Pause to prevent automatic ticks
      FramerateLimiter.pause(pid)

      # Mark dirty and render immediately
      FramerateLimiter.mark_dirty(pid)
      FramerateLimiter.render_immediate(pid)

      assert_receive :rendered, 50

      GenServer.stop(pid)
    end

    test "render_immediate clears dirty flag" do
      {:ok, pid} =
        FramerateLimiter.start_link(render_callback: fn -> :ok end)

      FramerateLimiter.mark_dirty(pid)
      assert FramerateLimiter.dirty?(pid)

      FramerateLimiter.render_immediate(pid)
      refute FramerateLimiter.dirty?(pid)

      GenServer.stop(pid)
    end
  end

  describe "pause/resume" do
    test "pause stops frame timing" do
      test_pid = self()

      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 60,
          render_callback: fn ->
            send(test_pid, :rendered)
          end
        )

      FramerateLimiter.pause(pid)
      assert FramerateLimiter.paused?(pid)

      # Mark dirty but should not render
      FramerateLimiter.mark_dirty(pid)
      Process.sleep(50)
      refute_received :rendered

      GenServer.stop(pid)
    end

    test "resume restarts frame timing" do
      test_pid = self()

      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 60,
          render_callback: fn ->
            send(test_pid, :rendered)
          end
        )

      FramerateLimiter.pause(pid)
      FramerateLimiter.mark_dirty(pid)

      FramerateLimiter.resume(pid)
      refute FramerateLimiter.paused?(pid)

      # Should render now
      assert_receive :rendered, 100

      GenServer.stop(pid)
    end
  end

  describe "FPS configuration" do
    test "set_fps changes target FPS" do
      {:ok, pid} = FramerateLimiter.start_link(fps: 60, render_callback: fn -> :ok end)

      FramerateLimiter.set_fps(pid, 120)
      assert FramerateLimiter.get_fps(pid) == 120

      GenServer.stop(pid)
    end
  end

  describe "performance metrics" do
    test "stats returns performance data" do
      {:ok, pid} = FramerateLimiter.start_link(render_callback: fn -> :ok end)

      stats = FramerateLimiter.stats(pid)

      assert Map.has_key?(stats, :rendered_frames)
      assert Map.has_key?(stats, :skipped_frames)
      assert Map.has_key?(stats, :total_frames)
      assert Map.has_key?(stats, :actual_fps)
      assert Map.has_key?(stats, :avg_render_time_us)
      assert Map.has_key?(stats, :slow_frames)

      GenServer.stop(pid)
    end

    test "stats tracks rendered frames" do
      test_pid = self()

      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 60,
          render_callback: fn ->
            send(test_pid, :rendered)
          end
        )

      # Render a few frames
      for _ <- 1..3 do
        FramerateLimiter.mark_dirty(pid)
        assert_receive :rendered, 500
      end

      stats = FramerateLimiter.stats(pid)
      assert stats.rendered_frames >= 3

      GenServer.stop(pid)
    end

    test "stats tracks average render time" do
      {:ok, pid} =
        FramerateLimiter.start_link(
          render_callback: fn ->
            # Simulate some work
            Process.sleep(1)
          end
        )

      # Render some frames
      for _ <- 1..5 do
        FramerateLimiter.mark_dirty(pid)
        Process.sleep(30)
      end

      stats = FramerateLimiter.stats(pid)
      # Should have some render time recorded
      assert stats.avg_render_time_us > 0

      GenServer.stop(pid)
    end

    test "reset_stats clears all metrics" do
      test_pid = self()

      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 60,
          render_callback: fn ->
            send(test_pid, :rendered)
          end
        )

      # Render some frames
      FramerateLimiter.mark_dirty(pid)
      assert_receive :rendered, 100

      # Reset
      FramerateLimiter.reset_stats(pid)

      stats = FramerateLimiter.stats(pid)
      assert stats.rendered_frames == 0
      assert stats.skipped_frames == 0
      assert stats.slow_frames == 0

      GenServer.stop(pid)
    end

    test "detects slow frames" do
      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 120,
          render_callback: fn ->
            # Sleep longer than 8ms target
            Process.sleep(20)
          end
        )

      # Render a slow frame
      FramerateLimiter.mark_dirty(pid)
      Process.sleep(50)

      stats = FramerateLimiter.stats(pid)
      assert stats.slow_frames > 0

      GenServer.stop(pid)
    end
  end

  describe "FPS calculation" do
    test "calculates actual FPS from frame timestamps" do
      test_pid = self()

      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 60,
          render_callback: fn ->
            send(test_pid, :rendered)
          end
        )

      # Wait for several frame ticks to accumulate timestamps
      Process.sleep(200)

      stats = FramerateLimiter.stats(pid)
      # Should have some FPS calculated (may not be exactly 60 due to timing)
      assert stats.actual_fps > 0

      GenServer.stop(pid)
    end
  end

  describe "drift compensation" do
    test "maintains consistent frame rate over time" do
      test_pid = self()
      counter = :counters.new(1, [])

      {:ok, pid} =
        FramerateLimiter.start_link(
          fps: 60,
          render_callback: fn ->
            :counters.add(counter, 1, 1)
            send(test_pid, :rendered)
          end
        )

      # Keep marking dirty for consistent rendering
      for _ <- 1..10 do
        FramerateLimiter.mark_dirty(pid)
        Process.sleep(20)
      end

      # Should have rendered multiple frames
      rendered = :counters.get(counter, 1)
      assert rendered >= 5

      GenServer.stop(pid)
    end
  end
end
