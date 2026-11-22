defmodule Efi.Test.Sandbox do
  @moduledoc false

  # Cliente de verdade contra a homologação da Efí, para `mix test --only sandbox`. As
  # credenciais vêm do ambiente e nunca do repositório:
  #
  #   EFI_SANDBOX_CLIENT_ID, EFI_SANDBOX_CLIENT_SECRET
  #   EFI_SANDBOX_CERTIFICATE  caminho do .p12 de homologação (a Cobranças não usa)
  #   EFI_SANDBOX_PIX_KEY      uma chave Pix da conta, para as cobranças

  def client(overrides \\ []) do
    {:ok, client} =
      [
        client_id: fetch!("EFI_SANDBOX_CLIENT_ID"),
        client_secret: fetch!("EFI_SANDBOX_CLIENT_SECRET"),
        environment: :sandbox,
        token_store: Efi.Test.ProcessTokenStore
      ]
      |> Keyword.merge(overrides)
      |> Keyword.put_new_lazy(:certificate, &certificate!/0)
      |> Efi.Client.new()

    client
  end

  def pix_key, do: fetch!("EFI_SANDBOX_PIX_KEY")

  def txid do
    suffix = Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    "efisandbox" <> suffix
  end

  defp certificate! do
    {:ok, certificate} =
      "EFI_SANDBOX_CERTIFICATE"
      |> fetch!()
      |> File.read!()
      |> Efi.Certificate.from_p12()

    certificate
  end

  defp fetch!(name) do
    System.get_env(name) ||
      raise "#{name} is not set: the sandbox suite needs Efí homologação credentials"
  end
end
