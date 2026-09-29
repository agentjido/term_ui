defmodule TermUI.Terminal.RawModeTest do
  use ExUnit.Case, async: true

  alias TermUI.Terminal.{RawMode, TtyNif}

  defmodule FakeTtyNif do
    def ensure_loaded do
      send(self(), :ensure_tty_nif_loaded)
      Process.get({__MODULE__, :load_result}, :ok)
    end

    def disable_control_flags do
      send(self(), :disable_control_flags)
      Process.get({__MODULE__, :disable_result}, {:ok, {1, 2}})
    end

    def restore_control_flags(flags) do
      send(self(), {:restore_control_flags, flags})
      Process.get({__MODULE__, :restore_result}, :ok)
    end
  end

  @tag :tty_nif
  test "the source-built NIF loads on request" do
    assert :ok = TtyNif.ensure_loaded()
    assert TtyNif.loaded?()
  end

  test "legacy entry disables controls and exit restores the saved flags" do
    shell_start = successful_shell_start()

    assert {:ok, {:native, {1, 2}} = session} =
             RawMode.enter(
               shell_start: shell_start,
               signals_api?: false,
               tty_nif: FakeTtyNif
             )

    assert_receive {:shell_start, {:noshell, :raw}}
    assert_receive :ensure_tty_nif_loaded
    assert_receive :disable_control_flags

    assert :ok =
             RawMode.exit(session,
               shell_start: shell_start,
               tty_nif: FakeTtyNif
             )

    assert_receive {:shell_start, {:noshell, :cooked}}
    assert_receive {:restore_control_flags, {1, 2}}
  end

  test "the OTP signals API does not call the native fallback" do
    shell_start = successful_shell_start()

    assert {:ok, :otp_signals} =
             RawMode.enter(
               shell_start: shell_start,
               signals_api?: true,
               tty_nif: FakeTtyNif
             )

    assert_receive {:shell_start, {:noshell, %{mode: :raw, signals: false}}}
    refute_receive :disable_control_flags
  end

  test "an unavailable signals API uses the native fallback" do
    shell_start = fn
      {:noshell, :raw} = argument ->
        send(self(), {:shell_start, argument})
        :ok
    end

    assert {:ok, {:native, {1, 2}}} =
             RawMode.enter(
               shell_start: shell_start,
               signals_api?: true,
               tty_nif: FakeTtyNif
             )

    assert_receive {:shell_start, {:noshell, :raw}}
    assert_receive :disable_control_flags
  end

  test "a native setup failure returns the terminal to cooked mode" do
    Process.put({FakeTtyNif, :disable_result}, {:error, :not_loaded})
    shell_start = successful_shell_start()

    assert {:error, {:control_flags_unavailable, :not_loaded, :ok}} =
             RawMode.enter(
               shell_start: shell_start,
               signals_api?: false,
               tty_nif: FakeTtyNif
             )

    assert_receive {:shell_start, {:noshell, :raw}}
    assert_receive :disable_control_flags
    assert_receive {:shell_start, {:noshell, :cooked}}
  end

  test "an unavailable native module returns the terminal to cooked mode" do
    Process.put({FakeTtyNif, :load_result}, {:error, :missing_artifact})
    shell_start = successful_shell_start()

    assert {:error, {:control_flags_unavailable, :missing_artifact, :ok}} =
             RawMode.enter(
               shell_start: shell_start,
               signals_api?: false,
               tty_nif: FakeTtyNif
             )

    assert_receive {:shell_start, {:noshell, :raw}}
    assert_receive :ensure_tty_nif_loaded
    refute_receive :disable_control_flags
    assert_receive {:shell_start, {:noshell, :cooked}}
  end

  test "exit attempts flag restoration when cooked-mode restoration fails" do
    Process.put({FakeTtyNif, :restore_result}, {:error, :restore_failed})

    shell_start = fn argument ->
      send(self(), {:shell_start, argument})
      {:error, :cooked_failed}
    end

    assert {:error, {:cooked_mode, :cooked_failed, :control_flags, :restore_failed}} =
             RawMode.exit({:native, {3, 4}},
               shell_start: shell_start,
               tty_nif: FakeTtyNif
             )

    assert_receive {:shell_start, {:noshell, :cooked}}
    assert_receive {:restore_control_flags, {3, 4}}
  end

  test "resume disables controls but exit retains the original saved flags" do
    session = {:native, {3, 4}}
    Process.put({FakeTtyNif, :disable_result}, {:ok, {8, 9}})
    opts = [tty_nif: FakeTtyNif, shell_start: successful_shell_start()]

    assert :ok = RawMode.resume(session, opts)
    assert_receive :disable_control_flags
    refute_receive {:shell_start, _argument}

    assert :ok = RawMode.exit(session, opts)
    assert_receive {:shell_start, {:noshell, :cooked}}
    assert_receive {:restore_control_flags, {3, 4}}
  end

  test "resume keeps the OTP signals API in its existing mode" do
    assert :ok = RawMode.resume(:otp_signals, tty_nif: FakeTtyNif)
    refute_receive :disable_control_flags
  end

  test "resume reports a native flag failure" do
    Process.put({FakeTtyNif, :disable_result}, {:error, :not_tty})

    assert {:error, {:control_flags, :not_tty}} =
             RawMode.resume({:native, {1, 2}}, tty_nif: FakeTtyNif)
  end

  test "resume reports an unavailable native module without replacing the session" do
    assert {:error, {:control_flags, {:native_exception, %UndefinedFunctionError{}}}} =
             RawMode.resume({:native, {3, 4}}, tty_nif: NotAvailableTtyNif)
  end

  defp successful_shell_start do
    fn argument ->
      send(self(), {:shell_start, argument})
      :ok
    end
  end
end
