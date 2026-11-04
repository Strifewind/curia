import Config

config :curia, CuriaWeb.Endpoint,
  server: true,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  secret_key_base:
    System.get_env("CURIA_SECRET_KEY_BASE") || Base.encode64(:crypto.strong_rand_bytes(48))
