defmodule Efi.OpenFinance.AutomaticPayment do
  @moduledoc """
  Pix Automático pelo Open Finance: o pagador adere uma vez, no banco dele, a cobranças
  periódicas, e o recebedor cria cada pagamento do ciclo sem pedir nova autorização.

  Exige Conta Digital Efí Empresas. Não confundir com o Pix Automático da API Pix (rotas
  `/v2/rec`), em que a Efí é o PSP recebedor e o pagador aceita a recorrência a partir de um QR
  Code ou de uma solicitação no app do banco.

  ## Adesão

  `create_enrollment/3` recebe o pagador, a conta que recebe em `"favorecido"` e as regras em
  `"assinatura"`: `"expiracao"`, `"intervalo"` (`SEMANAL`, `MENSAL`, `TRIMESTRAL`,
  `SEMESTRAL` ou `ANUAL`), `"dataInicio"` e o valor, fixo (`"valorFixo"`) ou numa faixa
  (`"valorMinimo"` e `"valorMaximo"`). O `"primeiroPagamento"` opcional, com data e valor, é o
  pagamento da própria adesão.

      {:ok, %{"identificadorAdesao" => enrollment_id, "redirectURI" => bank_url}} =
        Efi.OpenFinance.AutomaticPayment.create_enrollment(client, %{
          "pagador" => %{
            "cpf" => "12345678909",
            "nome" => "Cliente do Studio Ana",
            "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002"
          },
          "favorecido" => %{
            "contaBanco" => %{
              "nome" => "Studio Ana",
              "documento" => "11222333000181",
              "codigoBanco" => "09089356",
              "agencia" => "0001",
              "conta" => "1234567",
              "tipoConta" => "CACC"
            }
          },
          "assinatura" => %{
            "expiracao" => "2027-12-31",
            "descricao" => "Clube de escova mensal",
            "configuracao" => %{
              "automatico" => %{
                "valorFixo" => "150.00",
                "intervalo" => "MENSAL",
                "dataInicio" => "2026-12-10"
              }
            }
          }
        })

  O pagador abre o `redirectURI`, aprova a adesão no banco e volta ao `redirectURL` da
  aplicação (veja `Efi.OpenFinance.Config`). O webhook chega com `"tipo" => "adesao"` e
  `"status" => "aceito"` ou `"rejeitado"`.

  ## Pagamentos

  A cada ciclo, `create/4` cria o pagamento da adesão com o valor e a data em que ele deve
  sair. O webhook chega com `"tipo" => "pagamento"`, primeiro `agendado` e depois `aceito`,
  `rejeitado` ou `cancelado`. `cancel/3` desiste de um pagamento antes da data, e
  `update_enrollment/4` com `"status" => "revogado"` encerra a adesão.

  `create/4` e `update_enrollment/4` exigem a chave de idempotência, que vai no header
  `x-idempotency-key` (de 36 a 72 caracteres). `create_enrollment/3` não exige.
  """

  alias Efi.Client

  @doc """
  Pede a adesão do pagador ao Pix Automático e devolve o `redirectURI` onde ele aprova.

  `POST /v1/pagamentos-automaticos/adesao` · escopo `gn.opb.automatic.consent.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-automaticos#solicitar-criação-de-uma-adesão-para-um-pagamento-automático)
  """
  @spec create_enrollment(Client.t(), map(), keyword()) :: Efi.result()
  def create_enrollment(%Client{} = client, enrollment, opts \\ []) do
    opts = Keyword.put(opts, :json, enrollment)
    Client.request(client, :open_finance, :post, "/v1/pagamentos-automaticos/adesao", opts)
  end

  @doc """
  Lista as adesões criadas entre `inicio` e `fim` (datas `AAAA-MM-DD`) com o `status`
  informado (`autorizado`, `pendente`, `revogado`, `finalizado` ou `rejeitado`), os três
  obrigatórios. Filtros opcionais: `identificadorAdesao`, `idProprio` e `documento` do
  favorecido.

  `GET /v1/pagamentos-automaticos/adesao` · escopo `gn.opb.automatic.consent.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-automaticos#consultar-os-parâmetros-de-uma-adesão)
  """
  @spec list_enrollments(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list_enrollments(%Client{} = client, params, opts \\ []) do
    opts = Keyword.put(opts, :params, params)
    Client.request(client, :open_finance, :get, "/v1/pagamentos-automaticos/adesao", opts)
  end

  @doc """
  Altera uma adesão identificada por `"identificador"`. Hoje a Efí só aceita mudar o status,
  para revogar: `%{"identificador" => ..., "status" => "revogado"}`. `idempotency_key` vai no
  header `x-idempotency-key`.

  `PATCH /v1/pagamentos-automaticos/adesao` · escopo `gn.opb.automatic.consent.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-automaticos#editar-uma-adesão)
  """
  @spec update_enrollment(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def update_enrollment(%Client{} = client, idempotency_key, changes, opts \\ [])
      when is_binary(idempotency_key) do
    opts = Keyword.merge(opts, json: changes, idempotency_key: idempotency_key)
    Client.request(client, :open_finance, :patch, "/v1/pagamentos-automaticos/adesao", opts)
  end

  @doc """
  Cria um pagamento de uma adesão aprovada, com `"identificadorAdesao"` e
  `"pagamento" => %{"valor" => ..., "data" => "AAAA-MM-DD"}`. `idempotency_key` vai no header
  `x-idempotency-key`.

  `POST /v1/pagamentos-automaticos/pix` · escopo `gn.opb.automatic.payment.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-automaticos#solicitar-criação-de-um-pagamento-automatico)
  """
  @spec create(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, idempotency_key, payment, opts \\ [])
      when is_binary(idempotency_key) do
    opts = Keyword.merge(opts, json: payment, idempotency_key: idempotency_key)
    Client.request(client, :open_finance, :post, "/v1/pagamentos-automaticos/pix", opts)
  end

  @doc """
  Consulta os pagamentos de uma adesão pelo `identificadorAdesao` (obrigatório), ou um
  pagamento só com o `endToEndId` opcional. Os pagamentos voltam em `"pagamentos"`.

  `GET /v1/pagamentos-automaticos/pix` · escopo `gn.opb.automatic.payment.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-automaticos#consultar-pagamentos-automaticos)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    opts = Keyword.put(opts, :params, params)
    Client.request(client, :open_finance, :get, "/v1/pagamentos-automaticos/pix", opts)
  end

  @doc """
  Cancela um pagamento que ainda não saiu. O corpo leva o `"identificadorAdesao"` e o
  `"endToEndId"` do pagamento, os dois obrigatórios.

  `PATCH /v1/pagamentos-automaticos/pix` · escopo `gn.opb.automatic.payment.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-automaticos#solicitar-o-cancelamento-de-um-pagamento-automatico)
  """
  @spec cancel(Client.t(), map(), keyword()) :: Efi.result()
  def cancel(%Client{} = client, cancellation, opts \\ []) do
    opts = Keyword.put(opts, :json, cancellation)
    Client.request(client, :open_finance, :patch, "/v1/pagamentos-automaticos/pix", opts)
  end
end
