defmodule TermUI.Widget.Table.Column do
  @moduledoc "A column definition for `TermUI.Widget.Table`."

  @type t :: %__MODULE__{
          key: term(),
          label: String.t(),
          width: pos_integer() | :auto,
          align: :left | :center | :right
        }

  @schema Zoi.struct(__MODULE__, %{
            key: Zoi.any(),
            label: Zoi.string(),
            width:
              Zoi.union([Zoi.integer() |> Zoi.positive(), Zoi.literal(:auto)])
              |> Zoi.default(:auto),
            align: Zoi.enum([:left, :center, :right]) |> Zoi.default(:left)
          })
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for table columns."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates a column definition."
  @spec new(term(), iodata(), keyword()) :: t()
  def new(key, label, opts \\ []) do
    @schema
    |> Zoi.parse!(%__MODULE__{
      key: key,
      label: IO.iodata_to_binary(label),
      width: Keyword.get(opts, :width, :auto),
      align: Keyword.get(opts, :align, :left)
    })
  end
end
