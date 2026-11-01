# Curia

Curia is a stateless homelab health dashboard for an Arduino UNO Q running
Nerves. The Nerves application polls a Kubernetes API and configured HTTP
health endpoints, publishes the latest snapshot in memory, streams it to a
Phoenix LiveView dashboard, and forwards it to the STM32 through
`arduino-router`.

## Host requirements

- Elixir/OTP and the Nerves firmware tools (including `fwup`)
- Node.js and npm for the host-side LiveView JavaScript bundle
- The Nerves UNO Q system's first-install requirements for EDL flashing

Install the JavaScript dependencies once:

```sh
cd assets && npm ci && cd ..
```

Set `MIX_TARGET=uno_q` for target commands. Wi-Fi settings and SSH public keys
are read from the build host's environment; they are embedded in the firmware,
so keep generated firmware artifacts private:

```sh
export MIX_TARGET=uno_q
export WIFI_SSID='your-network'
export WIFI_PSK='your-wifi-password'
export NERVES_SSH_AUTHORIZED_KEYS="$(cat ~/.ssh/id_ed25519.pub)"
export CURIA_K8S_API_URL='https://kubernetes.example:6443'
export CURIA_K8S_BEARER_TOKEN='...'
export CURIA_ROUTER_URL='http://192.0.2.1/health'
export CURIA_NAS_URL='http://192.0.2.2:8080/health'
export CURIA_HOST='192.0.2.10'
export CURIA_ALLOWED_ORIGINS='//192.0.2.10:4000,//curia.local:4000'
mix deps.get
mix firmware
```

Kubernetes uses the API server's normal TLS verification. If the cluster uses a
private CA, install that CA in the Nerves system trust store. The token grants
read-only access only when its Kubernetes RBAC role is configured accordingly.
The dashboard listens on port `4000`; it is intended for a trusted homelab
network and does not provide user authentication.

The first install provisions eMMC and erases its current contents. Review the
UNO Q system's EDL instructions before running:

```sh
mix firmware.qdl
```

Subsequent updates can use the USB Ethernet gadget or Wi-Fi:

```sh
mix upload <device-ip>
```

For host development, run `mix deps.get`, `mix test`, then
`mix phx.server`. The dashboard uses the same in-memory polling and PubSub
services. `mix firmware` runs the JavaScript bundle step on the host before
packaging; no asset compiler runs on the target.

## Configuration

| Variable | Purpose |
| --- | --- |
| `WIFI_SSID`, `WIFI_PSK` | Optional target Wi-Fi profile |
| `WIFI_REGULATORY_DOMAIN` | Wi-Fi country code; defaults to `US` |
| `NERVES_SSH_AUTHORIZED_KEYS` | Newline-separated SSH **public** keys |
| `CURIA_SECRET_KEY_BASE` | Optional Phoenix session secret; otherwise generated for the firmware build |
| `CURIA_K8S_API_URL` | Kubernetes API base URL |
| `CURIA_K8S_BEARER_TOKEN` | Optional Kubernetes bearer token |
| `CURIA_ROUTER_URL`, `CURIA_NAS_URL` | Optional HTTP health-check URLs |
| `CURIA_HOST` | Dashboard host advertised by Phoenix; defaults to `curia.local` |
| `CURIA_ALLOWED_ORIGINS` | Comma-separated Phoenix origins allowed for LiveView; defaults to `//<CURIA_HOST>:4000` |
| `CURIA_POLL_INTERVAL_MS` | Poll period; defaults to `15000` |
| `CURIA_STORAGE_ALERT_PERCENT` | NAS storage warning threshold; defaults to `85` |
| `CURIA_MCU_SOCKET` | Router socket; defaults to `/var/run/arduino-router.sock` |
| `CURIA_MCU_METHOD` | MCU RPC handler; defaults to `set_status` |

Wi-Fi, SSH, and poller settings are loaded when the target firmware is built.
Do not put private keys or API tokens in source control. The SSH variable must
contain public keys only. Keep the optional session secret private as well.

For NAS storage alerts, the health endpoint may return JSON with a `storage`
object containing integer `used_bytes` and `total_bytes` fields.

## MCU bridge and hardware notes

The UNO Q system starts `arduino-router` and exposes its MessagePack-RPC
Unix-domain socket at `/var/run/arduino-router.sock`. Curia sends the latest
snapshot as a JSON string argument to the configured MCU method. The MCU sketch
must register that method. Application code must not open `/dev/ttyHS1`
directly: the router owns that UART.

`unoq-mcu` is the system's MCU flashing utility, not the RPC daemon. The
supported handoff is to build a compatible MCU sketch and use the system's
`unoq-mcu sketch` command with the board's loader and sketch image. OpenOCD
bit-banging and flashing are intentionally not run by the application.
Arduino_RouterBridge is the UNO Q's Zephyr-based MCU RPC layer; the included
C++ sketch uses that supported runtime rather than bypassing it with a custom
UART implementation.

The application has no database or persistent metrics store. If the network
or dashboard fails, the MCU firmware remains responsible for its last-known
physical indication and its own fail-safe behavior.
