for recipe <- ["input_focus", "form", "table", "stream"] do
  Code.require_file("../../examples/iex_counter/lib/iex_counter/recipes/#{recipe}.ex", __DIR__)
end

defmodule TermUI.WidgetRecipesSpex do
  use SexySpex

  alias IExCounter.Recipes
  alias TermUI.Clipboard.Operation
  alias TermUI.{Event, Frame, Runtime}
  alias TermUI.Test.DeterministicBackend
  alias TermUI.Widget.Table

  spex "text, paste, focus, clipboard, and resize follow the input owner" do
    scenario "the user edits two fields and cuts the selected city" do
      given_ "two empty inputs with the name focused", context do
        {:ok, Map.merge(context, start_recipe(Recipes.InputFocus))}
      end

      when_ "the user types a name and pastes a city after Tab", context do
        send_and_draw(context.runtime, Event.text("Ada"))
        send_and_draw(context.runtime, Event.key(:tab))
        frame = send_and_draw(context.runtime, Event.paste("Zürich\n"))
        assert String.trim(Frame.row_text(frame, 2)) == "Ada"
        assert String.trim(Frame.row_text(frame, 4)) == "Zürich"
        assert frame.cursor == {7, 4}
        {:ok, context}
      end

      then_ "focus loss hides the cursor and focus gain restores it", context do
        assert send_and_draw(context.runtime, Event.focus(:lost)).cursor == nil
        assert send_and_draw(context.runtime, Event.focus(:gained)).cursor == {7, 4}
        {:ok, context}
      end

      when_ "the user selects all city text and cuts it", context do
        send_and_draw(context.runtime, Event.key("a", modifiers: [:ctrl]))
        DeterministicBackend.send_event(context.runtime, Event.key("x", modifiers: [:ctrl]))
        assert_receive {:backend, :clipboard, %Operation{kind: :write, content: "Zürich"}}, 1_000
        frame = draw_until(&String.contains?(Frame.row_text(&1, 5), "Selection copied"))
        assert String.trim(Frame.row_text(frame, 4)) == ""
        assert Runtime.get_state(context.runtime).app_state.inputs.name.value == "Ada"
        {:ok, context}
      end

      then_ "resize preserves the name and normal quit cleans up", context do
        DeterministicBackend.resize(context.runtime, 12, 4)
        assert_receive {:backend, :resize, {4, 12}}, 1_000
        frame = draw_until(&({&1.width, &1.height} == {12, 4}))
        assert String.trim(Frame.row_text(frame, 2)) == "Ada"
        assert {:ok, _frame} = Zoi.parse(Frame.schema(), frame)
        quit_and_assert_cleanup(context)
        {:ok, context}
      end
    end
  end

  spex "form validation gives a visible error and an accepted result" do
    scenario "the user corrects a required name and chooses the role" do
      given_ "an empty required name", context do
        {:ok, Map.merge(context, start_recipe(Recipes.Form))}
      end

      when_ "the user submits the empty form", context do
        frame = send_and_draw(context.runtime, Event.key(:enter))
        assert Frame.row_text(frame, 2) =~ "is required"
        assert Frame.row_text(frame, 7) =~ "Fix the required fields"
        {:ok, context}
      end

      then_ "editing and resubmitting removes the error and displays the values", context do
        send_and_draw(context.runtime, Event.paste("Ada"))
        send_and_draw(context.runtime, Event.key(:tab))
        send_and_draw(context.runtime, Event.key(:right))
        send_and_draw(context.runtime, Event.key(:tab))
        send_and_draw(context.runtime, Event.text(" "))
        frame = send_and_draw(context.runtime, Event.key(:enter))
        assert Frame.row_text(frame, 7) =~ "Saved: Ada (writer)"
        assert Runtime.get_state(context.runtime).app_state.form.values.alerts
        refute Enum.any?(1..frame.height, &(Frame.row_text(frame, &1) =~ "is required"))
        quit_and_assert_cleanup(context)
        {:ok, context}
      end
    end
  end

  spex "table selection keeps identity through refresh, sort, and filtering" do
    scenario "the selected row moves and is temporarily hidden" do
      given_ "three rows with stable ids", context do
        {:ok, Map.merge(context, start_recipe(Recipes.Table))}
      end

      when_ "the user selects Bea then refreshes and sorts", context do
        send_and_draw(context.runtime, Event.key(:down))
        send_and_draw(context.runtime, Event.key(:enter))
        send_and_draw(context.runtime, Event.text("r"))
        frame = send_and_draw(context.runtime, Event.text("s"))
        assert Frame.row_text(frame, 3) =~ "Bea updated"
        assert Frame.row_text(frame, 7) =~ "Selected IDs: [2]"
        {:ok, context}
      end

      then_ "the filter hides the row while its selection stays", context do
        frame = send_and_draw(context.runtime, Event.text("h"))
        refute Enum.any?(1..frame.height, &(Frame.row_text(frame, &1) =~ "Bea updated"))
        assert Frame.row_text(frame, 7) =~ "Selected IDs: [2]"

        assert Table.selected_rows(Runtime.get_state(context.runtime).app_state.table) == [
                 %{id: 2, name: "Bea updated"}
               ]

        frame = send_and_draw(context.runtime, Event.text("h"))
        assert Enum.any?(1..frame.height, &(Frame.row_text(frame, &1) =~ "Bea updated"))
        quit_and_assert_cleanup(context)
        {:ok, context}
      end
    end
  end

  spex "a bounded stream retains data on command failure and can recover" do
    scenario "the user loads, pauses, sees a failed load, and retries" do
      given_ "an empty bounded stream", context do
        {:ok, Map.merge(context, start_recipe(Recipes.Stream))}
      end

      when_ "the runtime completes a load command", context do
        DeterministicBackend.send_event(context.runtime, Event.text("L"))
        frame = draw_until(&String.contains?(Frame.row_text(&1, 7), "Accepted: 4 Dropped: 1"))
        assert String.trim(Frame.row_text(frame, 2)) == "beta"
        assert String.trim(Frame.row_text(frame, 4)) == "delta"
        {:ok, context}
      end

      then_ "paused input is rejected without replacing the data", context do
        frame = send_and_draw(context.runtime, Event.text(" "))
        assert Frame.row_text(frame, 1) =~ "PAUSED"
        DeterministicBackend.send_event(context.runtime, Event.text("L"))
        frame = draw_until(&String.contains?(Frame.row_text(&1, 7), "Rejected: 4"))
        assert String.trim(Frame.row_text(frame, 2)) == "beta"
        {:ok, context}
      end

      when_ "a command fails then the user resumes and retries", context do
        DeterministicBackend.send_event(context.runtime, Event.text("F"))
        frame = draw_until(&String.contains?(Frame.row_text(&1, 7), "Load failed"))
        assert String.trim(Frame.row_text(frame, 2)) == "beta"
        send_and_draw(context.runtime, Event.text(" "))
        DeterministicBackend.send_event(context.runtime, Event.text("L"))
        frame = draw_until(&String.contains?(Frame.row_text(&1, 7), "Accepted: 4 Dropped: 4"))
        assert String.trim(Frame.row_text(frame, 4)) == "delta"
        assert Process.alive?(context.runtime)
        {:ok, context}
      end

      then_ "normal quit stops the backend owner", context do
        quit_and_assert_cleanup(context)
        {:ok, context}
      end
    end
  end

  spex "normal quit cancels a pending load without leaving a worker" do
    scenario "the user quits while an async command waits" do
      given_ "a stream with a blocked external loader", context do
        owner = self()

        loader = fn ->
          send(owner, {:loading_worker, self()})

          receive do
            {:monitor_ready, reference} -> send(owner, {:monitor_ready, self(), reference})
          end

          receive do
            :finish -> ["finished"]
          end
        end

        {:ok, Map.merge(context, start_recipe(Recipes.Stream, loader: loader))}
      end

      when_ "the load starts and remains pending", context do
        frame = send_and_draw(context.runtime, Event.text("L"))
        assert Frame.row_text(frame, 7) =~ "Loading"
        assert_receive {:loading_worker, worker}, 1_000
        reference = Process.monitor(worker)
        send(worker, {:monitor_ready, reference})
        assert_receive {:monitor_ready, ^worker, ^reference}, 1_000
        {:ok, Map.merge(context, %{worker: worker, worker_reference: reference})}
      end

      then_ "quit stops the runtime, backend owner, and pending worker", context do
        quit_and_assert_cleanup(context)
        worker = context.worker
        reference = context.worker_reference
        assert_receive {:DOWN, ^reference, :process, ^worker, :killed}, 1_000
        {:ok, context}
      end
    end
  end

  defp start_recipe(app, extra_opts \\ []) do
    opts =
      Keyword.merge(
        [
          backend: {DeterministicBackend, owner: self(), size: {8, 60}},
          backend_opts: [size_poll_interval: :disabled]
        ],
        extra_opts
      )

    runtime =
      start_supervised!(%{
        id: app,
        start: {TermUI, :start_link, [app, opts]},
        restart: :temporary
      })

    manager = Runtime.get_state(runtime).backend_manager
    assert_receive {:backend, :draw, %Frame{width: 60, height: 8}}, 1_000

    %{
      runtime: runtime,
      reference: Process.monitor(runtime),
      manager: manager,
      manager_reference: Process.monitor(manager)
    }
  end

  defp send_and_draw(runtime, event) do
    DeterministicBackend.send_event(runtime, event)
    draw_until(fn _frame -> true end)
  end

  defp draw_until(predicate),
    do: draw_until(predicate, System.monotonic_time(:millisecond) + 1_000)

  defp draw_until(predicate, deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:backend, :draw, frame} ->
        if predicate.(frame), do: frame, else: draw_until(predicate, deadline)
    after
      timeout -> flunk("The expected frame was not drawn within one second")
    end
  end

  defp quit_and_assert_cleanup(context) do
    DeterministicBackend.send_event(context.runtime, Event.key(:escape))
    assert_receive {:backend, :shutdown, :normal}, 1_000
    assert_receive {:backend, :shutdown_snapshot, %{shutdown_reason: :normal}}, 1_000
    runtime = context.runtime
    reference = context.reference
    assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 1_000
    manager = context.manager
    manager_reference = context.manager_reference
    assert_receive {:DOWN, ^manager_reference, :process, ^manager, :normal}, 1_000
  end
end
