defmodule Curia.McuBridgeTest do
  use ExUnit.Case, async: true

  alias Curia.McuBridge

  test "summarizes an alerting service for the MCU" do
    snapshot = %{
      cluster: %{state: :healthy, ready: 3, total: 3},
      services: [
        %{name: "Router", state: :healthy, latency_ms: 12, storage: nil},
        %{
          name: "NAS",
          state: :healthy,
          latency_ms: 42,
          storage: %{percent: 90, alert?: true}
        }
      ]
    }

    assert %{
             cluster: %{state: "healthy", ready: 3, total: 3},
             service: %{
               name: "NAS",
               state: "healthy",
               latency_ms: 42,
               storage_percent: 90,
               storage_alert: true
             }
           } = McuBridge.mcu_summary(snapshot)
  end

  test "keeps the encoded RPC request within the RouterBridge buffer" do
    snapshot = %{
      cluster: %{state: :degraded, ready: 1_000_000_000, total: 1_000_000_000},
      services: [
        %{
          name: String.duplicate("Router \"test\"/", 100),
          state: :down,
          latency_ms: 1_000_000_000,
          storage: %{percent: 100, alert?: true}
        }
      ]
    }

    request = McuBridge.encode_request("set_status", 1, snapshot)
    summary = McuBridge.mcu_summary(snapshot)

    assert is_binary(request)
    assert byte_size(request) <= 256
    assert byte_size(summary.service.name) <= 16
    assert summary.cluster.ready == 999_999
    assert summary.service.latency_ms == 999_999
  end

  test "receives a MessagePack string split inside a multibyte character" do
    response = Msgpax.pack!([1, 1, nil, "€"], iodata: false)
    prefix_size = byte_size(response) - 1
    <<prefix::binary-size(prefix_size), suffix::binary>> = response
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        :ok = :gen_tcp.send(socket, prefix)
        Process.sleep(20)
        :ok = :gen_tcp.send(socket, suffix)
        :gen_tcp.close(socket)
      end)

    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

    assert {:ok, [1, 1, nil, "€"]} = McuBridge.receive_response(client)

    :gen_tcp.close(client)
    :gen_tcp.close(listener)
    assert :ok = Task.await(server)
  end
end