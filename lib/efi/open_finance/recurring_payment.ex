defmodule Efi.OpenFinance.RecurringPayment do
  @moduledoc """
  Pix recorrente iniciado pelo Open Finance: o pagador autoriza uma vez, no banco dele, uma
  série de Pix com datas definidas, e cada parcela sai sozinha na data.

  Serve para pacotes e mensalidades com número de parcelas conhecido. A Efí marca o recurso
  como beta, sujeito a mudanças.

  O fluxo é o mesmo do `Efi.OpenFinance.ImmediatePayment` (redirecionamento ao banco, volta ao
  `redirectURL`, resultado pelo webhook, chave de idempotência obrigatória em `create/4`). O
  cronograma vai em `"pagamento" => %{"recorrencia" => ...}`:

    * `"tipo" => "diaria"`, `"semanal"` ou `"mensal"`, com `"dataInicio"` e `"quantidade"`
      (de 2 a 60 parcelas, dentro de 2 anos); a semanal pede `"diaDaSemana"`
      (`"TERCA_FEIRA"`, por exemplo) e a mensal pede `"diaDoMes"`;
    * `"tipo" => "personalizada"`, com a lista `"datas"` e uma `"descricao"`.

  A primeira parcela sai no mínimo um dia depois da autorização, então `"dataInicio"` vai de
  amanhã até um ano à frente.

      {:ok, %{"identificadorPagamento" => payment_id, "redirectURI" => bank_url}} =
        Efi.OpenFinance.RecurringPayment.create(
          client,
          "9a3e1d2c-5b4f-4e6a-8c7d-1f2e3d4c5b6a",
          %{
            "pagador" => %{
              "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002",
              "cpf" => "12345678909"
            },
            "favorecido" => %{"chave" => "chave-pix-do-studio-ana"},
            "pagamento" => %{
              "valor" => "89.90",
              "infoPagador" => "Pacote de manicure",
              "recorrencia" => %{
                "tipo" => "mensal",
                "dataInicio" => "2026-12-10",
                "diaDoMes" => 10,
                "quantidade" => 6
              }
            }
          }
        )

  A série tem status próprio (`ativa`, `pendente`, `concluida`, `cancelada`, `expirada`) e
  cada parcela, identificada pelo `endToEndId`, tem o dela (`pendente`, `aceito`,
  `rejeitado`, `cancelado`). O webhook chega com `"tipo" => "recorrencia"` e a lista das
  parcelas em `"recorrencia"`. Uma parcela rejeitada ou cancelada pode ser trocada por outra
  com `replace_installment/4`.
  """

  alias Efi.Client

  @doc """
  Registra uma série de Pix recorrentes e devolve o `redirectURI` que leva o pagador ao banco
  dele. `idempotency_key` vai no header `x-idempotency-key`.

  `POST /v1/pagamentos-recorrentes/pix` · escopo `gn.opb.payment.pix.send`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-recorrentes#solicitar-iniciação-de-pix-recorrente-via-open-finance)
  """
  @spec create(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, idempotency_key, payment, opts \\ []) do
    opts = Keyword.merge(opts, json: payment, idempotency_key: idempotency_key)
    Client.request(client, :open_finance, :post, "/v1/pagamentos-recorrentes/pix", opts)
  end

  @doc """
  Lista as séries criadas entre `inicio` e `fim` (datas `AAAA-MM-DD`, obrigatórios), cada uma
  com as parcelas em `"recorrencias"`. Filtros opcionais: `status`, `quantidade`, `pagina` e
  `identificador`.

  `GET /v1/pagamentos-recorrentes/pix` · escopo `gn.opb.payment.pix.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-recorrentes#listar-pagamentos-recorrentes-por-um-determinado-período)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    opts = Keyword.put(opts, :params, params)
    Client.request(client, :open_finance, :get, "/v1/pagamentos-recorrentes/pix", opts)
  end

  @doc """
  Cancela as parcelas que ainda não saíram. Com o `identificadorPagamento`, cancela a série
  inteira; com o `endToEndId` de uma parcela no lugar dele, cancela só aquela parcela.

  `PATCH /v1/pagamentos-recorrentes/pix/:identificadorPagamento/cancelar` · escopo `gn.opb.payment.pix.cancel`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-recorrentes#cancelar-um-pagamento-recorrente)
  """
  @spec cancel(Client.t(), String.t(), keyword()) :: Efi.result()
  def cancel(%Client{} = client, payment_or_installment_id, opts \\ []) do
    path =
      Client.path("/v1/pagamentos-recorrentes/pix/:identificadorPagamento/cancelar",
        identificadorPagamento: payment_or_installment_id
      )

    Client.request(client, :open_finance, :patch, path, opts)
  end

  @doc """
  Devolve ao pagador parcelas que já saíram, várias de uma vez:
  `%{"devolucoes" => [%{"endToEndId" => ..., "valor" => "10.00"}]}`. A resposta é uma lista,
  uma devolução por parcela.

  `POST /v1/pagamentos-recorrentes/pix/:identificadorPagamento/devolver` · escopo `gn.opb.payment.pix.refund`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-recorrentes#efetuar-uma-devolução-de-um-pagamento-recorrente)
  """
  @spec refund(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def refund(%Client{} = client, payment_id, refunds, opts \\ []) do
    path =
      Client.path("/v1/pagamentos-recorrentes/pix/:identificadorPagamento/devolver",
        identificadorPagamento: payment_id
      )

    Client.request(client, :open_finance, :post, path, Keyword.put(opts, :json, refunds))
  end

  @doc """
  Troca uma parcela `cancelado` ou `rejeitado` por uma nova. Sem corpo, a nova parcela tem o
  valor da anterior; para outro valor, passe `json: %{"valor" => "99.90"}` em `opts`. A
  resposta traz um `redirectURI`: o pagador autoriza a nova parcela no banco dele.

  `PATCH /v1/pagamentos-recorrentes/pix/:identificadorPagamento/substituir/:endToEndId` · escopo `gn.opb.payment.pix.send`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-recorrentes#substituir-parcela-de-pagamento-recorrente)
  """
  @spec replace_installment(Client.t(), String.t(), String.t(), keyword()) :: Efi.result()
  def replace_installment(%Client{} = client, payment_id, end_to_end_id, opts \\ []) do
    path =
      Client.path(
        "/v1/pagamentos-recorrentes/pix/:identificadorPagamento/substituir/:endToEndId",
        identificadorPagamento: payment_id,
        endToEndId: end_to_end_id
      )

    Client.request(client, :open_finance, :patch, path, opts)
  end
end
