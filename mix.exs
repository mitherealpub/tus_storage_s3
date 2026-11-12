defmodule Tus.Storage.S3.MixProject do
  use Mix.Project

  @version File.read!("VERSION") |> String.trim()

  def project do
    [
      app: :tus_storage_s3,
      version: @version,
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      description:
        "Amazon S3 (or compatible) storage backend for the Tus server",
      deps: deps(),
      package: package(),
      dialyzer: [ignore_warnings: "dialyzer.ignore-warnings"]
    ]
  end

  def package() do
    [
      files: ~w(lib mix.exs README.md LICENSE VERSION),
      licenses: ["BSD 3-Clause License"],
      maintainers: ["Jason Clark", "mithereal@gmail.com"],
      links: %{github: "https://github.com/data-twister/tus-storage-s3"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tus, "~> 0.1.3"},
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:telemetry, "~> 1.2"},
      # Optional HTTP/XML dependencies used by ExAws in tests or standalone runs
      {:hackney, "~> 1.20", optional: true},
      {:sweet_xml, "~> 0.7", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

    defp docs do
    [
      main: "Tus.Storage.S3",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
