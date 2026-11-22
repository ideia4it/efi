defmodule Efi.Charges.Card do
  @moduledoc """
  Cobrança por cartão de crédito com autenticação 3DS, retentativa, estorno e parcelas.

  ## O `payment_token` nasce no navegador

  Toda cobrança de cartão leva um `payment_token`, que representa o cartão. Ele é gerado no
  navegador do pagador pela biblioteca JavaScript da Efí, `payment-token-efi`
  ([js-payment-token-efi](https://github.com/efipay/js-payment-token-efi)), com o
  identificador de conta (`payee_code`) da conta Efí. Nunca no servidor: assim o número do
  cartão não passa pelo app, e a Efí descontinuou a geração pelo back-end. Com `reuse: true` na
  biblioteca, o token pode ser usado de novo, mas cobrar sem o pagador na tela, como numa
  mensalidade, só pela assinatura (`Efi.Charges.Subscription`).

  ## Cobrança com 3DS

  `create/3` é a rota que a Efí recomenda para integrações novas. Na biblioteca JavaScript,
  gere o token com `enable3ds: true` e o valor total em `totalValue` para receber também o
  `tds_identifier`. `customer`, `payment_token` e `installments` vão na raiz do corpo, e
  `tds_info` é obrigatório. Toda cobrança 3DS exige o pagador presente: com um token já salvo,
  gere no navegador um `tds_identifier` novo para o valor da cobrança (`get3dsIdentifier`).

      {:ok, charge} =
        Efi.Charges.Card.create(client, %{
          "items" => [%{"name" => "Pacote de 4 escovas", "value" => 20_000, "amount" => 1}],
          "customer" => %{
            "name" => "Cliente do Studio Ana",
            "cpf" => "12345678909",
            "email" => "cliente@app.example.com"
          },
          "installments" => 1,
          "payment_token" => payment_token,
          "tds_info" => %{
            "tds_identifier" => tds_identifier,
            "challenge_callback_url" => "https://app.example.com/pagamento/3ds"
          },
          "metadata" => %{"notification_url" => "https://app.example.com/efi/notificacoes"}
        })

  A resposta (sem o envelope `data`) vem `approved`, `unpaid` com o motivo em `refusal`, ou
  `waiting` com `tds_challenge`: o banco pede o desafio, e o front-end o apresenta pelo
  `html_template` (num `iframe` com `srcdoc`) ou pelo `form_data` (um formulário `POST`). O
  pagador tem 10 minutos; depois disso a cobrança vai a `unpaid`. A volta para
  `challenge_callback_url` não confirma o pagamento: acompanhe pela
  `Efi.Charges.Notification` e trate `waiting` como pendente.

  Os erros desta rota vêm no formato `title`/`status`/`detail`, e não no `error`/
  `error_description` do resto da API Cobranças. `Efi.Error` lê os dois.

  Cobrança de cartão sem 3DS usa `Efi.Charges.Charge.create_one_step/3` ou
  `Efi.Charges.Charge.set_payment_method/4` com `payment.credit_card`. A Efí avisa que essa
  rota antiga de pagamento será descontinuada, em data ainda não anunciada.

  ## Homologação

  O último dígito do cartão usado para gerar o token decide o resultado: 0 apresenta o desafio
  3DS (um código terminado em 1 aprova, qualquer outro recusa), 1, 2 e 3 recusam, e de 4 a 9
  aprovam direto. Uma cobrança com desafio parada há mais de 2 minutos vira `unpaid`.

  A Efí exige o ramo de atividade cadastrado na conta e o formulário de KYC preenchido para
  liberar o limite de emissão por cartão.
  """

  alias Efi.Client

  @typedoc "Identificador da transação na Efí (`charge_id`)."
  @type charge_id :: pos_integer() | String.t()

  @doc """
  Cria uma cobrança de cartão de crédito com autenticação 3DS.

  `POST /v1/charge/card`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/cartao#criação-de-cobrança-por-cartão-de-crédito-com-autenticação-3ds)
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(client, :charges, :post, "/v1/charge/card", Keyword.put(opts, :json, body))
  end

  @doc """
  Tenta de novo o pagamento de uma cobrança de cartão `unpaid`, recusada por limite, dado
  errado ou falha temporária, sem emitir outra cobrança. O exemplo da Efí manda
  `"update_card" => true` em `payment.credit_card` junto do cartão novo, sem descrever o campo.

  Vale também para a cobrança de uma assinatura: se a retentativa paga a última cobrança
  pendente de uma assinatura cancelada, a assinatura volta a ficar ativa.

  `POST /v1/charge/:id/retry`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/cartao#retentativa-de-pagamento-via-cartão-de-crédito).
  Para assinatura, veja também a [página de assinatura](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#retentativa-de-pagamento-de-assinatura-via-cartão-de-crédito).
  """
  @spec retry(Client.t(), charge_id(), map(), keyword()) :: Efi.result()
  def retry(%Client{} = client, charge_id, payment, opts \\ []) do
    path = Client.path("/v1/charge/:id/retry", id: charge_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, payment))
  end

  @doc """
  Estorna um pagamento de cartão `paid`. Sem `json` nas opções, o estorno é total; com
  `json: %{"amount" => 1000}`, estorna só esse valor em centavos.

  O estorno parcial vale até 90 dias depois da confirmação, e um por dia; o total, até 360
  dias. Não há estorno enquanto outro da mesma cobrança está em processamento, nem para venda
  com split.

  `POST /v1/charge/card/:id/refund`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/cartao#estorno-de-pagamento-via-cartão-de-crédito)
  """
  @spec refund(Client.t(), charge_id(), keyword()) :: Efi.result()
  def refund(%Client{} = client, charge_id, opts \\ []) do
    path = Client.path("/v1/charge/card/:id/refund", id: charge_id)
    Client.request(client, :charges, :post, path, Keyword.put_new(opts, :json, %{}))
  end

  @doc """
  Lista as parcelas de uma compra para uma bandeira, já com os juros configurados na conta.
  `brand` (`visa`, `mastercard`, `amex` ou `elo`) e `total`, em centavos, são obrigatórios.

  `GET /v1/installments`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/cartao#listar-parcelas-de-acordo-com-a-bandeira-do-cartão)
  """
  @spec list_installments(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list_installments(%Client{} = client, params, opts \\ []) do
    Client.request(client, :charges, :get, "/v1/installments", Client.put_params(opts, params))
  end
end
