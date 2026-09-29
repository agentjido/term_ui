defmodule TermUI.Integration.ColorUpdateTest do
  use ExUnit.Case, async: false

  alias TermUI.Backend.{Raw, TTY}
  alias TermUI.{Frame, Runtime, Style}
  alias TermUI.Test.AnsiScreen

  defmodule Matrix do
    use TermUI.Elm

    @colors %{"a" => :green, "b" => :yellow, "c" => :blue, "d" => :red}
    def init(opts), do: %{matrix: Keyword.fetch!(opts, :matrix)}
    def event_to_msg(_event, _state), do: :ignore
    def update({:matrix, matrix}, state), do: %{state | matrix: matrix}

    def view(state) do
      rows =
        Enum.map(state.matrix, fn row ->
          Enum.map(row, &{&1, Style.new(fg: Map.fetch!(@colors, &1))})
        end)

      Frame.from_rows(rows, 4, 5)
    end
  end

  defmodule OutputBackend do
    @behaviour TermUI.Backend
    def init(opts) do
      implementation = Keyword.fetch!(opts, :implementation)
      {:ok, state} = implementation.init(opts)
      {:ok, %{implementation: implementation, state: state}}
    end

    def size(state), do: state.implementation.size(state.state)
    def capabilities(state), do: state.implementation.capabilities(state.state)
    def draw(state, frame), do: invoke(state, :draw, [frame])
    def flush(state), do: invoke(state, :flush, [])
    def resize(state, size), do: invoke(state, :resize, [size])
    def shutdown(state, reason), do: state.implementation.shutdown(state.state, reason)
    def poll_event(state, _timeout), do: {:timeout, state}

    defp invoke(state, callback, args) do
      case apply(state.implementation, callback, [state.state | args]) do
        {:ok, next} -> {:ok, %{state | state: next}}
        error -> error
      end
    end
  end

  test "Raw and both TTY modes retain every matrix color through runtime updates" do
    for {implementation, mode} <- [{Raw, :incremental}, {TTY, :incremental}, {TTY, :full_redraw}] do
      with_output(fn device ->
        [first | rest] = matrices()

        {:ok, runtime} =
          Runtime.start_link(
            root: Matrix,
            matrix: first,
            backend: {OutputBackend, options(implementation, mode)},
            suppress_logger: false,
            render_interval: 60_000
          )

        try do
          assert :ok = Runtime.sync(runtime)
          {screen, offset} = read_screen(device, AnsiScreen.new(), 0)
          assert_matrix(screen, first)

          Enum.reduce(rest, {screen, offset}, fn matrix, {screen, offset} ->
            Runtime.send_message(runtime, {:matrix, matrix})
            assert :ok = Runtime.sync(runtime)
            # Deliver the pending ordinary render tick. Forced rendering would
            # discard the cache and hide an incremental-output defect.
            {_reference, token} = Runtime.get_state(runtime).render_timer
            send(runtime, {:render, token})
            assert :ok = Runtime.sync(runtime)
            assert Runtime.get_state(runtime).app_state.matrix == matrix
            {screen, offset} = read_screen(device, screen, offset)
            assert_matrix(screen, matrix)
            {screen, offset}
          end)
        after
          GenServer.stop(runtime)
        end
      end)
    end
  end

  test "style-only frame changes restore colors and removed attributes" do
    for implementation <- [Raw, TTY] do
      with_output(fn device ->
        {:ok, state} = implementation.init(options(implementation, :incremental))

        styles = [
          {:green, :blue, [:bold, :underline]},
          {:green, :default, []},
          {:default, :default, []},
          {196, {10, 20, 30}, [:italic]},
          {{40, 50, 60}, 25, []}
        ]

        Enum.reduce(styles, {state, AnsiScreen.new(), 0}, fn {fg, bg, attrs},
                                                             {state, screen, offset} ->
          frame =
            Frame.from_rows(
              List.duplicate(
                [{"XXXX", Style.new(fg: style_color(fg), bg: style_color(bg), attrs: attrs)}],
                5
              ),
              4,
              5
            )

          {:ok, state} = implementation.draw(state, frame)
          {screen, offset} = read_screen(device, screen, offset)

          for row <- 1..5, column <- 1..4 do
            assert Map.fetch!(screen.cells, {row, column}) == {"X", fg, bg, MapSet.new(attrs)}
          end

          {state, screen, offset}
        end)
      end)
    end
  end

  defp style_color(index) when is_integer(index), do: {:indexed, index}
  defp style_color({red, green, blue}), do: {:rgb, red, green, blue}
  defp style_color(named), do: named

  defp options(implementation, mode) do
    [
      implementation: implementation,
      size: {5, 4},
      line_mode: mode,
      alternate_screen: false,
      bracketed_paste: false,
      focus_events: false
    ]
  end

  defp matrices do
    permutations =
      for a <- ~w(a b c d),
          b <- ~w(a b c d),
          c <- ~w(a b c d),
          d <- ~w(a b c d),
          length(Enum.uniq([a, b, c, d])) == 4,
          do: [a, b, c, d]

    [List.duplicate(~w(a b c d), 5), List.duplicate(~w(d b c a), 5)] ++
      Enum.map(0..23, fn index -> Enum.map(0..4, &Enum.at(permutations, rem(index + &1, 24))) end)
  end

  defp assert_matrix(screen, matrix) do
    colors = %{"a" => :green, "b" => :yellow, "c" => :blue, "d" => :red}

    for {letters, row} <- Enum.with_index(matrix, 1),
        {letter, column} <- Enum.with_index(letters, 1) do
      assert Map.fetch!(screen.cells, {row, column}) ==
               {letter, Map.fetch!(colors, letter), :default, MapSet.new()}
    end
  end

  defp read_screen(device, screen, offset) do
    {_input, output} = StringIO.contents(device)
    changes = binary_part(output, offset, byte_size(output) - offset)
    {AnsiScreen.feed(screen, changes), byte_size(output)}
  end

  defp with_output(check) do
    {:ok, device} = StringIO.open("")
    previous = Process.group_leader()
    Process.group_leader(self(), device)

    try do
      check.(device)
    after
      Process.group_leader(self(), previous)
      StringIO.close(device)
    end
  end
end
