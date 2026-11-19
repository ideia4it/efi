defmodule Efi.Charges.PaymentLink do
  @moduledoc """
  Link de pagamento: uma tela de pagamento hospedada pela Efí, para quem não quer montar o
  próprio checkout. O app manda o pagador para a `payment_url`, e ele paga por boleto, cartão
  ou Pix, conforme o `payment_method` (`banking_billet`, `credit_card` ou `all`).

      {:ok, %{"data" => %{"charge_id" => charge_id, "payment_url" => payment_url}}} =
        Efi.Charges.PaymentLink.create_one_step(client, %{
          "items" => [%{"name" => "Coloração", "value" => 18_000, "amount" => 1}],
          "metadata" => %{"notification_url" => "https://app.example.com/efi/notificacoes"},
          "customer" => %{"email" => "cliente@app.example.com"},
          "settings" => %{
            "payment_method" => "all",
            "expire_at" => "2026-12-20",
            "request_delivery_address" => false
          }
        })

  Em dois passos, crie a transação com `Efi.Charges.Charge.create/3` e gere o link com
  `create/4`. A transação passa ao status `link` e vai a `expired` no `expire_at`. Consulta,
  cancelamento, histórico e `notification_url` são os da transação, em `Efi.Charges.Charge`.

  ## Pegadinhas

    * se uma tentativa de pagamento falha (cartão recusado, pagador quis outra forma), a
      transação fica `waiting` ou `unpaid` presa àquela forma de pagamento: gere uma transação
      e um link novos;
    * `update/4` só funciona antes da confirmação do pagamento;
    * cobrança de link de pagamento não aceita baixa manual, nem quando paga por boleto;
    * `message` aceita até 80 caracteres;
    * a Efí exige o formulário de KYC preenchido para liberar o limite de emissão por cartão.
  """

  alias Efi.Client

  @typedoc "Identificador da transação na Efí (`charge_id`)."
  @type charge_id :: pos_integer() | String.t()

  @doc """
  Cria a transação e o link de pagamento num passo só.

  `POST /v1/charge/one-step/link`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/link-de-pagamento#criando-o-link-de-pagamento-em-one-step)
  """
  @spec create_one_step(Client.t(), map(), keyword()) :: Efi.result()
  def create_one_step(%Client{} = client, body, opts \\ []) do
    Client.request(
      client,
      :charges,
      :post,
      "/v1/charge/one-step/link",
      Keyword.put(opts, :json, body)
    )
  end

  @doc """
  Gera o link de pagamento de uma transação `new`, criada com `Efi.Charges.Charge.create/3`.

  `POST /v1/charge/:id/link`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/link-de-pagamento#2-crie-um-link-de-pagamento)
  """
  @spec create(Client.t(), charge_id(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, charge_id, settings, opts \\ []) do
    path = Client.path("/v1/charge/:id/link", id: charge_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, settings))
  end

  @doc """
  Altera a forma de pagamento aceita, os descontos, a mensagem, o vencimento ou o pedido de
  endereço de entrega de um link ainda não pago.

  `PUT /v1/charge/:id/link`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/link-de-pagamento#alterar-determinados-parâmetrosatributos-de-um-link-de-pagamento-existente)
  """
  @spec update(Client.t(), charge_id(), map(), keyword()) :: Efi.result()
  def update(%Client{} = client, charge_id, changes, opts \\ []) do
    path = Client.path("/v1/charge/:id/link", id: charge_id)
    Client.request(client, :charges, :put, path, Keyword.put(opts, :json, changes))
  end

  @doc """
  Reenvia o link de uma transação com status `link` para o e-mail informado:
  `%{"email" => "cliente@app.example.com"}`.

  `POST /v1/charge/:id/link/resend`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/link-de-pagamento#reenviar-link-de-pagamento-por-e-mail)
  """
  @spec resend(Client.t(), charge_id(), map(), keyword()) :: Efi.result()
  def resend(%Client{} = client, charge_id, body, opts \\ []) do
    path = Client.path("/v1/charge/:id/link/resend", id: charge_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end
end
