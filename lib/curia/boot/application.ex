defmodule Curia.Application do
  use Application

  @recovery Application.compile_env(:curia, :recovery, false)

  @impl true
  def start(_type, _args) do
    children =
      if @recovery do
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

  if @recovery do
    @impl true
    def config_change(_changed, _new, _removed), do: :ok
  else
    @impl true
    def config_change(changed, _new, removed) do
      CuriaWeb.Endpoint.config_change(changed, removed)

      :ok
    end
  end
end
