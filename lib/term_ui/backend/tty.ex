defmodule TermUI.Backend.TTY do
  @moduledoc false

  @behaviour TermUI.Backend

  alias TermUI.{ANSI, Clipboard, Frame}
  alias TermUI.Backend.{CapabilityFilter, EventStream, Renderer}
  alias TermUI.Terminal.SizeDetector
  alias TermUI.TerminalOutput

  @type line_mode :: :full_redraw | :incremental
  @type color_mode :: :true_color | :color_256 | :color_16 | :monochrome
  @type character_set :: :unicode | :ascii

  @type t :: %__MODULE__{
          size: TermUI.Backend.size(),
          capabilities: map(),
          line_mode: line_mode(),
          character_set: character_set(),
          color_mode: color_mode(),
          alternate_screen: boolean(),
          input_buffer: binary(),
          event_queue: [TermUI.Backend.event()],
          paste_state: map() | nil,
          input_reader: pid() | nil,
          rendered_frame: Frame.t() | nil,
          bracketed_paste: boolean(),
          focus_events: boolean()
        }

  defstruct size: {24, 80},
            capabilities: %{},
            line_mode: :full_redraw,
            character_set: :unicode,
            color_mode: :true_color,
            alternate_screen: false,
            input_buffer: "",
            event_queue: [],
            paste_state: nil,
            input_reader: nil,
            rendered_frame: nil,
            bracketed_paste: true,
            focus_events: true

  @impl true
  @spec init(keyword()) :: {:ok, t()} | {:error, term()}
  def init(opts) do
    capabilities =
      opts
      |> Keyword.get(:capabilities, %{})
      |> CapabilityFilter.filter(opts)

    state = %__MODULE__{
      size: determine_size(opts, capabilities),
      capabilities: capabilities,
      line_mode: Keyword.get(opts, :line_mode, :full_redraw),
      character_set: if(capabilities.unicode, do: :unicode, else: :ascii),
      color_mode: determine_color_mode(capabilities),
      alternate_screen: Keyword.get(opts, :alternate_screen, false),
      bracketed_paste: Keyword.get(opts, :bracketed_paste, true),
      focus_events: Keyword.get(opts, :focus_events, true)
    }

    case TerminalOutput.write(setup_sequence(state)) do
      :ok ->
        {:ok, state}

      {:error, reason} ->
        shutdown(state, {:init_failed, reason})
        {:error, {:terminal_write_failed, reason}}
    end
  end

  @impl true
  @spec shutdown(t(), term()) :: :ok
  def shutdown(state, _reason) do
    EventStream.stop(state)

    TerminalOutput.write_to_tty(
      TerminalOutput.cleanup_sequence(
        bracketed_paste: state.bracketed_paste,
        focus_events: state.focus_events,
        alternate_screen: state.alternate_screen
      )
    )

    :ok
  end

  @impl true
  @spec size(t()) :: {:ok, TermUI.Backend.size()}
  def size(state), do: {:ok, state.size}

  @impl true
  @spec capabilities(t()) :: map()
  def capabilities(state), do: Map.put_new(state.capabilities, :dimensions, state.size)

  @spec refresh_size(t()) :: {:ok, TermUI.Backend.size(), t()} | {:error, term()}
  def refresh_size(state) do
    case SizeDetector.detect() do
      {:ok, size} -> {:ok, size, %{state | size: size}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @spec draw(t(), Frame.t()) :: {:ok, t()} | {:error, term()}
  def draw(state, %Frame{} = frame) do
    full? =
      state.line_mode == :full_redraw or is_nil(state.rendered_frame) or
        dimensions_changed?(state.rendered_frame, frame)

    changes = if full?, do: Frame.cells(frame), else: Frame.diff(state.rendered_frame, frame)

    output = [
      ANSI.cursor_hide(),
      if(full?, do: [ANSI.reset(), ANSI.clear_screen(), ANSI.cursor_position(1, 1)], else: []),
      Renderer.render(changes, state.color_mode, state.character_set),
      cursor_sequence(frame.cursor)
    ]

    case TerminalOutput.write(output) do
      :ok -> {:ok, %{state | rendered_frame: frame}}
      {:error, reason} -> {:error, {:terminal_write_failed, reason}}
    end
  end

  @impl true
  @spec flush(t()) :: {:ok, t()}
  def flush(state), do: {:ok, state}

  @impl true
  @spec invalidate(t()) :: {:ok, t()}
  def invalidate(state), do: {:ok, %{state | rendered_frame: nil}}

  @impl true
  @spec clipboard(t(), Clipboard.Operation.t()) :: {:ok, t()} | {:error, term()}
  def clipboard(state, %Clipboard.Operation{} = operation) do
    with {:ok, sequence} <- Clipboard.sequence(operation),
         :ok <- TerminalOutput.write(sequence) do
      {:ok, state}
    else
      {:error, {:clipboard_too_large, _size, _maximum} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:terminal_write_failed, reason}}
    end
  end

  @impl true
  @spec poll_event(t(), non_neg_integer()) ::
          {:ok, TermUI.Backend.event(), t()}
          | {:timeout, t()}
          | {:error, term(), t()}
  def poll_event(state, timeout) do
    EventStream.poll(state, timeout, &read_one_character/0, __MODULE__)
  end

  @impl true
  @spec resize(t(), TermUI.Backend.size()) :: {:ok, t()} | {:error, term()}
  def resize(state, {rows, columns} = size)
      when is_integer(rows) and rows > 0 and is_integer(columns) and columns > 0 do
    case TerminalOutput.write([ANSI.clear_screen(), ANSI.cursor_position(1, 1)]) do
      :ok -> {:ok, %{state | size: size, rendered_frame: nil}}
      {:error, reason} -> {:error, {:terminal_write_failed, reason}}
    end
  end

  defp setup_sequence(state) do
    [
      if(state.alternate_screen, do: ANSI.enter_alternate_screen(), else: []),
      ANSI.cursor_hide(),
      ANSI.clear_screen(),
      ANSI.cursor_position(1, 1),
      if(state.bracketed_paste, do: ANSI.enable_bracketed_paste(), else: []),
      if(state.focus_events, do: ANSI.enable_focus_events(), else: [])
    ]
  end

  defp cursor_sequence(nil), do: ANSI.cursor_hide()
  defp cursor_sequence({column, row}), do: [ANSI.cursor_position(row, column), ANSI.cursor_show()]

  defp dimensions_changed?(previous, current) do
    previous.width != current.width or previous.height != current.height
  end

  defp determine_size(opts, capabilities) do
    case Keyword.get(opts, :size, Map.get(capabilities, :dimensions, {24, 80})) do
      {rows, columns}
      when is_integer(rows) and rows > 0 and is_integer(columns) and columns > 0 ->
        {rows, columns}

      _invalid ->
        {24, 80}
    end
  end

  defp determine_color_mode(capabilities) do
    capabilities
    |> Map.get(:colors, :true_color)
    |> color_mode()
  end

  defp color_mode(:true_color), do: :true_color
  defp color_mode(:color_256), do: :color_256
  defp color_mode(:color_16), do: :color_16
  defp color_mode(:monochrome), do: :monochrome
  defp color_mode(count) when is_integer(count) and count >= 16_777_216, do: :true_color
  defp color_mode(count) when is_integer(count) and count >= 256, do: :color_256
  defp color_mode(count) when is_integer(count) and count >= 16, do: :color_16
  defp color_mode(_other), do: :monochrome

  defp read_one_character do
    case IO.getn("", 1) do
      :eof -> :eof
      {:error, reason} -> {:error, reason}
      data when is_binary(data) -> {:ok, data}
      [byte] when is_integer(byte) -> {:ok, <<byte>>}
      other -> {:error, {:unexpected_io_return, other}}
    end
  end
end
