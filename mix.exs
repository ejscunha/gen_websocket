defmodule GenWebsocket.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :gen_websocket,
      version: @version,
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
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
      {:ex_doc, "~> 0.20", only: :dev, runtime: false},
      {:socket, "~> 0.3.13", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      main: "GenWebsocket",
      source_ref: "v#{@version}",
      source_url: "https://github.com/ejscunha/gen_websocket"
    ]
  end
end
