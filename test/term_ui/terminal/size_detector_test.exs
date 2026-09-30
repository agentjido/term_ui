defmodule TermUI.Terminal.SizeDetectorTest do
  use ExUnit.Case, async: false

  alias TermUI.Terminal.SizeDetector

  setup do
    original_lines = System.get_env("LINES")
    original_columns = System.get_env("COLUMNS")

    on_exit(fn ->
      restore_env("LINES", original_lines)
      restore_env("COLUMNS", original_columns)
    end)

    :ok
  end

  test "validates explicit terminal sizes and limits" do
    assert SizeDetector.max_dimension() == 9_999
    assert {:ok, {24, 80}} = SizeDetector.detect(size: {24, 80})
    assert {:ok, {9_999, 9_999}} = SizeDetector.validate_size(9_999, 9_999)

    for invalid <- [{0, 80}, {24, 0}, {-1, 80}, {24, 10_000}, {24.0, 80}, :bad] do
      assert {:error, :invalid_size} = SizeDetector.detect(size: invalid)
    end
  end

  test "reads bounded dimensions from the environment" do
    System.put_env("LINES", "41")
    System.put_env("COLUMNS", "132")

    assert {:ok, {41, 132}} = SizeDetector.detect_from_env()
  end

  test "rejects missing, malformed, and oversized environment dimensions" do
    for {lines, columns} <- [
          {nil, nil},
          {"x", "80"},
          {"24tail", "80"},
          {"0", "80"},
          {"24", "10000"}
        ] do
      restore_env("LINES", lines)
      restore_env("COLUMNS", columns)
      assert {:error, :env_detection_failed} = SizeDetector.detect_from_env()
    end
  end

  test "automatic detection uses valid environment dimensions as a fallback" do
    System.put_env("LINES", "37")
    System.put_env("COLUMNS", "111")

    assert {:ok, {37, 111}} = SizeDetector.auto_detect()
    assert {:ok, {37, 111}} = SizeDetector.detect()
  end

  test "direct IO and stty detection return only documented results" do
    assert_documented_result(SizeDetector.detect_from_io(), [
      :io_detection_failed,
      :io_not_available
    ])

    assert_documented_result(SizeDetector.detect_from_stty(), [
      :stty_failed,
      :stty_timeout,
      :stty_parse_failed
    ])
  end

  defp assert_documented_result({:ok, {rows, columns}}, _errors) do
    assert rows in 1..SizeDetector.max_dimension()
    assert columns in 1..SizeDetector.max_dimension()
  end

  defp assert_documented_result({:error, reason}, errors), do: assert(reason in errors)

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
