# Terminal tests are excluded by default because they manipulate terminal state
# in ways that can leave an interactive terminal in an unusable state.
# Run them with: TERMUI_INCLUDE_TERMINAL_TESTS=1 mix test

terminal_excludes =
  if System.get_env("TERMUI_INCLUDE_TERMINAL_TESTS") do
    # Only check OTP availability when explicitly requested
    raw_mode_available? = function_exported?(:shell, :start_interactive, 1)
    if raw_mode_available?, do: [], else: [:requires_terminal]
  else
    # Always exclude by default
    [:requires_terminal]
  end

nif_excludes =
  if String.downcase(System.get_env("TERM_UI_TTY_NIF", "auto")) == "disabled" do
    [:tty_nif]
  else
    []
  end

ExUnit.start(exclude: terminal_excludes ++ nif_excludes)
