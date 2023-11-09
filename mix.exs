defmodule Reactive.MixProject do
  use Mix.Project

  @source_url "https://github.com/danielrw7/reactive_state"

  def project do
    [
      app: :reactive_state,
      version: "0.2.4",
      elixir: "~> 1.14",
      deps: deps(),
      description:
        "A simple library for creating and managing reactive state through GenServer processes",
      package: package(),
      name: "Reactive State",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    []
  end

  defp deps do
    [
      {:ex_doc, "~> 0.27", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        GitHub: @source_url
      }
    ]
  end

  defp docs do
    [
      main: "Reactive"
    ]
  end
end
