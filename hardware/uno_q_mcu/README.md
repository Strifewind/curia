# UNO Q MCU status sketch

This Arduino C++ sketch is the MCU-side endpoint used by `Curia.McuBridge`.
It registers the `set_status` MessagePack-RPC method, accepts the JSON
snapshot string sent by the Linux application, and renders cluster, service,
latency, and storage data on an I2C OLED. By default it targets an SSD1306
128x64 display; define `OLED_SH1106` to select the SH1106 driver instead.

Install the UNO Q board support and these libraries in the host Arduino build
environment:

- Arduino_RouterBridge
- U8g2
- ArduinoJson 6.x

The sketch uses the board's default `Wire` I2C pins. Confirm the selected
display address and wiring for the particular module. `Bridge.provide_safe`
keeps OLED updates on the sketch's main loop.

The screen switches to a stale-link warning if no update arrives for 45
seconds. This is a display-side fail-safe; add board-specific LED/buzzer
outputs only after verifying the UNO Q pin mapping and electrical limits.
An optional `CURIA_STATUS_LED_PIN` build definition mirrors cluster/service
errors and stale-link state to a status LED; leave it undefined until the
physical pin and polarity are confirmed.

The Nerves system's `unoq-mcu` utility handles the OpenOCD/SWD bit-banged
flashing path. Build a loader and sketch image using the UNO Q MCU toolchain,
then flash with:

```sh
unoq-mcu sketch path/to/loader.elf path/to/status_sketch.bin
```

Do not flash the MCU concurrently with normal router operation. The Linux
application communicates through `/var/run/arduino-router.sock`; it must not
take ownership of `/dev/ttyHS1`.
