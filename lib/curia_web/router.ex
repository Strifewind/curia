defmodule CuriaWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", CuriaWeb do
    pipe_through(:browser)

    live_session :dashboard,
      layout: false,
      root_layout: {CuriaWeb.Layouts, :app} do
      live("/", DashboardLive, :index)
    end
  end
end