defmodule Riemannx.Mixfile do
  use Mix.Project

  @version "2.3.0"

  def project do
    [
      app: :riemannx,
      version: @version,
      elixir: "~> 1.3",
      package: package(),
      description: "A riemann client for elixir with UDP/TCP/TLS support.",
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: ["coveralls": :test, "coveralls.detail": :test, "coveralls.post": :test, "coveralls.html": :test],
      elixirc_paths: elixirc_paths(Mix.env),
      aliases: [test: "test --no-start"],
      dialyzer: [ignore_warnings: "./dialyzer.ignore-warnings", plt_add_apps: [:ssl, :stdlib, :public_key]] ++ dialyzer(),
      docs: [main: "Riemannx", source_ref: "v#{@version}",
             source_url: "https://github.com/hazardfn/riemannx",
             extras: ["README.md"]]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: applications(Mix.env),
      mod: {Riemannx.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/servers", "test/"]
  defp elixirc_paths(_),     do: ["lib"]

  defp applications(:test) do
    applications(:others) ++ [:propcheck]
  end
  defp applications(_) do
    [:poolboy, :logger, :exprotobuf]
  end
  defp deps do
    [
      {:exprotobuf, "~> 1.2.9"},
      {:poolboy, "~> 1.5"},
      {:excoveralls, "~> 0.7", only: [:test]},
      {:ex_doc, "~> 0.12", only: [:dev], runtime: false},
      {:propcheck, "~> 1.0", only: :test},
      {:dialyxir, "~> 0.5", only: [:test], runtime: false}
    ]
  end

  defp package do
    %{licenses: ["MIT"],
      maintainers: ["Howard Beard-Marlowe"],
      links: %{"GitHub" => "https://github.com/hazardfn/riemannx"}}
  end

  defp dialyzer do
    if travis?(), do: [plt_file: {:no_warn, System.get_env("PLT_LOCATION")}], else: []
  end
  defp travis? do
    if System.get_env("TRAVIS"), do: true, else: false
  end
end
