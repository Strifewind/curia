import Config

if config_target() == :host do
  service_checks =
    [
      {"Router", System.get_env("CURIA_ROUTER_URL")},
      {"NAS", System.get_env("CURIA_NAS_URL")}
    ]
    |> Enum.reject(fn {_name, url} -> is_nil(url) or url == "" end)
    |> Enum.map(fn {name, url} -> %{name: name, url: url} end)

  poll_interval_ms =
    case Integer.parse(System.get_env("CURIA_POLL_INTERVAL_MS", "15000")) do
      {value, ""} when value > 0 -> value
      _ -> raise ArgumentError, "CURIA_POLL_INTERVAL_MS must be a positive integer"
    end

  storage_alert_percent =
    case Integer.parse(System.get_env("CURIA_STORAGE_ALERT_PERCENT", "85")) do
      {value, ""} when value in 1..100 -> value
      _ -> raise ArgumentError, "CURIA_STORAGE_ALERT_PERCENT must be from 1 to 100"
    end

  config :curia,
    poll_interval_ms: poll_interval_ms,
    kubernetes_api_url: System.get_env("CURIA_K8S_API_URL"),
    kubernetes_bearer_token: System.get_env("CURIA_K8S_BEARER_TOKEN"),
    service_checks: service_checks,
    mcu_socket: System.get_env("CURIA_MCU_SOCKET", "/var/run/arduino-router.sock"),
    mcu_method: System.get_env("CURIA_MCU_METHOD", "set_status"),
    storage_alert_percent: storage_alert_percent
end