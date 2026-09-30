defmodule TermUI.Event do
  @moduledoc """
  Normalized input from a terminal backend.

  Printable input is `Text`. Named or modified keys are `Key`. Paste, mouse,
  resize, and focus input have separate types. Use `TermUI.Input` to normalize
  data from an external input adapter. Applications do not parse terminal byte
  sequences.
  """

  @type t ::
          __MODULE__.Key.t()
          | __MODULE__.Text.t()
          | __MODULE__.Paste.t()
          | __MODULE__.Mouse.t()
          | __MODULE__.Resize.t()
          | __MODULE__.Focus.t()

  defmodule Key do
    @moduledoc "A named or modified key press."
    @type t :: %__MODULE__{key: atom() | String.t(), modifiers: [atom()], timestamp: integer()}
    @schema Zoi.struct(__MODULE__, %{
              key: Zoi.union([Zoi.atom(), Zoi.string()]),
              modifiers: Zoi.array(Zoi.atom()) |> Zoi.default([]),
              timestamp: Zoi.integer() |> Zoi.default(0)
            })
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc false
    def new(key, opts) when is_atom(key) or is_binary(key) do
      %__MODULE__{
        key: key,
        modifiers: opts |> Keyword.get(:modifiers, []) |> Enum.uniq(),
        timestamp: Keyword.get(opts, :timestamp, System.monotonic_time(:millisecond))
      }
    end
  end

  defmodule Text do
    @moduledoc "Printable Unicode text input."
    @type t :: %__MODULE__{text: String.t(), timestamp: integer()}
    @schema Zoi.struct(__MODULE__, %{
              text: Zoi.string() |> Zoi.min(1),
              timestamp: Zoi.integer() |> Zoi.default(0)
            })
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc false
    def new(text, opts) when is_binary(text) and text != "" do
      %__MODULE__{
        text: text,
        timestamp: Keyword.get(opts, :timestamp, System.monotonic_time(:millisecond))
      }
    end
  end

  defmodule Paste do
    @moduledoc "Text received in one bracketed-paste operation."
    @type t :: %__MODULE__{content: String.t(), timestamp: integer()}
    @schema Zoi.struct(__MODULE__, %{
              content: Zoi.string(),
              timestamp: Zoi.integer() |> Zoi.default(0)
            })
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc false
    def new(content, opts) when is_binary(content) do
      %__MODULE__{
        content: content,
        timestamp: Keyword.get(opts, :timestamp, System.monotonic_time(:millisecond))
      }
    end
  end

  defmodule Mouse do
    @moduledoc "A normalized mouse action."
    @type action :: :press | :release | :move | :drag | :scroll_up | :scroll_down
    @type button :: :left | :middle | :right | nil
    @type t :: %__MODULE__{
            action: action(),
            button: button(),
            x: non_neg_integer(),
            y: non_neg_integer(),
            modifiers: [atom()],
            timestamp: integer()
          }
    @schema Zoi.struct(__MODULE__, %{
              action: Zoi.enum([:press, :release, :move, :drag, :scroll_up, :scroll_down]),
              button: Zoi.enum([:left, :middle, :right, nil]),
              x: Zoi.integer() |> Zoi.non_negative(),
              y: Zoi.integer() |> Zoi.non_negative(),
              modifiers: Zoi.array(Zoi.atom()) |> Zoi.default([]),
              timestamp: Zoi.integer() |> Zoi.default(0)
            })
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc false
    def new(action, button, x, y, opts)
        when action in [:press, :release, :move, :drag, :scroll_up, :scroll_down] and
               button in [:left, :middle, :right, nil] and is_integer(x) and x >= 0 and
               is_integer(y) and y >= 0 do
      %__MODULE__{
        action: action,
        button: button,
        x: x,
        y: y,
        modifiers: opts |> Keyword.get(:modifiers, []) |> Enum.uniq(),
        timestamp: Keyword.get(opts, :timestamp, System.monotonic_time(:millisecond))
      }
    end
  end

  defmodule Resize do
    @moduledoc "A terminal size change in columns and rows."
    @type t :: %__MODULE__{width: pos_integer(), height: pos_integer(), timestamp: integer()}
    @schema Zoi.struct(__MODULE__, %{
              width: Zoi.integer() |> Zoi.positive(),
              height: Zoi.integer() |> Zoi.positive(),
              timestamp: Zoi.integer() |> Zoi.default(0)
            })
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc false
    def new(width, height, opts)
        when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
      %__MODULE__{
        width: width,
        height: height,
        timestamp: Keyword.get(opts, :timestamp, System.monotonic_time(:millisecond))
      }
    end
  end

  defmodule Focus do
    @moduledoc "A terminal focus change."
    @type t :: %__MODULE__{action: :gained | :lost, timestamp: integer()}
    @schema Zoi.struct(__MODULE__, %{
              action: Zoi.enum([:gained, :lost]),
              timestamp: Zoi.integer() |> Zoi.default(0)
            })
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc false
    def new(action, opts) when action in [:gained, :lost] do
      %__MODULE__{
        action: action,
        timestamp: Keyword.get(opts, :timestamp, System.monotonic_time(:millisecond))
      }
    end
  end

  @doc "Creates a named or modified key event."
  @spec key(atom() | String.t(), keyword()) :: Key.t()
  def key(key, opts \\ []), do: Key.new(key, opts)

  @doc "Creates a printable text event."
  @spec text(String.t(), keyword()) :: Text.t()
  def text(text, opts \\ []), do: Text.new(text, opts)

  @doc "Creates a bracketed-paste event."
  @spec paste(String.t(), keyword()) :: Paste.t()
  def paste(content, opts \\ []), do: Paste.new(content, opts)

  @doc "Creates a mouse event."
  @spec mouse(Mouse.action(), Mouse.button(), non_neg_integer(), non_neg_integer(), keyword()) ::
          Mouse.t()
  def mouse(action, button, x, y, opts \\ []), do: Mouse.new(action, button, x, y, opts)

  @doc "Creates a resize event."
  @spec resize(pos_integer(), pos_integer(), keyword()) :: Resize.t()
  def resize(width, height, opts \\ []), do: Resize.new(width, height, opts)

  @doc "Creates a focus event."
  @spec focus(:gained | :lost, keyword()) :: Focus.t()
  def focus(action, opts \\ []), do: Focus.new(action, opts)

  @doc "Returns the Zoi schema for all normalized terminal events."
  @spec schema() :: Zoi.schema()
  def schema do
    Zoi.union([
      Key.schema(),
      Text.schema(),
      Paste.schema(),
      Mouse.schema(),
      Resize.schema(),
      Focus.schema()
    ])
  end

  @doc "Returns the event type."
  @spec type(t()) :: :key | :text | :paste | :mouse | :resize | :focus
  def type(%Key{}), do: :key
  def type(%Text{}), do: :text
  def type(%Paste{}), do: :paste
  def type(%Mouse{}), do: :mouse
  def type(%Resize{}), do: :resize
  def type(%Focus{}), do: :focus

  @doc "Returns true when the event contains a modifier."
  @spec has_modifier?(Key.t() | Mouse.t(), atom()) :: boolean()
  def has_modifier?(%{modifiers: modifiers}, modifier), do: modifier in modifiers
end
