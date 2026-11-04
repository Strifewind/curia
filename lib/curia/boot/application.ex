defmodule Curia.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.fetch_env!(:curia, :recovery) do
        []
      else
        [
          {Phoenix.PubSub, name: Curia.PubSub},
          {Task.Supervisor, name: Curia.PollerTaskSupervisor},
          Curia.Poller,
          Curia.McuBridge,
          CuriaWeb.Endpoint
        ]
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Curia.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    unless Application.fetch_env!(:curia, :recovery) do
      CuriaWeb.Endpoint.config_change(changed, removed)
    end

    :ok
  end
end
