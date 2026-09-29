defmodule TermUIGhosttyExample.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Application.put_env(:term_ui_web_example, :session_options, root: TermUIGhosttyExample.App)

    Application.put_env(
      :term_ui_web_example,
      :index_file,
      Path.expand("../priv/index.html", __DIR__)
    )

    TermUIWebExample.Application.start(:normal, [])
  end
end
