import Config

wifi_ssid = System.get_env("WIFI_SSID")
wifi_psk = System.get_env("WIFI_PSK")

wifi_config =
  if is_binary(wifi_ssid) and wifi_ssid != "" and is_binary(wifi_psk) and wifi_psk != "" do
    [
      {"wlan0",
       %{
         type: VintageNetWiFi,
         vintage_net_wifi: %{
           networks: [%{ssid: wifi_ssid, psk: wifi_psk, key_mgmt: :wpa_psk}]
         },
         ipv4: %{method: :dhcp}
       }}
    ]
  else
    []
  end

network_config =
  wifi_config ++
    [
      {"usb0", %{type: VintageNetDirect}}
    ]

authorized_keys =
  System.get_env("NERVES_SSH_AUTHORIZED_KEYS", "")
  |> String.split("\n", trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.reject(&(&1 == ""))

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

config :curia, target: true

config :curia,
  poll_interval_ms: poll_interval_ms,
  kubernetes_api_url: System.get_env("CURIA_K8S_API_URL"),
  kubernetes_bearer_token: System.get_env("CURIA_K8S_BEARER_TOKEN"),
  service_checks: service_checks,
  mcu_socket: System.get_env("CURIA_MCU_SOCKET", "/var/run/arduino-router.sock"),
  mcu_method: System.get_env("CURIA_MCU_METHOD", "set_status"),
  storage_alert_percent: storage_alert_percent

config :curia, CuriaWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  server: true

config :nerves_ssh,
  authorized_keys: authorized_keys

web_host = System.get_env("CURIA_HOST", "curia.local")

allowed_origins =
  System.get_env("CURIA_ALLOWED_ORIGINS", "//#{web_host}:4000")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)

config :vintage_net,
  regulatory_domain: System.get_env("WIFI_REGULATORY_DOMAIN", "US"),
  config: network_config

config :curia, CuriaWeb.Endpoint,
  url: [host: web_host, port: 4000],
  check_origin: allowed_origins
