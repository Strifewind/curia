defmodule Curia.McuBridge do
  use GenServer
  require Logger

  @topic "curia:health"
  @response_timeout 2_000

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
    request = [0, request_id, method, [Jason.encode!(snapshot)]]

    with :ok <- :gen_tcp.send(socket, Msgpax.pack!(request)),
         {:ok, [1, ^request_id, nil, _result]} <- receive_response(socket, <<>>) do
      :ok
    else
      {:ok, [1, ^request_id, error, _result]} -> {:error, {:rpc_error, error}}
      {:ok, _response} -> {:error, :unexpected_rpc_response}
      {:error, reason} -> {:error, reason}
    end
  end

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
