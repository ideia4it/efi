defmodule Efi.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ideia4it/efi"

  @guides ~w(
    guides/primeiros-passos.md
    guides/parceiros.md
    guides/phoenix.md
  )

  def project do
    [
      app: :efi,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description:
        "Cliente Elixir para as APIs da Efí: Pix, Cobranças, Open Finance, Abertura de Contas, Pagamento de Contas e Extratos.",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      test_coverage: test_coverage()
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def application do
    [extra_applications: [:logger, :public_key, :crypto, :ssl]]
  end

  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(:test), do: ["lib", "dev", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:req, "~> 0.7"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "test --cover"
      ]
    ]
  end

  defp test_coverage do
    [
      ignore_modules: [~r/^Efi\.Test\./, ~r/^Mix\.Tasks\.Efi\./, ~r/^Efi\.Dev\./],
      summary: [threshold: 99]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Documentação da Efí" => "https://dev.efipay.com.br"},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md guides)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md" | @guides] ++ ["CHANGELOG.md"],
      groups_for_extras: [Guias: ~r/^guides\//],
      filter_modules: &published_module?/2,
      groups_for_modules: [
        Núcleo: [Efi, Efi.Client, Efi.Certificate, Efi.Token, Efi.TokenStore, Efi.Error],
        Pix: ~r/^Efi\.Pix\.(?!Automatic)/,
        "Pix Automático": ~r/^Efi\.Pix\.Automatic/,
        Cobranças: ~r/^Efi\.Charges\./,
        "Open Finance": ~r/^Efi\.OpenFinance\./,
        "Abertura de Contas": ~r/^Efi\.Accounts\./,
        "Pagamento de Contas": ~r/^Efi\.BillPayments\./,
        Extratos: ~r/^Efi\.Statements\./
      ]
    ]
  end

  defp published_module?(module, _metadata) do
    name = inspect(module)
    not String.starts_with?(name, ["Mix.Tasks.Efi.", "Efi.Dev.", "Efi.Test."])
  end
end
