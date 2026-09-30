defmodule TermUI.NativeBuildPolicyTest do
  use ExUnit.Case, async: true

  test "auto mode uses the BEAM-only path when a source tool is absent" do
    find_none = fn _executable -> nil end

    refute :elixir_make in TermUI.MixProject.tty_nif_compilers("auto", find_none, {:unix, :linux})
  end

  test "source mode selects the native compiler when all tools exist" do
    find_all = fn executable -> "/tools/#{executable}" end

    assert :elixir_make in TermUI.MixProject.tty_nif_compilers(
             "source",
             find_all,
             {:unix, :linux}
           )
  end

  test "source mode gives the missing tools and BEAM-only alternatives" do
    find_none = fn _executable -> nil end

    error =
      assert_raise Mix.Error, fn ->
        TermUI.MixProject.tty_nif_compilers("source", find_none, {:unix, :linux})
      end

    assert error.message =~ "make build tool"
    assert error.message =~ "C compiler"
    assert error.message =~ "TERM_UI_TTY_NIF=disabled"
    assert error.message =~ "TermUI.Backend.SSH"
    assert error.message =~ "TermUI.Test.DeterministicBackend"
  end

  test "disabled mode does not select the native compiler" do
    fail_if_called = fn _executable -> flunk("disabled mode must not inspect source tools") end

    refute :elixir_make in TermUI.MixProject.tty_nif_compilers(
             "disabled",
             fail_if_called,
             {:unix, :linux}
           )
  end
end
