defmodule Curia.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Curia.PubSub},
      Curia.Poller,
      Curia.McuBridge,
      CuriaWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Curia.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    CuriaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
