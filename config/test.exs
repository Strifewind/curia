import Config

config :curia, CuriaWeb.Endpoint,
  secret_key_base: String.duplicate("curia-test-secret-", 5),
  server: false
