defmodule Tinycc.MixProject do
  use Mix.Project

  def project do
    [
      app: :tinycc,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:rebar3] ++ Mix.compilers
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
      {:mix_rebar3, github: "dominicletz/mix_rebar3"}
    ]
  end
end
