defmodule Curia.MixProject do
  use Mix.Project

  def project do
    [
      app: :curia,
      version: "0.1.0",
      elixir: "~> 1.14",
      archives: [nerves_bootstrap: "~> 1.10"],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: [
        curia: [
          include_executables_for: [:unix],
          steps: [&Nerves.Release.init/1, :assemble]
        ]
      ]
    ]
  end

  def application do
    [
      mod: {Curia.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    application_deps() ++ target_deps(Mix.target())
  end

  defp application_deps do
    [
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:msgpax, "~> 2.4"},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:plug, "~> 1.16"},
      {:req, "~> 0.5"}
    ]
  end

  defp target_deps(:uno_q) do
    [
      {:circuits_gpio, "~> 2.0"},
      {:nerves, "~> 1.10", runtime: false},
      {:nerves_pack, "~> 0.7"},
      {:nerves_system_arduino_uno_q, "~> 0.1", runtime: false, targets: :uno_q}
    ]
  end

  defp target_deps(_host), do: []

  defp aliases do
    [
      "assets.deploy": ["cmd --cd assets npm run deploy"],
      "phx.server": ["assets.deploy", "phx.server"],
      firmware: ["assets.deploy", "firmware"]
    ]
  end
end
