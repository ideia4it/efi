defmodule Efi.Statements.Recurrence do
  @moduledoc """
  Recorrência do extrato CNAB 240: de quanto em quanto tempo a Efí gera o arquivo de extrato
  da conta, se avisa por e-mail e se entrega compactado.

      {:ok, _created} =
        Efi.Statements.Recurrence.create(client, %{
          "periodicidade" => "diario",
          "envia_email" => true,
          "comprimir_arquivos" => false
        })

  `periodicidade` é `"diario"`, `"semanal"` ou `"mensal"`, e ela mesma é o identificador da
  recorrência em `update/4`: não há outro id. Na revisão, os quatro campos são obrigatórios,
  não só os que mudam; para parar a geração, envie `"status" => "inativo"`.

  Os arquivos gerados ficam em `Efi.Statements.CnabFile`.
  """

  alias Efi.Client

  @doc """
  Lista as recorrências da conta, cada uma com `status`, `periodicidade`, `envia_email`,
  `comprimir_arquivos` e `data_criacao`.

  `GET /v1/extrato-cnab/agendamentos` · escopo `gn.cnab-statement.statement.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-extratos/extratos#consultar-recorrências-cadastradas)
  """
  @spec list(Client.t(), keyword()) :: Efi.result()
  def list(%Client{} = client, opts \\ []) do
    Client.request(client, :statements, :get, "/v1/extrato-cnab/agendamentos", opts)
  end

  @doc """
  Cria uma recorrência com `periodicidade`, `envia_email` e `comprimir_arquivos`, todos
  obrigatórios.

  `POST /v1/extrato-cnab/agendar` · escopo `gn.cnab-statement.statement.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-extratos/extratos#criar-recorrência)
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(
      client,
      :statements,
      :post,
      "/v1/extrato-cnab/agendar",
      Keyword.put(opts, :json, body)
    )
  end

  @doc """
  Revisa a recorrência da `periodicidade` informada (`"diario"`, `"semanal"` ou `"mensal"`).
  O corpo leva `periodicidade`, `status` (`"ativo"` ou `"inativo"`), `envia_email` e
  `comprimir_arquivos`, todos obrigatórios.

  `PATCH /v1/extrato-cnab/agendar/:identificador` · escopo `gn.cnab-statement.statement.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-extratos/extratos#revisar-recorrência)
  """
  @spec update(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def update(%Client{} = client, periodicity, changes, opts \\ []) do
    path = Client.path("/v1/extrato-cnab/agendar/:identificador", identificador: periodicity)
    Client.request(client, :statements, :patch, path, Keyword.put(opts, :json, changes))
  end
end
