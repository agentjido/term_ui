defmodule TermUI.Runtime.ColorUpdateTest do
  use ExUnit.Case, async: false

  alias TermUI.Backend.{Raw, TTY}
  alias TermUI.Renderer.Buffer
  alias TermUI.Renderer.Style
  alias TermUI.Runtime
  alias TermUI.Runtime.NodeRenderer
  alias TermUI.Test.AnsiScreen

  defmodule Matrix do
    use TermUI.Elm

    @colors %{"a" => :green, "b" => :yellow, "c" => :blue, "d" => :red}

    def init(opts), do: %{matrix: Keyword.fetch!(opts, :matrix)}
    def event_to_msg(_event, _state), do: :ignore
    def update({:matrix, matrix}, state), do: {%{state | matrix: matrix}, []}

    def view(state) do
      stack(:vertical, [
        Enum.map(state.matrix, fn row ->
          stack(:horizontal, Enum.map(row, &text(&1, Style.new(fg: Map.fetch!(@colors, &1)))))
        end)
      ])
    end
  end

  defmodule RawOutputBackend do
    @behaviour TermUI.Backend
    def init(opts), do: Raw.init(opts)
    defdelegate shutdown(state), to: Raw
    defdelegate size(state), to: Raw
    defdelegate move_cursor(state, position), to: Raw
    defdelegate hide_cursor(state), to: Raw
    defdelegate show_cursor(state), to: Raw
    defdelegate clear(state), to: Raw
    defdelegate draw_cells(state, cells), to: Raw
    defdelegate flush(state), to: Raw
    def poll_event(state, _timeout), do: {:timeout, state}
  end

  test "the issue 25 matrix retains every color through runtime updates" do
    with_output(fn device ->
      matrices = matrices()
      [first | rest] = matrices

      {:ok, runtime} =
        Runtime.start_link(
          root: Matrix,
          matrix: first,
          backend: {RawOutputBackend, size: {5, 4}},
          render_interval: 60_000
        )

      try do
        send(runtime, :render)
        assert :ok = Runtime.sync(runtime)
        {screen, offset} = read_screen(device, AnsiScreen.new(), 0)
        assert_matrix(screen, first)

        Enum.reduce(rest, {screen, offset}, fn matrix, {screen, offset} ->
          Runtime.send_message(runtime, :root, {:matrix, matrix})
          send(runtime, :render)
          assert :ok = Runtime.sync(runtime)
          assert Runtime.get_state(runtime).root_state.matrix == matrix
          {screen, offset} = read_screen(device, screen, offset)
          assert_matrix(screen, matrix)
          {screen, offset}
        end)
      after
        GenServer.stop(runtime)
      end
    end)
  end

  test "both TTY modes preserve unchanged colored cells between changed cells" do
    for line_mode <- [:full_redraw, :incremental] do
      with_output(fn device ->
        {:ok, state} = TTY.init(size: {5, 4}, line_mode: line_mode)
        {:ok, buffer} = Buffer.new(5, 4)

        try do
          Enum.reduce(matrices(), {state, AnsiScreen.new(), 0}, fn matrix,
                                                                   {state, screen, offset} ->
            :ok = Buffer.clear(buffer)
            NodeRenderer.render_to_buffer_direct(Matrix.view(%{matrix: matrix}), buffer)

            cells =
              for row <- 1..5, column <- 1..4 do
                cell = Buffer.get_cell(buffer, row, column)
                {{row, column}, {cell.char, cell.fg, cell.bg, MapSet.to_list(cell.attrs)}}
              end

            {:ok, state} = TTY.draw_cells(state, cells)
            {screen, offset} = read_screen(device, screen, offset)
            assert_matrix(screen, matrix)
            {state, screen, offset}
          end)
        after
          Buffer.destroy(buffer)
        end
      end)
    end
  end

  test "style-only changes restore foreground, background, and removed attributes" do
    for backend <- [Raw, TTY] do
      with_output(fn device ->
        {:ok, state} = backend.init(size: {5, 4}, line_mode: :incremental)

        styles = [
          {:green, :blue, [:bold, :underline]},
          {:green, :default, []},
          {:default, :default, []},
          {196, {10, 20, 30}, [:italic]},
          {{40, 50, 60}, 25, []}
        ]

        Enum.reduce(styles, {state, AnsiScreen.new(), 0}, fn {fg, bg, attrs},
                                                             {state, screen, offset} ->
          cells = for row <- 1..5, column <- 1..4, do: {{row, column}, {"X", fg, bg, attrs}}
          {:ok, state} = backend.draw_cells(state, cells)
          {screen, offset} = read_screen(device, screen, offset)

          for {position, _cell} <- cells do
            assert Map.fetch!(screen.cells, position) == {"X", fg, bg, MapSet.new(attrs)}
          end

          {state, screen, offset}
        end)
      end)
    end
  end

  defp matrices do
    permutations =
      for a <- ~w(a b c d),
          b <- ~w(a b c d),
          c <- ~w(a b c d),
          d <- ~w(a b c d),
          length(Enum.uniq([a, b, c, d])) == 4,
          do: [a, b, c, d]

    # Swap only the first and last letters before all permutations. The middle
    # cells must remain visible during an incremental update.
    [List.duplicate(~w(a b c d), 5), List.duplicate(~w(d b c a), 5)] ++
      Enum.map(0..23, fn index ->
        Enum.map(0..4, &Enum.at(permutations, rem(index + &1, 24)))
      end)
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
