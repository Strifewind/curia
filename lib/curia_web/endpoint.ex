defmodule CuriaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :curia

  @session_options [
    store: :cookie,
    key: "_curia_key",
    signing_salt: "curia-session"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static,
    at: "/",
    from: :curia,
    gzip: false,
    only: ~w(assets)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(CuriaWeb.Router)
end
