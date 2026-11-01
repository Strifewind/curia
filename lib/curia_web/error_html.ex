defmodule CuriaWeb.ErrorHTML do
  use Phoenix.Component

  def render("404.html", _assigns), do: ~H"<h1>Page not found</h1>"
  def render("500.html", _assigns), do: ~H"<h1>Internal server error</h1>"
  def render(_template, _assigns), do: ~H"<h1>Something went wrong</h1>"
end
