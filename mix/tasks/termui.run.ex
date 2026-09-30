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
    end) || raise """
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
    |> Enum.map(fn segment ->
      case segment do
        "iex" -> "IEx"
        "io" -> "IO"
        "ui" -> "UI"
        "otp" -> "OTP"
        "tls" -> "TLS"
        "tcp" -> "TCP"
        "udp" -> "UDP"
        "http" -> "HTTP"
        "https" -> "HTTPS"
        "json" -> "JSON"
        "xml" -> "XML"
        "sql" -> "SQL"
        "id" -> "ID"
        "url" -> "URL"
        "uri" -> "URI"
        other -> Macro.camelize(other)
      end
    end)
    |> Enum.join()
  end
end
