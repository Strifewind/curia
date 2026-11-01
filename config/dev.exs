import Config

config :curia, CuriaWeb.Endpoint,
  secret_key_base: String.duplicate("curia-development-secret-", 4),
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: true,
  check_origin: false
