defmodule Niffler.MixProject do
  use Mix.Project

  @version "0.1.11"

  def project do
    [
      app: :niffler,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Niffler",
      compilers: [:rebar3] ++ Mix.compilers(),
      docs: docs(),
      package: package(),
      homepage_url: "https://github.com/dominicletz/niffler",
      description: """
      Just-In-Time nif generator
      """
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # {:mix_rebar3, github: "dominicletz/mix_rebar3"},
      {:mix_rebar3, path: "../mix_rebar3"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:benchee, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.22", only: :docs}
    ]
  end

  defp docs do
    [
      main: "introduction",
      source_ref: "v#{@version}",
      source_url: "https://github.com/dominicletz/niffler",
      extra_section: "GUIDES",
      extras: [
        "guides/introduction.md"
      ]
    ]
  end

  defp package do
    [
      maintainers: ["Dominic Letz"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/dominicletz/niffler"},
      files:
        ~w(c_src src lib priv) ++
          ~w(CHANGELOG.md LICENSE.md rebar.config mix.exs README.md)
    ]
  end
end
