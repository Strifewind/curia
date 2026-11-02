defmodule Curia.PollerTest do
  use ExUnit.Case, async: true

  alias Curia.Poller

  test "counts ready nodes and preserves allocatable resources" do
    body = %{
      "items" => [
        %{
          "metadata" => %{"name" => "worker-1"},
          "status" => %{
            "conditions" => [%{"type" => "Ready", "status" => "True"}],
            "allocatable" => %{"cpu" => "4", "memory" => "8Gi"}
          }
        },
        %{
          "metadata" => %{"name" => "worker-2"},
          "status" => %{"conditions" => [%{"type" => "Ready", "status" => "False"}]}
        }
      ]
    }

    assert %{
             state: :degraded,
             ready: 1,
             total: 2,
             nodes: [
               %{name: "worker-1", ready: true, allocatable: %{"cpu" => "4"}},
               %{name: "worker-2", ready: false}
             ]
           } = Poller.parse_nodes(body)
  end

  test "marks storage as alerting at the configured threshold" do
    assert %{percent: 85, alert?: true} =
             Poller.parse_storage(
               %{"storage" => %{"used_bytes" => 85, "total_bytes" => 100}},
               85
             )
  end

  test "ignores incomplete storage metrics" do
    assert is_nil(Poller.parse_storage(%{"storage" => %{"used_bytes" => 20}}, 85))
  end
end
