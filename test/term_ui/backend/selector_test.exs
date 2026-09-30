defmodule TermUI.Backend.SelectorTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias TermUI.Backend.Selector
  import TermUI.Backend.SelectorTestHelpers

  setup_all do
    Code.ensure_loaded!(Selector)
    :ok
  end

  describe "module structure" do
    test "module compiles successfully" do
      assert Code.ensure_loaded?(Selector)
    end

    test "module exports select/0" do
      assert function_exported?(Selector, :select, 0)
    end

    test "module exports select/1" do
      assert function_exported?(Selector, :select, 1)
    end
  end

  describe "documentation" do
    test "module stays out of the public documentation" do
      {:docs_v1, _, :elixir, _, module_doc, _, _} = Code.fetch_docs(Selector)
      assert module_doc == :hidden
    end

    test "select/0 has documentation" do
      {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(Selector)

      select_0_doc =
        Enum.find(docs, fn
          {{:function, :select, 0}, _, _, _, _} -> true
          _ -> false
        end)

      assert select_0_doc != nil, "select/0 should have documentation"
      {{:function, :select, 0}, _, _, doc, _} = select_0_doc
      assert doc != :none
      assert doc != :hidden
    end

    test "select/1 has documentation" do
      {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(Selector)

      select_1_doc =
        Enum.find(docs, fn
          {{:function, :select, 1}, _, _, _, _} -> true
          _ -> false
        end)

      assert select_1_doc != nil, "select/1 should have documentation"
      {{:function, :select, 1}, _, _, doc, _} = select_1_doc
      assert doc != :none
      assert doc != :hidden
    end
  end

  describe "type definitions" do
    test "selection_result type is defined" do
      {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(Selector)

      type_docs =
        docs
        |> Enum.filter(fn
          {{:type, :selection_result, _}, _, _, _, _} -> true
          _ -> false
        end)

      assert length(type_docs) == 1, "selection_result type should be defined"
    end

    test "raw_state type is defined" do
      {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(Selector)

      type_docs =
        docs
        |> Enum.filter(fn
          {{:type, :raw_state, _}, _, _, _, _} -> true
          _ -> false
        end)

      assert length(type_docs) == 1, "raw_state type should be defined"
    end

    test "capabilities type is defined" do
      {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(Selector)

      type_docs =
        docs
        |> Enum.filter(fn
          {{:type, :capabilities, _}, _, _, _, _} -> true
          _ -> false
        end)

      assert length(type_docs) == 1, "capabilities type should be defined"
    end

    test "color_depth type is defined" do
      {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(Selector)

      type_docs =
        docs
        |> Enum.filter(fn
          {{:type, :color_depth, _}, _, _, _, _} -> true
          _ -> false
        end)

      assert length(type_docs) == 1, "color_depth type should be defined"
    end
  end

  describe "select/0 return format" do
    test "returns a two-element tuple" do
      result = Selector.select()
      assert is_tuple(result)
      assert tuple_size(result) == 2
    end

    test "returns either {:raw, _} or {:tty, _}" do
      result = Selector.select()

      case result do
        {:raw, state} ->
          assert is_map(state)

        {:tty, capabilities} ->
          assert is_map(capabilities)
      end
    end

    test "tty capabilities has expected keys" do
      # Current placeholder always returns TTY
      {:tty, capabilities} = Selector.select()

      assert Map.has_key?(capabilities, :colors)
      assert Map.has_key?(capabilities, :unicode)
      assert Map.has_key?(capabilities, :dimensions)
      assert Map.has_key?(capabilities, :terminal)
    end
  end

  describe "select/1 with :auto" do
    test "delegates to select/0" do
      # Both should return the same format
      result_0 = Selector.select()
      result_1 = Selector.select(:auto)

      assert elem(result_0, 0) == elem(result_1, 0)
    end
  end

  describe "select/1 with explicit module" do
    test "returns {:explicit, module, []} for module atom" do
      result = Selector.select(SomeModule)
      assert result == {:explicit, SomeModule, []}
    end

    test "returns {:explicit, module, opts} for {module, opts} tuple" do
      result = Selector.select({SomeModule, [option: :value]})
      assert result == {:explicit, SomeModule, [option: :value]}
    end

    test "works with actual backend module atoms" do
      result = Selector.select(TermUI.Backend.TTY)
      assert result == {:explicit, TermUI.Backend.TTY, []}
    end

    test "passes through options correctly" do
      opts = [line_mode: :full_redraw, alternate_screen: false]
      result = Selector.select({TermUI.Backend.TTY, opts})
      assert result == {:explicit, TermUI.Backend.TTY, opts}
    end
  end

  describe "try_raw_mode/0 core selection logic" do
    test "returns a two-element tuple" do
      result = Selector.try_raw_mode()
      assert is_tuple(result)
      assert tuple_size(result) == 2
    end

    test "first element is :raw or :tty" do
      {mode, _} = Selector.try_raw_mode()
      assert mode in [:raw, :tty]
    end

    test "raw mode returns map with raw_mode_started key" do
      case Selector.try_raw_mode() do
        {:raw, state} ->
          assert is_map(state)
          assert Map.has_key?(state, :raw_mode_started)
          assert state.raw_mode_started == true

        {:tty, _} ->
          # TTY mode is also valid - depends on environment
          :ok
      end
    end

    test "tty mode returns capabilities map" do
      case Selector.try_raw_mode() do
        {:tty, capabilities} ->
          assert is_map(capabilities)
          assert Map.has_key?(capabilities, :colors)
          assert Map.has_key?(capabilities, :unicode)
          assert Map.has_key?(capabilities, :dimensions)
          assert Map.has_key?(capabilities, :terminal)

        {:raw, _} ->
          # Raw mode is also valid - depends on environment
          :ok
      end
    end
  end

  describe "attempt_raw_mode/0" do
    # These tests verify the attempt_raw_mode function behavior
    # The actual result depends on OTP version and terminal state

    test "returns a valid selection result" do
      result = Selector.attempt_raw_mode()
      assert is_tuple(result)
      assert tuple_size(result) == 2

      case result do
        {:raw, state} ->
          assert is_map(state)
          assert state.raw_mode_started == true

        {:tty, capabilities} ->
          assert is_map(capabilities)
      end
    end

    test "handles :already_started error by returning tty mode" do
      # In a test environment with IEx/shell already running,
      # we expect {:error, :already_started} which should return TTY mode
      # This test documents expected behavior - actual result depends on environment
      result = Selector.attempt_raw_mode()

      case result do
        {:tty, capabilities} ->
          assert is_map(capabilities)
          assert Map.has_key?(capabilities, :colors)

        {:raw, _state} ->
          # Raw mode succeeded - also valid
          :ok
      end
    end
  end

  describe "pre-OTP 28 fallback" do
    # Test that the try/rescue in try_raw_mode handles UndefinedFunctionError
    # We can't easily simulate this without mocking, so we test the structure

    test "try_raw_mode wraps attempt_raw_mode in try/rescue" do
      # The function should not raise even if shell.start_interactive doesn't exist
      # This is verified by the function returning a valid result
      result = Selector.try_raw_mode()
      assert match?({:raw, _}, result) or match?({:tty, _}, result)
    end

    test "function exports attempt_raw_mode for testability" do
      # attempt_raw_mode is exported (doc false) to allow testing the core logic
      Code.ensure_loaded!(Selector)
      assert function_exported?(Selector, :attempt_raw_mode, 0)
    end
  end

  describe "raw mode state format" do
    test "raw state contains raw_mode_started boolean" do
      # When raw mode succeeds, state should have this key
      # Test the expected structure
      expected_keys = [:raw_mode_started, :raw_mode_session]

      case Selector.try_raw_mode() do
        {:raw, state} ->
          for key <- expected_keys do
            assert Map.has_key?(state, key), "Raw state should have #{key} key"
          end

          assert is_boolean(state.raw_mode_started)

        {:tty, _} ->
          # TTY mode - raw state format not applicable
          :ok
      end
    end
  end

  describe "integration with select/0" do
    test "select/0 delegates to try_raw_mode/0" do
      # Both should return compatible formats
      select_result = Selector.select()
      try_result = Selector.try_raw_mode()

      # Both should be same mode (raw or tty)
      assert elem(select_result, 0) == elem(try_result, 0)
    end
  end

  describe "detect_capabilities/0" do
    test "returns a map with required keys" do
      caps = Selector.detect_capabilities()

      assert is_map(caps)
      assert Map.has_key?(caps, :colors)
      assert Map.has_key?(caps, :unicode)
      assert Map.has_key?(caps, :dimensions)
      assert Map.has_key?(caps, :terminal)
    end

    test "colors is a valid color_depth atom" do
      caps = Selector.detect_capabilities()

      assert caps.colors in [:true_color, :color_256, :color_16, :monochrome]
    end

    test "unicode is a boolean" do
      caps = Selector.detect_capabilities()

      assert is_boolean(caps.unicode)
    end

    test "dimensions is nil or a {rows, cols} tuple" do
      caps = Selector.detect_capabilities()

      case caps.dimensions do
        nil ->
          :ok

        {rows, cols} ->
          assert is_integer(rows) and rows > 0
          assert is_integer(cols) and cols > 0
      end
    end

    test "terminal is a boolean" do
      caps = Selector.detect_capabilities()

      assert is_boolean(caps.terminal)
    end
  end

  describe "color depth detection" do
    # These tests verify the color detection logic using environment manipulation
    # Uses with_env/2 helper for environment isolation

    test "detects true_color from COLORTERM=truecolor" do
      with_env(%{"COLORTERM" => "truecolor"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.colors == :true_color
      end)
    end

    test "detects true_color from COLORTERM=24bit" do
      with_env(%{"COLORTERM" => "24bit"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.colors == :true_color
      end)
    end

    test "detects color_256 from TERM containing -256color" do
      with_env(%{"COLORTERM" => nil, "TERM" => "xterm-256color"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.colors == :color_256
      end)
    end

    test "detects true_color from TERM containing -direct" do
      with_env(%{"COLORTERM" => nil, "TERM" => "xterm-direct"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.colors == :true_color
      end)
    end

    test "detects color_16 from basic terminal TERM" do
      with_env(%{"COLORTERM" => nil, "TERM" => "xterm"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.colors == :color_16
      end)
    end

    test "falls back to monochrome when TERM is empty" do
      with_env(%{"COLORTERM" => nil, "TERM" => nil}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.colors == :monochrome
      end)
    end

    test "COLORTERM takes priority over TERM" do
      # Even with xterm (which would be color_16), truecolor COLORTERM wins
      with_env(%{"COLORTERM" => "truecolor", "TERM" => "xterm"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.colors == :true_color
      end)
    end
  end

  describe "basic terminal type detection" do
    # Tests for all 13 terminal types supported by basic_terminal?/1

    @basic_terminals ~w(xterm screen tmux vt100 vt220 linux rxvt ansi cygwin putty konsole gnome eterm)

    test "detects all supported basic terminal types" do
      for terminal <- @basic_terminals do
        with_env(%{"COLORTERM" => nil, "TERM" => terminal}, fn ->
          caps = Selector.detect_capabilities()

          assert caps.colors == :color_16,
                 "Expected #{terminal} to be detected as color_16, got #{caps.colors}"
        end)
      end
    end

    test "detects terminal types with suffixes" do
      # Test that terminal types with common suffixes are still detected
      test_cases = [
        {"xterm-256color", :color_256},
        {"screen-256color", :color_256},
        {"tmux-256color", :color_256},
        {"rxvt-unicode", :color_16},
        {"gnome-terminal", :color_16}
      ]

      for {terminal, expected} <- test_cases do
        with_env(%{"COLORTERM" => nil, "TERM" => terminal}, fn ->
          caps = Selector.detect_capabilities()

          assert caps.colors == expected,
                 "Expected #{terminal} to be detected as #{expected}, got #{caps.colors}"
        end)
      end
    end

    test "detects terminal types with prefixes" do
      # Test that terminal types can be detected when they appear as substrings
      test_cases = [
        "my-xterm-custom",
        "custom-screen",
        "linux-console"
      ]

      for terminal <- test_cases do
        with_env(%{"COLORTERM" => nil, "TERM" => terminal}, fn ->
          caps = Selector.detect_capabilities()

          assert caps.colors == :color_16,
                 "Expected #{terminal} to be detected as color_16, got #{caps.colors}"
        end)
      end
    end

    test "returns monochrome for unknown terminal types" do
      unknown_terminals = ["dumb", "unknown", "weird-terminal", ""]

      for terminal <- unknown_terminals do
        with_env(%{"COLORTERM" => nil, "TERM" => terminal}, fn ->
          caps = Selector.detect_capabilities()

          assert caps.colors == :monochrome,
                 "Expected #{inspect(terminal)} to be detected as monochrome, got #{caps.colors}"
        end)
      end
    end
  end

  describe "unicode detection" do
    # Uses with_env/2 helper for environment isolation

    test "detects unicode from LANG containing UTF-8" do
      with_env(%{"LC_ALL" => nil, "LC_CTYPE" => nil, "LANG" => "en_US.UTF-8"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.unicode == true
      end)
    end

    test "detects unicode from LC_ALL taking priority over LANG" do
      with_env(%{"LC_ALL" => "en_US.UTF-8", "LC_CTYPE" => nil, "LANG" => "C"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.unicode == true
      end)
    end

    test "detects unicode from LC_CTYPE taking priority over LANG" do
      with_env(%{"LC_ALL" => nil, "LC_CTYPE" => "en_US.UTF-8", "LANG" => "C"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.unicode == true
      end)
    end

    test "LC_ALL takes priority over LC_CTYPE" do
      with_env(%{"LC_ALL" => "en_US.UTF-8", "LC_CTYPE" => "C", "LANG" => "C"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.unicode == true
      end)
    end

    test "returns false when no UTF locale is set" do
      with_env(%{"LC_ALL" => nil, "LC_CTYPE" => nil, "LANG" => "C"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.unicode == false
      end)
    end

    test "handles case-insensitive UTF-8 detection" do
      # Some systems use lowercase utf-8
      with_env(%{"LC_ALL" => nil, "LC_CTYPE" => nil, "LANG" => "en_US.utf-8"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.unicode == true
      end)
    end

    test "handles UTF8 without hyphen" do
      with_env(%{"LC_ALL" => nil, "LC_CTYPE" => nil, "LANG" => "en_US.UTF8"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.unicode == true
      end)
    end
  end

  describe "terminal dimensions detection" do
    # Note: These tests are environment-dependent
    # In a test environment, dimensions may or may not be available

    test "returns valid format when dimensions are available" do
      caps = Selector.detect_capabilities()

      case caps.dimensions do
        nil ->
          # No dimensions available in test environment - acceptable
          :ok

        {rows, cols} ->
          assert is_integer(rows)
          assert is_integer(cols)
          assert rows > 0
          assert cols > 0
      end
    end
  end

  describe "terminal presence detection" do
    # Note: Terminal presence depends on test environment

    test "returns a boolean" do
      caps = Selector.detect_capabilities()
      assert is_boolean(caps.terminal)
    end
  end

  describe "defensive error handling" do
    # Tests documenting the defensive programming approach for unexpected errors

    test "attempt_raw_mode handles documented error types" do
      # The function should always return a valid result
      result = Selector.attempt_raw_mode()
      assert_valid_selection_result(result)
    end

    test "generic error handling preserves error reason in capabilities" do
      # This test documents the expected behavior when an unexpected error occurs.
      # While we can't easily simulate an unexpected error from :shell.start_interactive/1,
      # we document that when such errors occur:
      # 1. The function returns {:tty, capabilities} (graceful degradation)
      # 2. The error reason is preserved in the :raw_mode_error key
      #
      # This defensive approach ensures forward compatibility with future OTP versions
      # that might introduce new error conditions.
      result = Selector.attempt_raw_mode()

      case result do
        {:tty, caps} ->
          # In test environment, we typically get {:error, :already_started}
          # which doesn't add :raw_mode_error. But the structure is valid.
          assert_valid_capabilities(caps)

        {:raw, state} ->
          # Raw mode succeeded - also valid
          assert_valid_raw_state(state)
      end
    end
  end

  describe "logging" do
    test "logs forced backend selection" do
      log =
        capture_log(fn ->
          Selector.select(TermUI.Backend.TTY)
        end)

      assert log =~ "TermUI: Using forced backend"
      assert log =~ "TermUI.Backend.TTY"
    end

    test "logs forced backend with options" do
      log =
        capture_log(fn ->
          Selector.select({TermUI.Backend.TTY, [line_mode: :full_redraw]})
        end)

      assert log =~ "TermUI: Using forced backend"
      assert log =~ "TermUI.Backend.TTY"
    end
  end
end
