defmodule Mix.Tasks.Termui.Run do
  @moduledoc """
  Runs a TermUI application.

  ## Usage

      mix termui.run

  ## Examples

  When the Mix app name maps to its runnable module:
      mix termui.run

  From any other project with a TermUI app:
      mix termui.run --module MyApp

  ## Options

      --module MODULE    - Module name containing run/0 (default: autodetect)
      --function NAME    - Function name to call (default: run)

  ## How it works

  1. Autodetects the module containing `run/0` from the mix.exs app name
  2. Compiles the project
  3. Calls `Module.run()` to start the TUI application

  """

  use Mix.Task

  @acronyms ~w(io ui otp tls tcp udp http https json xml sql id url uri)

  @shortdoc "Runs a TermUI application"

  @impl true
  def run(args) do
    {opts, _} =
      OptionParser.parse!(args, strict: [module: :string, function: :string])

    # Ensure project is compiled
    Mix.Project.get!()
    Mix.Task.run("compile")

    module =
      case Keyword.get(opts, :module) do
        nil ->
          autodetect_module()

        mod_name ->
          Module.concat(["Elixir", mod_name])
      end

    function = Keyword.get(opts, :function, "run") |> String.to_atom()

    # Run the application
    apply(module, function, [])
  end

  defp autodetect_module do
    app = Mix.Project.config()[:app]

    # Common module name patterns to try
    base_name = camelize_acronyms(to_string(app))

    candidates = [
      Module.concat([base_name]),
      Module.concat([base_name, "App"]),
      Module.concat([base_name, "Application"]),
      # Also try standard camelize as fallback
      Module.concat([Macro.camelize(to_string(app))]),
      Module.concat([Macro.camelize(to_string(app)), "App"]),
      Module.concat([Macro.camelize(to_string(app)), "Application"])
    ]

    # Find first candidate that has a run/0 function
    Enum.find_value(candidates, fn mod ->
      if Code.ensure_loaded?(mod) && function_exported?(mod, :run, 0) do
        mod
      else
        nil
      end
    end) ||
      raise """
      Could not find a module with run/0 function.

      Available modules in your project:
      #{inspect(Enum.filter(candidates, &Code.ensure_loaded?/1))}

      Specify explicitly with --module:
          mix termui.run --module #{base_name}
      """
  end

  # Camelize while preserving common acronyms
  defp camelize_acronyms(string) do
    string
    |> String.split("_")
    |> Enum.map_join("", &camelize_segment/1)
  end

  defp camelize_segment("iex"), do: "IEx"
  defp camelize_segment(segment) when segment in @acronyms, do: String.upcase(segment)
  defp camelize_segment(segment), do: Macro.camelize(segment)
end
