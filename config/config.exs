import Config

{:ok, _} = Application.ensure_all_started(:nerves_bootstrap)

config :curia,
  target: false,
  poll_interval_ms: 15_000,
  kubernetes_api_url: nil,
  kubernetes_bearer_token: nil,
  service_checks: [],
  mcu_socket: "/var/run/arduino-router.sock",
  mcu_method: "set_status"

config :curia, CuriaWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [html: CuriaWeb.ErrorHTML], layout: false],
  pubsub_server: Curia.PubSub,
  live_view: [signing_salt: "curia-live-view"],
  server: false

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"

if Mix.target() != :host do
  import_config "target.exs"
end
