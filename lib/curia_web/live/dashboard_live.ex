defmodule CuriaWeb.DashboardLive do
  use Phoenix.LiveView

  @topic "curia:health"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Curia.PubSub, @topic)
    {:ok, assign(socket, snapshot: Curia.Poller.snapshot())}
  end

  @impl true
  def handle_info({:health_snapshot, snapshot}, socket) do
    {:noreply, assign(socket, snapshot: snapshot)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="dashboard">
      <header class="topbar">
        <div>
          <p class="eyebrow">CURIA / HOMELAB</p>
          <h1>Infrastructure health</h1>
        </div>
        <p class="updated">
          Updated <%= format_time(@snapshot.updated_at) %>
        </p>
      </header>

      <section class="summary-grid" aria-label="Infrastructure summary">
        <article class="card cluster-card">
          <div class="card-heading">
            <div>
              <p class="eyebrow">KUBERNETES</p>
              <h2>Cluster nodes</h2>
            </div>
            <span class={"status status--#{@snapshot.cluster.state}"}>
              <%= status_text(@snapshot.cluster.state) %>
            </span>
          </div>
          <p class="metric">
            <strong><%= @snapshot.cluster.ready %></strong>
            <span>/ <%= @snapshot.cluster.total %> ready</span>
          </p>
          <p :if={@snapshot.cluster.error} class="muted"><%= @snapshot.cluster.error %></p>
          <div :if={@snapshot.cluster.nodes != []} class="node-list">
            <div :for={node <- @snapshot.cluster.nodes} class="node-row">
              <span class={"node-dot node-dot--#{if node.ready, do: "healthy", else: "down"}"}></span>
              <span class="node-name"><%= node.name %></span>
              <span class="node-capacity">
                CPU <%= Map.get(node.allocatable, "cpu", "—") %>
                <span aria-hidden="true">·</span>
                RAM <%= Map.get(node.allocatable, "memory", "—") %>
              </span>
            </div>
          </div>
        </article>

        <article :for={service <- @snapshot.services} class="card service-card">
          <div class="card-heading">
            <div>
              <p class="eyebrow">HTTP HEALTH CHECK</p>
              <h2><%= service.name %></h2>
            </div>
            <span class={"status status--#{service.state}"}>
              <%= status_text(service.state) %>
            </span>
          </div>
          <p class="metric">
            <strong><%= format_latency(service.latency_ms) %></strong>
            <span>latency</span>
          </p>
          <p :if={service.error} class="muted"><%= service.error %></p>
          <div :if={service.storage} class="storage">
            <div class="storage-heading">
              <span>Storage</span>
              <strong class={if service.storage.alert?, do: "storage-warning", else: ""}>
                <%= service.storage.percent %>%
              </strong>
            </div>
            <div class="storage-track" role="progressbar"
              aria-valuenow={service.storage.percent} aria-valuemin="0" aria-valuemax="100">
              <span class={if service.storage.alert?, do: "storage-fill storage-fill--warning", else: "storage-fill"}
                style={"width: #{min(service.storage.percent, 100)}%"}></span>
            </div>
            <p :if={service.storage.alert?} class="alert">
              Storage usage is above the configured threshold.
            </p>
            <p class="muted">
              <%= format_bytes(service.storage.used_bytes) %> used of
              <%= format_bytes(service.storage.total_bytes) %>
            </p>
          </div>
        </article>

        <article :if={@snapshot.services == []} class="card empty-card">
          <p class="eyebrow">SERVICE CHECKS</p>
          <h2>No endpoints configured</h2>
          <p class="muted">Set CURIA_ROUTER_URL and CURIA_NAS_URL in the target configuration.</p>
        </article>
      </section>

      <footer>
        <span>Live health snapshot</span>
        <span>Data is held in memory; no database or history is stored.</span>
      </footer>
    </main>
    """
  end

  defp format_time(nil), do: "waiting for first poll"
  defp format_time(datetime), do: Calendar.strftime(datetime, "%b %d, %Y %H:%M:%S UTC")

  defp format_latency(nil), do: "—"
  defp format_latency(milliseconds), do: "#{milliseconds} ms"

  defp format_bytes(bytes) do
    units = ["B", "KB", "MB", "GB", "TB"]
    format_bytes(bytes, units)
  end

  defp format_bytes(bytes, [unit]) when bytes < 1024, do: "#{bytes} #{unit}"
  defp format_bytes(bytes, [_unit]) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} PB"
  defp format_bytes(bytes, [unit | _]) when bytes < 1024, do: "#{bytes} #{unit}"
  defp format_bytes(bytes, [_unit | rest]), do: format_bytes(bytes / 1024, rest)

  defp status_text(:healthy), do: "Healthy"
  defp status_text(:degraded), do: "Degraded"
  defp status_text(:down), do: "Offline"
  defp status_text(_), do: "Unknown"
end
