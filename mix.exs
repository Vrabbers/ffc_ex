defmodule FfcEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :ffc_ex,
      version: "1.2.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    dev_apps =
      if Mix.env() != :prod do
        [:observer, :wx, :runtime_tools]
      else
        []
      end

    [
      extra_applications: [:logger | dev_apps],
      mod: {FfcEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nostrum, "~> 0.8"},
      {:hammer, "~> 6.2.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
