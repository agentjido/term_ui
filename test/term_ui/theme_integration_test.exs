defmodule TermUI.ThemeIntegrationTest do
  use ExUnit.Case, async: true

  alias TermUI.Renderer.Style
  alias TermUI.Theme

  setup do
    name = :"theme_integration_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Theme.start_link(name: name, theme: :dark)
    %{server: name, pid: pid}
  end

  describe "application startup" do
    test "starts with default dark theme", %{server: server} do
      theme = Theme.get_theme(server)

      assert theme.name == :dark
      assert theme.colors.background == :black
      assert theme.colors.foreground == :white
    end

    test "starts with specified theme" do
      name = :"startup_test_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Theme.start_link(name: name, theme: :light)

      theme = Theme.get_theme(name)
      assert theme.name == :light
      assert theme.colors.background == :white
    end

    test "starts with custom theme" do
      name = :"custom_startup_#{:erlang.unique_integer([:positive])}"
      {:ok, custom} = Theme.from(name: :my_custom, colors: %{primary: :magenta})
      {:ok, _} = Theme.start_link(name: name, theme: custom)

      theme = Theme.get_theme(name)
      assert theme.name == :my_custom
      assert theme.colors.primary == :magenta
    end
  end

  describe "theme switching" do
    test "switch updates all colors", %{server: server} do
      # Initial dark
      assert Theme.get_color(:background, server) == :black
      assert Theme.get_color(:foreground, server) == :white

      # Switch to light
      :ok = Theme.set_theme(:light, server)

      assert Theme.get_color(:background, server) == :white
      assert Theme.get_color(:foreground, server) == :black
    end

    test "switch updates semantic colors", %{server: server} do
      # Dark theme has :cyan for info
      assert Theme.get_semantic(:info, server) == :cyan

      # Light theme has :blue for info
      :ok = Theme.set_theme(:light, server)
      assert Theme.get_semantic(:info, server) == :blue
    end

    test "switch updates component styles", %{server: server} do
      dark_button = Theme.get_component_style(:button, :normal, server)

      :ok = Theme.set_theme(:light, server)
      light_button = Theme.get_component_style(:button, :normal, server)

      # Colors should differ
      assert dark_button.fg != light_button.fg or dark_button.bg != light_button.bg
    end

    test "subscribers notified on switch", %{server: server} do
      :ok = Theme.subscribe(server)

      :ok = Theme.set_theme(:light, server)

      assert_receive {:theme_changed, theme}
      assert theme.name == :light
    end

    test "multiple switches work correctly", %{server: server} do
      themes = [:light, :high_contrast, :dark, :light]

      for theme_name <- themes do
        :ok = Theme.set_theme(theme_name, server)
        theme = Theme.get_theme(server)
        assert theme.name == theme_name
      end
    end
  end

  describe "custom theme integration" do
    test "create and apply custom theme", %{server: server} do
      {:ok, custom} =
        Theme.from(
          base: :dark,
          name: :corporate,
          colors: %{primary: :cyan, accent: :yellow},
          semantic: %{success: :bright_green}
        )

      :ok = Theme.set_theme(custom, server)

      assert Theme.get_theme(server).name == :corporate
      assert Theme.get_color(:primary, server) == :cyan
      assert Theme.get_semantic(:success, server) == :bright_green
      # Inherited from dark
      assert Theme.get_color(:background, server) == :black
    end

    test "custom theme with component style overrides", %{server: server} do
      custom_button = %{
        normal: Style.new() |> Style.fg(:yellow) |> Style.bg(:blue)
      }

      {:ok, custom} =
        Theme.from(
          name: :custom,
          components: %{button: custom_button}
        )

      :ok = Theme.set_theme(custom, server)

      button = Theme.get_component_style(:button, :normal, server)
      assert button.fg == :yellow
      assert button.bg == :blue

      # Other button variants preserved from base (dark theme defaults)
      focused = Theme.get_component_style(:button, :focused, server)
      assert focused.fg == :white
      assert focused.bg == :blue
      assert Style.has_attr?(focused, :bold)
    end

    test "theme validation catches errors" do
      incomplete_theme = %Theme{
        name: :incomplete,
        colors: %{background: :black},
        semantic: %{},
        components: %{}
      }

      {:error, errors} = Theme.validate(incomplete_theme)
      assert errors != []
    end
  end

  describe "component style resolution" do
    test "get component style for all built-in components", %{server: server} do
      components = [:button, :text_input, :text, :border]
      variants = [:normal, :focused, :disabled]

      for component <- components do
        for variant <- variants do
          style = Theme.get_component_style(component, variant, server)
          # Not all components have all variants
          if style do
            assert %Style{} = style
          end
        end
      end
    end

    test "style_from_theme with overrides", %{server: server} do
      # Get button style with fg override
      style = Theme.style_from_theme(:button, :normal, [fg: :magenta], server)

      assert style.fg == :magenta
      # bg from dark theme button normal
      assert style.bg == :bright_black
    end

    test "style_from_theme falls back for unknown component", %{server: server} do
      style = Theme.style_from_theme(:nonexistent, :normal, [fg: :blue], server)

      assert style.fg == :blue
    end
  end

  describe "color and semantic access" do
    test "all base colors accessible", %{server: server} do
      colors = [:background, :foreground, :primary, :secondary, :accent]

      for color <- colors do
        value = Theme.get_color(color, server)
        assert value != nil, "Missing color: #{color}"
      end
    end

    test "all semantic colors accessible", %{server: server} do
      semantics = [:success, :warning, :error, :info, :muted]

      for semantic <- semantics do
        value = Theme.get_semantic(semantic, server)
        assert value != nil, "Missing semantic: #{semantic}"
      end
    end

    test "colors consistent across theme access methods", %{server: server} do
      theme = Theme.get_theme(server)

      # Direct theme access vs helper function
      assert theme.colors.primary == Theme.get_color(:primary, server)
      assert theme.semantic.error == Theme.get_semantic(:error, server)
    end
  end

  describe "multi-subscriber scenarios" do
    test "multiple subscribers all notified", %{server: server} do
      # Spawn multiple subscriber processes
      parent = self()

      pids =
        for i <- 1..3 do
          spawn(fn ->
            Theme.subscribe(server)
            send(parent, {:subscribed, i})

            receive do
              {:theme_changed, theme} ->
                send(parent, {:received, i, theme.name})
            end
          end)
        end

      # Guarantee cleanup even if test fails
      on_exit(fn ->
        for pid <- pids, Process.alive?(pid), do: Process.exit(pid, :kill)
      end)

      # Wait for all subscriptions
      for i <- 1..3 do
        assert_receive {:subscribed, ^i}
      end

      # Switch theme
      :ok = Theme.set_theme(:light, server)

      # All should receive
      for i <- 1..3 do
        assert_receive {:received, ^i, :light}
      end
    end

    test "dead subscriber cleaned up", %{server: server} do
      # Subscribe from a process that will die
      pid =
        spawn(fn ->
          Theme.subscribe(server)

          receive do
            :done -> :ok
          end
        end)

      # Guarantee cleanup even if test fails
      on_exit(fn ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
      end)

      # Kill the subscriber
      Process.exit(pid, :kill)
      Process.sleep(50)

      # Theme switch should not error
      :ok = Theme.set_theme(:light, server)
    end
  end

  describe "theme persistence simulation" do
    test "theme survives server restart with same config" do
      # Start with light theme
      name1 = :"persist_test_1_#{:erlang.unique_integer([:positive])}"
      {:ok, pid1} = Theme.start_link(name: name1, theme: :light)
      assert Theme.get_theme(name1).name == :light

      # Stop it
      GenServer.stop(pid1)

      # Start new server with same theme config (simulating persistence)
      name2 = :"persist_test_2_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = Theme.start_link(name: name2, theme: :light)
      assert Theme.get_theme(name2).name == :light
    end
  end

  describe "high contrast accessibility" do
    test "high contrast uses bright colors", %{server: server} do
      :ok = Theme.set_theme(:high_contrast, server)

      # Check that colors are bright variants
      fg = Theme.get_color(:foreground, server)
      assert fg == :bright_white

      success = Theme.get_semantic(:success, server)
      assert success == :bright_green

      error = Theme.get_semantic(:error, server)
      assert error == :bright_red
    end

    test "high contrast button has bold", %{server: server} do
      :ok = Theme.set_theme(:high_contrast, server)

      button = Theme.get_component_style(:button, :normal, server)
      assert Style.has_attr?(button, :bold)
    end
  end
end
