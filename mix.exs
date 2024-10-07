defmodule Niffler.MixProject do
  use Mix.Project

  @version "0.3.2"
  @name "Niffler"
  @url "https://github.com/dominicletz/niffler"
  @maintainers ["Dominic Letz"]

  def project do
    [
      app: :niffler,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: @name,
      compilers: [:rebar3] ++ Mix.compilers(),
      docs: docs(),
      package: package(),
      homepage_url: @url,
      description: """
      Just-In-Time nif generator, FFI generator, C-compiler based on TinyCC.
      For Linux, MacOS, Windows (msys2)
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
      {:mix_rebar3, "~> 0.2"},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:benchee, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: @name,
      source_ref: "v#{@version}",
      source_url: @url,
      authors: @maintainers,
      logo: "img/niffler_logo.png"
    ]
  end

  defp package do
    [
      maintainers: @maintainers,
      licenses: ["MIT"],
      links: %{github: @url},
      files:
        ~w(c_src src lib priv) ++
          ~w(CHANGELOG.md LICENSE.md rebar.config mix.exs README.md)
    ]
  end
end
