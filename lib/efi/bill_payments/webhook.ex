defmodule Efi.BillPayments.Webhook do
  @moduledoc """
  Webhook do Pagamento de Contas: a URL que a Efí chama a cada mudança de status de um
  pagamento pedido em `Efi.BillPayments.Payment.create/4`.

      {:ok, _webhook} =
        Efi.BillPayments.Webhook.configure(client, %{
          "url" => "https://app.example.com/efi/pagamentos"
        })

  A URL precisa de HTTPS e de mTLS com a cadeia pública da Efí, no mesmo padrão do webhook Pix
  ([como configurar o servidor](https://dev.efipay.com.br/docs/api-pix/webhooks#entendendo-o-padrão-mtls)).

  ## A notificação

  A Efí faz um `POST` na URL com o `identificador` do pagamento, o `status` anterior e o
  atual, o `valor`, os horários em `horario` e, em `efiExtras`, o código de barras, a data de
  execução, o protocolo e o `motivoRecusa` quando não foi pago:

      %{
        "identificador" => "5968942",
        "status" => %{"anterior" => "EXECUTADO", "atual" => "LIQUIDADO"},
        "valor" => "650.00",
        "horario" => %{
          "solicitacao" => "2024-02-01T15:12:21",
          "liquidacao" => "2024-02-01T15:12:33"
        },
        "efiExtras" => %{"dataExecucao" => "2024-02-01", "motivoRecusa" => nil}
      }

  O `valor` da notificação vem em reais, como texto (`"650.00"`), e não em centavos como no
  pedido de pagamento. A Efí espera um 2xx em até 60 segundos. Sem isso, tenta de novo até 10
  vezes: a primeira 5 minutos depois e as seguintes em intervalos cada vez maiores.
  """

  alias Efi.Client

  @doc """
  Cadastra a `url` que recebe as mudanças de status dos pagamentos.

  `PUT /v1/webhook` · escopo `payment.webhook.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pagamento-de-contas/webhooks#criar-webhook-de-pagamento)
  """
  @spec configure(Client.t(), map(), keyword()) :: Efi.result()
  def configure(%Client{} = client, body, opts \\ []) do
    Client.request(client, :bill_payments, :put, "/v1/webhook", Keyword.put(opts, :json, body))
  end

  @doc """
  Lista os webhooks criados entre `dataInicio` e `dataFim` (data e hora em RFC 3339,
  obrigatórios).

  `GET /v1/webhook` · escopo `payment.webhook.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pagamento-de-contas/webhooks#listar-webhooks-de-pagamento)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(
      client,
      :bill_payments,
      :get,
      "/v1/webhook",
      Keyword.put(opts, :params, params)
    )
  end

  @doc """
  Apaga o webhook da `url` informada no corpo, como `%{"url" => "https://..."}`. A resposta não
  tem corpo e volta como `{:ok, nil}`.

  `DELETE /v1/webhook` · escopo `payment.webhook.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pagamento-de-contas/webhooks#deletar-webhook-de-pagamento)
  """
  @spec delete(Client.t(), map(), keyword()) :: Efi.result()
  def delete(%Client{} = client, body, opts \\ []) do
    Client.request(
      client,
      :bill_payments,
      :delete,
      "/v1/webhook",
      Keyword.put(opts, :json, body)
    )
  end
end
