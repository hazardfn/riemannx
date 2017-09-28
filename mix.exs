defmodule Riemannx.Mixfile do
  use Mix.Project

  def project do
    [
      app: :riemannx,
      version: "0.0.7",
      elixir: "~> 1.3",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: ["coveralls": :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test],
      aliases: [test: "test --no-start"],
      elixirc_paths: elixirc_paths(Mix.env),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: [:poolboy, :logger, :exprotobuf],
      extra_applications: [:logger, :exprotobuf, :poolboy],
      mod: {Riemannx.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/servers"]
  defp elixirc_paths(_),     do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:exprotobuf, "~> 1.2.9"},
      {:poolboy, "~> 1.5"},
      {:excoveralls, "~> 0.7", only: [:test]}
    ]
  end
end
