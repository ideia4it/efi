defmodule Efi.Statements.SftpKey do
  @moduledoc """
  Chave de acesso SFTP da conta na API Extratos.

      {:ok, %{"privateKey" => private_key}} =
        Efi.Statements.SftpKey.generate(client, %{"conta" => 123456})

  A Efí descreve o escopo `gn.cnab-statement.keys.write` como redefinir as configurações do
  SFTP. A chave privada só aparece nesta resposta, porque nenhuma rota a devolve de novo:
  guarde-a cifrada.
  """

  alias Efi.Client

  @doc """
  Gera a chave SFTP da conta e devolve a `privateKey`. O corpo leva `conta`, o número da conta
  sem o dígito.

  A tabela de atributos da Efí pede `conta`; o texto da mesma seção e o SDK oficial em Node
  chamam a rota sem corpo.

  `POST /v1/extrato-cnab/gerar-chaves` · escopo `gn.cnab-statement.keys.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-extratos/extratos#gerar-chave)
  """
  @spec generate(Client.t(), map(), keyword()) :: Efi.result()
  def generate(%Client{} = client, body, opts \\ []) do
    Client.request(
      client,
      :statements,
      :post,
      "/v1/extrato-cnab/gerar-chaves",
      Keyword.put(opts, :json, body)
    )
  end
end
