defmodule TermUIWebExample.Router do
  @moduledoc false
  use Plug.Router

  plug(Plug.Static, at: "/assets", from: {:term_ui, "priv/web"})
  plug(:match)
  plug(:dispatch)

  get "/" do
    index =
      Application.get_env(
        :term_ui_web_example,
        :index_file,
        Path.expand("../priv/index.html", __DIR__)
      )

    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, index)
  end

  get "/ws" do
    origin = "http://127.0.0.1:#{conn.port}"

    if get_req_header(conn, "origin") == [origin] and conn.host == "127.0.0.1" do
      options = Map.new(Application.get_env(:term_ui_web_example, :session_options, []))
      conn |> WebSockAdapter.upgrade(TermUIWebExample.Socket, options, timeout: 60_000) |> halt()
    else
      send_resp(conn, 403, "Origin refused")
    end
  end

  match(_, do: send_resp(conn, 404, "Not found"))
end
