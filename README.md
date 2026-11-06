# Curia

Curia is a stateless homelab health dashboard for an Arduino UNO Q running
Nerves. The Nerves application polls a Kubernetes API and configured HTTP
health endpoints, publishes the latest snapshot in memory, streams it to a
Phoenix LiveView dashboard, and forwards it to the STM32 through
`arduino-router`.

## Host requirements

- Elixir 1.17 or newer, an OTP version matching the selected Nerves system,
  and the Nerves firmware tools (including `fwup`)
- Node.js and npm for the host-side LiveView JavaScript bundle
- The Nerves UNO Q system's first-install requirements for EDL flashing

Install the Mix build tooling using the same Erlang/Elixir environment that
will build the firmware:

```sh
mix local.hex --force
mix local.rebar --force
mix archive.install hex nerves_bootstrap "~> 1.10" --force
```

`config/config.exs` starts Nerves bootstrap before dependencies are compiled.
Installing the archive alone does not initialize its Mix integration.

The release VM arguments use the Elixir 1.17+ `start_cli` entry point.
Keep these arguments literal: Nerves validates `rel/vm.args.eex` before EEx
evaluation, so conditional legacy startup arguments are not supported here.
The trailing `-extra --no-halt` keeps the VM alive after Elixir CLI startup;
without it the CLI can exit normally and erlinit can reboot the board.
`-heart` enables the heartbeat process required by the startup guard, with the
Nerves defaults of a 30-second heartbeat timeout and a 10-minute initialization
handshake timeout.

The firmware release selects the target OTP installation through
`Nerves.Release.erts/0`. Shoehorn creates the device boot script and starts
Nerves runtime and networking before the dashboard. Do not bypass firmware
architecture checks with `.noscrub`: host x86-64 OTP libraries cannot run on
the UNO Q's AArch64 CPU.

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
bounded MCU-specific summary as a JSON string argument to the configured MCU
method. The MCU sketch must register that method. Application code must not
open `/dev/ttyHS1` directly: the router owns that UART.

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

## Networking-only recovery

If the board repeatedly disconnects and SSH is unavailable, an opt-in recovery
build can isolate the application from the Nerves system and power supply.
It starts Nerves networking and SSH without Phoenix, the pollers, or the MCU
bridge. Recovery builds compile only the boot module in `lib/curia/boot`,
so excluded web modules do not require Phoenix during compilation. Web and
polling dependencies are marked `runtime: false` in this mode; Mix still
derives the OTP application list and retains access to Nerves build tooling.
This mode does not change the separate STM32 firmware.

Keep the same OTP-29-compatible Elixir, bootstrap archive, `fwup`, and
`MIX_REBAR3` configuration used for the successful normal build. Set a public
key that you can log in with:

```sh
export MIX_TARGET=uno_q
export MIX_ENV=prod
export CURIA_RECOVERY=1
export NERVES_SSH_AUTHORIZED_KEYS="$(cat ~/.ssh/curia_ed25519.pub)"
mix clean
mix deps.get
mix firmware
```

With the same recovery environment still set, use `mix firmware.qdl` to
provision the board over EDL again. This erases eMMC data. After successful
flashing, power off, remove the EDL jumper, and reconnect normally.

On the native host connected to the board, try
`ssh -i ~/.ssh/curia_ed25519 curia-recovery.local`. This name requires working
mDNS on the host. Otherwise obtain the board's address from the USB DHCP
exchange or, if Wi-Fi was configured, the router's DHCP leases. There is no
web dashboard in recovery mode. In IEx, capture:

```elixir
System.cmd("cat", ["/proc/uptime"])
Application.started_applications() |> Enum.map(&elem(&1, 0))
RingLogger.next()
```

Check uptime again after a minute. Increasing uptime and a stable USB
interface indicate that the minimal firmware is staying up. Continued cycling
does not prove a power fault: a Nerves-system or boot failure is still possible.

To return to normal firmware, unset `CURIA_RECOVERY`, then run `mix clean` and
`mix firmware`. Cleaning when switching modes ensures the application
dependency list is regenerated. Upload over the working recovery connection
using `mix upload DEVICE_IP`.

Before reflashing, record `git rev-parse HEAD` and `mix deps` alongside the
firmware image. There is currently no committed `mix.lock`, so matching Git
revisions alone does not ensure matching dependency versions. In particular,
check the selected UNO Q system version against its
[upstream changelog](https://github.com/jimsynz/nerves_system_arduino_uno_q/blob/main/CHANGELOG.md).
System versions through 0.1.2 have a separate ABL boot-slot issue that can leave
the board in fastboot after several boots; the upstream fix requires
reprovisioning with `mix firmware.qdl`, not just a firmware upload. This does
not establish the cause of the repeating USB disconnect/reconnect cycle.

The boot loop remains unresolved, including with recovery firmware. Recovery
still runs the same kernel, erlinit, system pre-run helpers (including
`arduino-router`), and Nerves networking/SSH stack. The configured Nerves startup
guard's validation timeout is 15 minutes, not the observed roughly 48-second USB
cycle. Missing `--no-halt` and `-heart` have been corrected, but whether these
caused the observed cycle still needs a reflash to verify. If cycling persists,
capture the debug UART console from power-on through
a complete cycle, after verifying the console pinout and adapter voltage.
USB disconnects and changing gadget MAC addresses alone do not distinguish a
board reset from USB gadget reinitialization or establish a power fault.
