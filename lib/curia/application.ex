defmodule Curia.Application do
  use Application

  @impl true
  def start(_type, _args) do
    validate_firmware_config!()

    children = [
      {Phoenix.PubSub, name: Curia.PubSub},
      {Task.Supervisor, name: Curia.PollerTaskSupervisor},
      Curia.McuBridge,
      CuriaWeb.Endpoint,
      Curia.Poller
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Curia.Supervisor)
  end

  @doc false
  def validate_firmware_config! do
    if Application.get_env(:curia, :target, false) do
      network_config = Application.get_env(:vintage_net, :config, [])

      unless Enum.any?(network_config, fn
               {"usb0", %{type: VintageNetDirect}} -> true
               _ -> false
             end) do
        raise "Target firmware requires usb0 to use VintageNetDirect"
      end
    end

    :ok
  end

  @impl true
  def config_change(changed, _new, removed) do
    CuriaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
