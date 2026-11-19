defmodule Efi.OpenFinance.ScheduledPayment do
  @moduledoc """
  Pix agendado iniciado pelo Open Finance: o pagador autoriza hoje, no banco dele, um Pix que
  sai numa data futura.

  O fluxo é o mesmo do `Efi.OpenFinance.ImmediatePayment` (redirecionamento ao banco, volta ao
  `redirectURL`, resultado pelo webhook, chave de idempotência obrigatória em `create/4`). A
  diferença está em `"pagamento" => %{"dataAgendamento" => "AAAA-MM-DD"}`, que aceita datas até
  um ano à frente.

      {:ok, %{"identificadorPagamento" => payment_id, "redirectURI" => bank_url}} =
        Efi.OpenFinance.ScheduledPayment.create(
          client,
          "0b6f3f0e-3d43-4b0e-9a6b-2a1d6c7e9f10",
          %{
            "pagador" => %{
              "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002",
              "cpf" => "12345678909"
            },
            "favorecido" => %{"chave" => "chave-pix-do-studio-ana"},
            "pagamento" => %{"valor" => "120.00", "dataAgendamento" => "2026-12-05"}
          }
        )

  Depois da autorização, o webhook chega com `"status" => "agendado"` e `"dataOperacao"`; no
  dia, chega de novo com `aceito` ou `rejeitado` (saldo insuficiente, por exemplo). Até a
  data, `cancel/3` desiste do agendamento.
  """

  alias Efi.Client

  @doc """
  Registra um Pix agendado e devolve o `redirectURI` que leva o pagador ao banco dele.
  `idempotency_key` vai no header `x-idempotency-key`.

  `POST /v1/pagamentos-agendados/pix` · escopo `gn.opb.payment.pix.send`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-agendados#solicitar-iniciação-de-pix-agendado-via-open-finance)
  """
  @spec create(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, idempotency_key, payment, opts \\ [])
      when is_binary(idempotency_key) do
    opts = Keyword.merge(opts, json: payment, idempotency_key: idempotency_key)
    Client.request(client, :open_finance, :post, "/v1/pagamentos-agendados/pix", opts)
  end

  @doc """
  Lista os pagamentos agendados criados entre `inicio` e `fim` (datas `AAAA-MM-DD`,
  obrigatórios). Filtros opcionais: `status`, `quantidade`, `pagina` e `identificador`.

  `GET /v1/pagamentos-agendados/pix` · escopo `gn.opb.payment.pix.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-agendados#listar-pagamentos-agendados-por-um-determinado-período)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    opts = Keyword.put(opts, :params, params)
    Client.request(client, :open_finance, :get, "/v1/pagamentos-agendados/pix", opts)
  end

  @doc """
  Cancela um pagamento agendado que ainda não saiu.

  `PATCH /v1/pagamentos-agendados/pix/:identificadorPagamento/cancelar` · escopo `gn.opb.payment.pix.cancel`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-agendados#cancelar-um-pagamento-agendado)
  """
  @spec cancel(Client.t(), String.t(), keyword()) :: Efi.result()
  def cancel(%Client{} = client, payment_id, opts \\ []) do
    path =
      Client.path("/v1/pagamentos-agendados/pix/:identificadorPagamento/cancelar",
        identificadorPagamento: payment_id
      )

    Client.request(client, :open_finance, :patch, path, opts)
  end

  @doc """
  Devolve ao pagador todo ou parte de um pagamento agendado que já saiu, com
  `%{"endToEndId" => ..., "valor" => "10.00"}`.

  `POST /v1/pagamentos-agendados/pix/:identificadorPagamento/devolver` · escopo `gn.opb.payment.pix.refund`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-agendados#efetuar-uma-devolução-de-um-pagamento-agendado)
  """
  @spec refund(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def refund(%Client{} = client, payment_id, refund, opts \\ []) do
    path =
      Client.path("/v1/pagamentos-agendados/pix/:identificadorPagamento/devolver",
        identificadorPagamento: payment_id
      )

    Client.request(client, :open_finance, :post, path, Keyword.put(opts, :json, refund))
  end
end
