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

    assert byte_size(request) <= 256
    assert byte_size(summary.service.name) <= 16
    assert summary.cluster.ready == 999_999
    assert summary.service.latency_ms == 999_999
  end
end