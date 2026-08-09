# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :pavedb_client,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir client for PaveDB",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:inets, :logger, :public_key]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "docs/reference",
        "mix.exs",
        "README.md",
        "LICENSE",
        "Makefile"
      ],
      licenses: ["Apache-2.0"],
      links: %{"GitLab" => "https://gitlab.com/flowlexi/pavedb-elixir-client"}
    ]
  end
end
