defmodule TermUI.ConfigTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias TermUI.Backend.{CapabilityFilter, Raw, TTY}
  alias TermUI.Config

  @legacy_keys [:backend, :color_mode, :character_set, :render_interval, :iex_compatible]

  setup do
    previous = Map.new(@legacy_keys, &{&1, Application.fetch_env(:term_ui, &1)})
    Enum.each(@legacy_keys, &Application.delete_env(:term_ui, &1))
    Config.reset_deprecation_warnings()

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:term_ui, key, value)
        {key, :error} -> Application.delete_env(:term_ui, key)
      end)

      Config.reset_deprecation_warnings()
    end)

    :ok
  end

  test "maps every direct v1 key and emits each warning one time" do
    Application.put_env(:term_ui, :backend, :tty)
    Application.put_env(:term_ui, :color_mode, :color_256)
    Application.put_env(:term_ui, :character_set, :ascii)
    Application.put_env(:term_ui, :render_interval, 33)

    log =
      capture_log(fn ->
        assert {:ok, opts} = Config.merge_runtime_options([])
        assert opts[:backend] == :tty
        assert opts[:render_interval] == 33
        assert opts[:backend_opts][:color_mode] == :color_256
        assert opts[:backend_opts][:character_set] == :ascii

        assert {:ok, _same_values} = Config.merge_runtime_options([])
      end)

    for key <- [:backend, :color_mode, :character_set, :render_interval] do
      assert count_warning(log, key) == 1
    end

    assert log =~ ":backend runtime option"
    assert log =~ ":backend_opts option :color_mode"
    assert log =~ ":backend_opts option :character_set"
    assert log =~ ":render_interval runtime option"
  end

  test "maps all supported backend and IEx values" do
    for backend <- [:auto, :raw, :tty] do
      Application.put_env(:term_ui, :backend, backend)
      assert {:ok, opts} = Config.merge_runtime_options([])
      assert opts[:backend] == backend
    end

    Application.delete_env(:term_ui, :backend)

    for {iex_value, expected_backend} <- [{:auto, :auto}, {false, :auto}, {true, :tty}] do
      Application.put_env(:term_ui, :iex_compatible, iex_value)
      assert {:ok, opts} = Config.merge_runtime_options([])
      assert opts[:backend] == expected_backend
    end
  end

  test "maps all supported color and character values" do
    for color <- [:auto, :true_color, :color_256, :color_16, :monochrome] do
      Application.put_env(:term_ui, :color_mode, color)
      assert {:ok, opts} = Config.merge_runtime_options([])
      assert opts[:backend_opts][:color_mode] == color
    end

    for character_set <- [:auto, :unicode, :ascii] do
      Application.put_env(:term_ui, :character_set, character_set)
      assert {:ok, opts} = Config.merge_runtime_options([])
      assert opts[:backend_opts][:character_set] == character_set
    end
  end

  test "explicit v2 values take precedence and do not read old keys" do
    Application.put_env(:term_ui, :backend, :raw)
    Application.put_env(:term_ui, :color_mode, :monochrome)
    Application.put_env(:term_ui, :character_set, :ascii)
    Application.put_env(:term_ui, :render_interval, 99)
    Application.put_env(:term_ui, :iex_compatible, true)

    explicit = [
      backend: :tty,
      backend_opts: [color_mode: :color_16, character_set: :unicode],
      render_interval: 20
    ]

    log =
      capture_log(fn ->
        assert {:ok, ^explicit} = Config.merge_runtime_options(explicit)
      end)

    assert log == ""
  end

  test "backend tuple options also take precedence" do
    Application.put_env(:term_ui, :color_mode, :monochrome)
    Application.put_env(:term_ui, :character_set, :ascii)

    explicit = [backend: {TTY, [color_mode: :color_16, character_set: :unicode]}]
    assert {:ok, ^explicit} = Config.merge_runtime_options(explicit)
  end

  test "an unsupported old backend returns a clear error and warning" do
    Application.put_env(:term_ui, :backend, :component_backend)

    log =
      capture_log(fn ->
        assert {:error,
                {:invalid_legacy_config, :backend, :component_backend,
                 "expected one of :auto, :raw, :tty"}} = Config.merge_runtime_options([])
      end)

    assert count_warning(log, :backend) == 1
    assert log =~ "matching v2 runtime or backend option"
  end

  test "capability preferences can reduce but never increase reported support" do
    limited = %{colors: :color_16, unicode: false}

    assert CapabilityFilter.filter(limited, color_mode: :true_color, character_set: :unicode) ==
             limited

    assert CapabilityFilter.filter(
             %{colors: :true_color, unicode: true},
             color_mode: :monochrome,
             character_set: :ascii
           ) == %{colors: :monochrome, unicode: false}

    capture_io(fn ->
      assert {:ok, tty} =
               TTY.init(
                 size: {2, 5},
                 capabilities: limited,
                 color_mode: :true_color,
                 character_set: :unicode,
                 bracketed_paste: false,
                 focus_events: false
               )

      assert tty.color_mode == :color_16
      assert tty.character_set == :ascii
      assert TTY.capabilities(tty).colors == :color_16
      assert TTY.capabilities(tty).unicode == false
      TTY.shutdown(tty, :normal)

      assert {:ok, raw} =
               Raw.init(
                 size: {2, 5},
                 color_mode: :color_16,
                 character_set: :ascii,
                 alternate_screen: false,
                 bracketed_paste: false,
                 focus_events: false
               )

      assert Raw.capabilities(raw).colors == :color_16
      assert Raw.capabilities(raw).unicode == false
      Raw.shutdown(raw, :normal)
    end)
  end

  defp count_warning(log, key) do
    log
    |> String.split("\n")
    |> Enum.count(&String.contains?(&1, "config :term_ui, #{inspect(key)} is deprecated"))
  end
end
