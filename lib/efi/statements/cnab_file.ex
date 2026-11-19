defmodule Efi.Statements.CnabFile do
  @moduledoc """
  Arquivos de extrato da conta Efí no padrão CNAB 240, para a conciliação bancária automática
  num ERP ou sistema financeiro.

  A Efí gera os arquivos conforme as recorrências cadastradas em `Efi.Statements.Recurrence`.
  `list/2` mostra os que já existem e `download/3` baixa um pelo `nome`:

      {:ok, [%{"nome" => file_name} | _other_files]} = Efi.Statements.CnabFile.list(client)
      {:ok, cnab} = Efi.Statements.CnabFile.download(client, file_name)

  O download volta como a Efí entrega: o texto CNAB, ou um `.zip` quando a recorrência pede
  `comprimir_arquivos`. Os erros desta API trazem só `mensagem`, então `%Efi.Error{}` vem com
  `message` e sem `name`.
  """

  alias Efi.Client

  @doc """
  Lista os arquivos CNAB gerados para a conta, cada um com `nome`, `data_geracao`,
  `periodo_inicio` e `periodo_fim`.

  `GET /v1/extrato-cnab/arquivos` · escopo `gn.cnab-statement.statement.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-extratos/extratos#consultar-arquivos-gerados)
  """
  @spec list(Client.t(), keyword()) :: Efi.result()
  def list(%Client{} = client, opts \\ []) do
    Client.request(client, :statements, :get, "/v1/extrato-cnab/arquivos", opts)
  end

  @doc """
  Baixa um arquivo de extrato pelo `nome` que `list/2` devolve. O conteúdo volta como binário,
  sem decodificar.

  `GET /v1/extrato-cnab/download/:nome_arquivo` · escopo `gn.cnab-statement.statement.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-extratos/extratos#solicitar-download-do-extrato)
  """
  @spec download(Client.t(), String.t(), keyword()) :: Efi.result()
  def download(%Client{} = client, file_name, opts \\ []) do
    path = Client.path("/v1/extrato-cnab/download/:nome_arquivo", nome_arquivo: file_name)
    Client.request(client, :statements, :get, path, opts)
  end
end
