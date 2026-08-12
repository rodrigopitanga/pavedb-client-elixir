# (C) 2026 Rodrigo Rodrigues da Silva <rodrigo@flowlexi.com>
# SPDX-License-Identifier: Apache-2.0

defmodule PaveDBClient.MixProject do
  use Mix.Project

  # The client encodes and decodes with OTP's built-in :json, which arrived in
  # OTP 27. Elixir 1.17 is the first release that runs on it.
  @otp_required 27

  if String.to_integer(System.otp_release()) < @otp_required do
    Mix.raise(
      "pavedb_client needs OTP #{@otp_required} or later for the :json module, " <>
        "found OTP #{System.otp_release()}"
    )
  end

  def project do
    [
      app: :pavedb_client,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir client for PaveDB",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:inets, :logger, :ssl]
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
      links: %{"GitLab" => "https://gitlab.com/flowlexi/pavedb-client-elixir"}
    ]
  end
end
