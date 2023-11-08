defmodule Reactive.MixProject do
  use Mix.Project

  def project do
    [
      app: :reactive_state,
      version: "0.2.2",
      elixir: "~> 1.14",
      deps: deps(),
      description:
        "A simple library for creating and managing reactive state through GenServer processes",
      package: [
        licenses: ["MIT"],
        links: %{}
      ],
      name: "Reactive State",
      source_url: "https://github.com/danielrw7/reactive_state",
      docs: [
        main: "Reactive"
      ]
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
end
