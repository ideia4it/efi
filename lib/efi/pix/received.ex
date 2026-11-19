defmodule Efi.Pix.Received do
  @moduledoc """
  Pix recebidos: cada pagamento que entrou na conta, identificado pelo `endToEndId` (e2eId, 32
  caracteres) que o Banco Central atribui à transação.

  Use para conferir na Efí o pagamento que o webhook anunciou antes de dar baixa, e para
  conciliar um período. Pix de cobrança trazem o `txid`; as devoluções já feitas aparecem em
  `devolucoes`. Para devolver um Pix, veja `Efi.Pix.Refund`.

      {:ok, pix} = Efi.Pix.Received.get(client, "E12345678202611191200abcdef12345")

      pix["valor"]

  Com `params: %{"exibirCodigoBanco" => true}`, `get/3` traz o ISPB do banco de quem pagou em
  `pagador.contaBanco.codigoBanco`.
  """

  alias Efi.Client

  @doc """
  Consulta um Pix recebido pelo `e2eId`. Filtro opcional: `exibirCodigoBanco`.

  `GET /v2/pix/:e2eId` · escopo `pix.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/gestao-de-pix#consultar-pix-recebido)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, e2e_id, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/pix/:e2eId", e2eId: e2e_id), opts)
  end

  @doc """
  Lista os Pix recebidos entre `inicio` e `fim` (RFC 3339, obrigatórios). Filtros opcionais:
  `txid`, `txIdPresente`, `devolucaoPresente`, `cpf`, `cnpj`, `paginacao.paginaAtual` e
  `paginacao.itensPorPagina`.

  `GET /v2/pix` · escopo `pix.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/gestao-de-pix#consultar-lista-de-pix-recebidos)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/pix", Keyword.put(opts, :params, params))
  end
end
