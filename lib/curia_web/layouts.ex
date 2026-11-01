defmodule CuriaWeb.Layouts do
  use Phoenix.Component

  def app(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>Curia | Homelab health</title>
        <link rel="stylesheet" href="/assets/app.css" />
        <script defer src="/assets/app.js"></script>
      </head>
      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end
end
