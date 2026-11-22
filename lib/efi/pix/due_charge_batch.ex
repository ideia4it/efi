defmodule Efi.Pix.DueChargeBatch do
  @moduledoc """
  Lote de cobranças com vencimento (`lotecobv`): de 1 a 1000 cobranças `cobv` criadas numa
  chamada só, debaixo de um `id` numérico escolhido por quem cobra.

  A documentação da Efí avisa que a criação de lotes (`create/4`) está temporariamente
  desativada para manutenção. Confira a página antes de depender dela.

  O processamento é assíncrono: `create/4` e `update/4` respondem 202 sem corpo (`{:ok, nil}`), e
  o resultado de cada cobrança aparece em `get/3`, no `status` de cada item de `cobsv`:
  `EM_PROCESSAMENTO`, `CRIADA` ou `NEGADA`, este com o motivo em `problema`. Uma cobrança
  `EM_PROCESSAMENTO` ou `NEGADA` ainda não existe para `Efi.Pix.DueCharge.get/3`. Depois de
  criadas, as cobranças do lote saem em `Efi.Pix.DueCharge.list/3` com o filtro `loteCobVId`.

      {:ok, nil} =
        Efi.Pix.DueChargeBatch.create(client, 202_612, %{
          "descricao" => "Mensalidades de dezembro do Studio Ana",
          "cobsv" => [
            %{
              "txid" => "studioana0000000000000000001",
              "calendario" => %{"dataDeVencimento" => "2026-12-10"},
              "devedor" => %{"cpf" => "12345678909", "nome" => "Cliente do Studio Ana"},
              "valor" => %{"original" => "150.00"},
              "chave" => "chave-pix-do-studio-ana"
            }
          ]
        })

      {:ok, %{"cobsv" => charges}} = Efi.Pix.DueChargeBatch.get(client, 202_612)

  O conjunto de cobranças de um lote nunca muda: não dá para incluir nem tirar cobranças depois
  da criação. Repetir `create/4` com o mesmo `id` altera o lote, mas exige exatamente as mesmas
  cobranças do pedido original; `update/4` revisa só algumas delas. Uma cobrança criada por
  `Efi.Pix.DueCharge.create/4` não entra num lote depois, e uma cobrança de lote não muda de lote.

  Os escopos dos lotes estão invertidos na Efí: `lotecobv.read` libera a criação e a revisão, e
  `lotecobv.write` libera a consulta. A página de credenciais da Efí descreve os dois assim, então
  habilite ambos na aplicação.
  """

  alias Efi.Client

  @doc """
  Cria um lote de cobranças com vencimento, ou altera todas as cobranças de um lote existente.

  `PUT /v2/lotecobv/:id` · escopo `lotecobv.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-lote#criaralterar-lote-de-cobranças-com-vencimento)
  """
  @spec create(Client.t(), integer() | String.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, id, body, opts \\ []) do
    path = Client.path("/v2/lotecobv/:id", id: id)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Revisa cobranças específicas de um lote, sem precisar mandar as outras.

  `PATCH /v2/lotecobv/:id` · escopo `lotecobv.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-lote#revisar-cobranças-específicas-de-um-lote)
  """
  @spec update(Client.t(), integer() | String.t(), map(), keyword()) :: Efi.result()
  def update(%Client{} = client, id, changes, opts \\ []) do
    path = Client.path("/v2/lotecobv/:id", id: id)
    Client.request(client, :pix, :patch, path, Keyword.put(opts, :json, changes))
  end

  @doc """
  Consulta um lote e a situação de cada cobrança dele.

  `GET /v2/lotecobv/:id` · escopo `lotecobv.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-lote#consultar-lote-de-cobranças-com-vencimento)
  """
  @spec get(Client.t(), integer() | String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, id, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/lotecobv/:id", id: id), opts)
  end

  @doc """
  Lista os lotes criados entre `inicio` e `fim` (RFC 3339, obrigatórios). Filtros opcionais:
  `paginacao.paginaAtual` e `paginacao.itensPorPagina`.

  `GET /v2/lotecobv` · escopo `lotecobv.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-lote#consultar-lista-de-lotes-de-cobranças-com-vencimento)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/lotecobv", Client.put_params(opts, params))
  end
end
