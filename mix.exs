defmodule GenWebsocket.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :gen_websocket,
      version: @version,
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: "https://github.com/ejscunha/gen_websocket"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {GenWebsocket.Application, []}
    ]
  end

  defp deps do
    [
      {:gen_state_machine, "~> 2.0"},
      {:gun, "~> 1.3"},
      {:ex_doc, "~> 0.20", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A websocket client based on gun with a similar API to gen_tcp."
  end

  defp package do
    [
      maintainers: ["Eduardo Cunha"],
      licenses: ["MIT"],
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      links: %{"GitHub" => "https://github.com/ejscunha/gen_websocket"}
    ]
  end

  defp docs do
    [
      name: "gen_websocket",
      source_ref: "v#{@version}",
      main: "introduction",
      canonical: "http://hexdocs.pm/gen_websocket",
      source_url: "https://github.com/ejscunha/gen_websocket",
      extras: [
        "docs/introduction.md"
      ]
    ]
  end
end
