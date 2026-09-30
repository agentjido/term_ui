defmodule TermUI.Clipboard.Operation do
  @moduledoc "Clipboard operation data for one terminal backend."

  @type target :: :clipboard | :primary | :secondary
  @type t :: %__MODULE__{
          kind: :write | :clear,
          target: target(),
          content: String.t(),
          max_bytes: pos_integer()
        }

  @schema Zoi.struct(__MODULE__, %{
            kind: Zoi.enum([:write, :clear]),
            target: Zoi.enum([:clipboard, :primary, :secondary]) |> Zoi.default(:clipboard),
            content: Zoi.string() |> Zoi.default(""),
            max_bytes: Zoi.integer() |> Zoi.positive() |> Zoi.default(100_000)
          })

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for clipboard operations."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema
end
