defmodule TermUI.Test.RawModePtyProbe do
  alias TermUI.Terminal.RawMode

  def run do
    options =
      if System.get_env("TERM_UI_CONSOLE_FORCE_NATIVE") == "1",
        do: [signals_api?: false],
        else: []

    case RawMode.enter(options) do
      {:ok, session} ->
        IO.write("__TERM_UI_READY__\n")
        bytes = read_bytes(4, [])
        exit_result = RawMode.exit(session)
        IO.write("__TERM_UI_RESULT__:#{Base.encode16(bytes)}:#{inspect(exit_result)}\n")

      {:error, reason} ->
        IO.write("__TERM_UI_ERROR__:#{inspect(reason)}\n")
    end
  end

  defp read_bytes(0, bytes), do: IO.iodata_to_binary(Enum.reverse(bytes))

  defp read_bytes(remaining, bytes) do
    case IO.getn("", 1) do
      data when is_binary(data) and byte_size(data) == 1 ->
        read_bytes(remaining - 1, [data | bytes])

      [byte] when is_integer(byte) ->
        read_bytes(remaining - 1, [<<byte>> | bytes])

      other ->
        IO.write("__TERM_UI_READ_ERROR__:#{inspect(other)}\n")
        System.halt(2)
    end
  end
end

TermUI.Test.RawModePtyProbe.run()
