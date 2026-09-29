defmodule TermUIWebExample.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    port = System.get_env("TERM_UI_WEB_PORT", "4040") |> String.to_integer()

    Supervisor.start_link(
      [
        {Bandit,
         plug: TermUIWebExample.Router,
         ip: {127, 0, 0, 1},
         port: port,
         websocket_options: [max_frame_size: 70_000]}
      ],
      strategy: :one_for_one
    )
  end
end
