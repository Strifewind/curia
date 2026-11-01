defmodule Curia.Poller do
  use GenServer
  require Logger

  @topic "curia:health"
  @request_timeout 3_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @doc false
  def parse_nodes(%{"items" => items}) when is_list(items) do
    nodes =
      Enum.map(items, fn item ->
        conditions = get_in(item, ["status", "conditions"]) || []

        ready =
          Enum.any?(conditions, fn condition ->
            condition["type"] == "Ready" and condition["status"] == "True"
          end)

        %{
          name: get_in(item, ["metadata", "name"]) || "unknown",
          ready: ready,
          allocatable: get_in(item, ["status", "allocatable"]) || %{}
        }
      end)

    ready_count = Enum.count(nodes, & &1.ready)
    total_count = length(nodes)

    state =
      cond do
        total_count == 0 -> :unknown
        ready_count == total_count -> :healthy
        true -> :degraded
      end

    %{
      state: state,
      ready: ready_count,
      total: total_count,
      nodes: nodes,
      error: nil
    }
  end

  def parse_nodes(_body) do
    %{state: :unknown, ready: 0, total: 0, nodes: [], error: "Unexpected API response"}
  end

  @doc false
  def parse_storage(
        %{"storage" => %{"used_bytes" => used, "total_bytes" => total}},
        alert_percent
      )
      when is_integer(used) and is_integer(total) and used >= 0 and total > 0 do
    percent = div(used * 100, total)

    %{
      used_bytes: used,
      total_bytes: total,
      percent: percent,
      alert?: percent >= alert_percent
    }
  end

  def parse_storage(_body, _alert_percent), do: nil

  @impl true
  def init(_opts) do
    Process.send_after(self(), :poll, 0)

    {:ok,
     %{
       interval_ms: Application.get_env(:curia, :poll_interval_ms, 15_000),
       kubernetes_api_url: Application.get_env(:curia, :kubernetes_api_url),
       kubernetes_bearer_token: Application.get_env(:curia, :kubernetes_bearer_token),
       service_checks: Application.get_env(:curia, :service_checks, []),
       storage_alert_percent: Application.get_env(:curia, :storage_alert_percent, 85),
       snapshot: initial_snapshot()
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  @impl true
  def handle_info(:poll, state) do
    snapshot = collect_snapshot(state)
    Phoenix.PubSub.broadcast(Curia.PubSub, @topic, {:health_snapshot, snapshot})
    Process.send_after(self(), :poll, state.interval_ms)

    {:noreply, %{state | snapshot: snapshot}}
  end

  defp collect_snapshot(state) do
    %{
      updated_at: DateTime.utc_now(),
      cluster: poll_kubernetes(state.kubernetes_api_url, state.kubernetes_bearer_token),
      services: Enum.map(state.service_checks, &check_service(&1, state.storage_alert_percent))
    }
  end

  defp poll_kubernetes(nil, _token),
    do: %{state: :unknown, ready: 0, total: 0, nodes: [], error: "Not configured"}

  defp poll_kubernetes("", token), do: poll_kubernetes(nil, token)

  defp poll_kubernetes(base_url, token) do
    headers =
      case token do
        value when is_binary(value) and value != "" ->
          [{"authorization", "Bearer #{value}"}]

        _ ->
          []
      end

    url = String.trim_trailing(base_url, "/") <> "/api/v1/nodes"

    case Req.get(url, headers: headers, receive_timeout: @request_timeout) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        parse_nodes(body)

      {:ok, %{status: status}} ->
        %{state: :unknown, ready: 0, total: 0, nodes: [], error: "HTTP #{status}"}

      {:error, reason} ->
        Logger.warning("Kubernetes node poll failed: #{inspect(reason)}")
        %{state: :unknown, ready: 0, total: 0, nodes: [], error: "Request failed"}
    end
  end

  defp check_service(%{name: name, url: url}, storage_alert_percent) do
    started_at = System.monotonic_time(:millisecond)

    case Req.get(url, receive_timeout: @request_timeout) do
      {:ok, %{status: status, body: body}} when status in 200..399 ->
        %{
          name: name,
          state: :healthy,
          latency_ms: System.monotonic_time(:millisecond) - started_at,
          storage: parse_storage(body, storage_alert_percent),
          error: nil
        }

      {:ok, %{status: status, body: body}} ->
        %{
          name: name,
          state: :down,
          latency_ms: System.monotonic_time(:millisecond) - started_at,
          storage: parse_storage(body, storage_alert_percent),
          error: "HTTP #{status}"
        }

      {:error, reason} ->
        Logger.warning("Health check for #{name} failed: #{inspect(reason)}")

        %{
          name: name,
          state: :down,
          latency_ms: System.monotonic_time(:millisecond) - started_at,
          storage: nil,
          error: "Request failed"
        }
    end
  end

  defp initial_snapshot do
    %{
      updated_at: nil,
      cluster: %{
        state: :unknown,
        ready: 0,
        total: 0,
        nodes: [],
        error: "Waiting for first poll"
      },
      services: []
    }
  end
end
