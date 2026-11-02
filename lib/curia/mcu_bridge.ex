defmodule Curia.McuBridge do
  use GenServer
  require Logger

  @topic "curia:health"
  @response_timeout 2_000
  @rpc_buffer_size 256
  @max_service_name_length 16

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Curia.PubSub, @topic)

    {:ok,
     %{
       socket_path: Application.get_env(:curia, :mcu_socket, "/var/run/arduino-router.sock"),
       method: Application.get_env(:curia, :mcu_method, "set_status"),
       request_id: 0
     }}
  end

  @doc false
  def encode_request(method, request_id, snapshot) do
    payload = snapshot |> mcu_summary() |> Jason.encode!()
    Msgpax.pack!([0, request_id, method, [payload]])
  end

  @doc false
  def mcu_summary(snapshot) do
    cluster = Map.get(snapshot, :cluster, %{})
    services = Map.get(snapshot, :services, [])
    service = Enum.find(services, &alerting_service?/1) || List.first(services)

    %{
      cluster: %{
        state: cluster_state(Map.get(cluster, :state)),
        ready: bounded_count(Map.get(cluster, :ready)),
        total: bounded_count(Map.get(cluster, :total))
      },
      service: summarize_service(service)
    }
  end

  @impl true
  def handle_info({:health_snapshot, snapshot}, state) do
    case send_snapshot(state, snapshot) do
      {:ok, request_id} ->
        {:noreply, %{state | request_id: request_id}}

      {:error, reason} ->
        Logger.warning("MCU status update failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  defp send_snapshot(state, snapshot) do
    with {:ok, socket} <- connect(state.socket_path),
         result <- rpc_call(socket, state.method, state.request_id + 1, snapshot) do
      :gen_tcp.close(socket)

      case result do
        :ok -> {:ok, state.request_id + 1}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp connect(path) do
    :gen_tcp.connect({:local, String.to_charlist(path)}, 0, [:binary, active: false], 1_000)
  end

  defp rpc_call(socket, method, request_id, snapshot) do
    request = encode_request(method, request_id, snapshot)

    with true <- byte_size(request) <= @rpc_buffer_size || {:error, :request_too_large},
         :ok <- :gen_tcp.send(socket, request),
         {:ok, [1, ^request_id, nil, _result]} <- receive_response(socket, <<>>) do
      :ok
    else
      {:ok, [1, ^request_id, error, _result]} -> {:error, {:rpc_error, error}}
      {:ok, _response} -> {:error, :unexpected_rpc_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp summarize_service(nil), do: nil

  defp summarize_service(service) do
    storage = Map.get(service, :storage) || %{}

    %{
      name: bounded_service_name(Map.get(service, :name)),
      state: service_state(Map.get(service, :state)),
      latency_ms: bounded_latency(Map.get(service, :latency_ms)),
      storage_percent: bounded_storage_percent(Map.get(storage, :percent)),
      storage_alert: Map.get(storage, :alert?, false) == true
    }
  end

  defp alerting_service?(service) do
    Map.get(service, :state) != :healthy or
      get_in(service, [:storage, :alert?]) == true
  end

  defp cluster_state(:healthy), do: "healthy"
  defp cluster_state(:degraded), do: "degraded"
  defp cluster_state(_state), do: "unknown"

  defp service_state(:healthy), do: "healthy"
  defp service_state(:down), do: "down"
  defp service_state(_state), do: "unknown"

  defp bounded_count(value) when is_integer(value) and value >= 0,
    do: min(value, 999_999)

  defp bounded_count(_value), do: 0

  defp bounded_latency(value) when is_integer(value) and value >= 0,
    do: min(value, 999_999)

  defp bounded_latency(_value), do: -1

  defp bounded_storage_percent(value) when is_integer(value) and value in 0..100,
    do: value

  defp bounded_storage_percent(_value), do: -1

  defp bounded_service_name(name) when is_binary(name) do
    safe_name =
      name
      |> String.replace(~r/[^A-Za-z0-9 _.-]/, "")
      |> String.slice(0, @max_service_name_length)

    if safe_name == "", do: "Service", else: safe_name
  end

  defp bounded_service_name(_name), do: "Service"

  defp receive_response(socket, buffer) do
    case Msgpax.unpack(buffer) do
      {:ok, response} ->
        {:ok, response}

      {:error, %Msgpax.UnpackError{reason: :incomplete}} ->
        case :gen_tcp.recv(socket, 0, @response_timeout) do
          {:ok, data} -> receive_response(socket, buffer <> data)
          {:error, reason} -> {:error, reason}
        end

      {:error, error} ->
        {:error, error}
    end
  end
end