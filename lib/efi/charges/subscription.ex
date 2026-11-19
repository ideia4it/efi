defmodule Efi.Charges.Subscription do
  @moduledoc """
  Assinatura: a inscrição de um cliente num `Efi.Charges.Plan`, que gera uma cobrança igual à
  primeira a cada `interval` do plano.

  Há três jeitos de criar:

    * `create_one_step/4`: assinatura e forma de pagamento juntas;
    * `create/4` e depois `set_payment_method/4`: a assinatura nasce `new` e fica `active`
      quando a forma de pagamento é definida;
    * `create_with_payment_link/4`: o cliente escolhe como pagar na tela da Efí.

  ```elixir
  {:ok, %{"data" => %{"subscription_id" => subscription_id}}} =
    Efi.Charges.Subscription.create_one_step(client, plan_id, %{
      "items" => [%{"name" => "Clube de escova mensal", "value" => 9_900, "amount" => 1}],
      "metadata" => %{"notification_url" => "https://app.example.com/efi/notificacoes"},
      "payment" => %{
        "credit_card" => %{
          "customer" => %{
            "name" => "Cliente do Studio Ana",
            "cpf" => "12345678909",
            "email" => "cliente@app.example.com",
            "birth" => "1990-08-29",
            "phone_number" => "5144916523"
          },
          "billing_address" => %{
            "street" => "Rua das Flores",
            "number" => "100",
            "neighborhood" => "Centro",
            "zipcode" => "35400000",
            "city" => "Ouro Preto",
            "state" => "MG"
          },
          "payment_token" => payment_token
        }
      }
    })
  ```

  No cartão, o `payment_token` vem da biblioteca JavaScript da Efí (veja `Efi.Charges.Card`) e
  o cliente informa o cartão só na primeira cobrança; `trial_days` dá dias de teste grátis e
  só vale para cartão. No boleto, a Efí manda cada boleto por e-mail 10 dias antes do
  vencimento, e um vencimento em fim de semana ou feriado passa para o dia útil seguinte.

  A assinatura deixa de gerar cobranças quando o cliente ou o vendedor cancela (`canceled`) ou
  quando todas as cobranças do plano já saíram (`expired`). Uma cobrança de cartão recusada
  fica `unpaid` e pode ser tentada de novo com `Efi.Charges.Card.retry/4`. As cobranças de
  assinatura por boleto aparecem em `Efi.Charges.Charge.list/3`.
  """

  alias Efi.Client

  @typedoc "Identificador da assinatura na Efí (`subscription_id`)."
  @type subscription_id :: pos_integer() | String.t()

  @doc """
  Cria uma assinatura no plano, com status `new` e sem forma de pagamento.

  `POST /v1/plan/:id/subscription`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#1-crie-inscrições-assinaturas-para-vincular-ao-plano)
  """
  @spec create(Client.t(), Efi.Charges.Plan.plan_id(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, plan_id, body, opts \\ []) do
    path = Client.path("/v1/plan/:id/subscription", id: plan_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Cria uma assinatura no plano já com a forma de pagamento: `payment.banking_billet` ou
  `payment.credit_card`.

  `POST /v1/plan/:id/subscription/one-step`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#crie-inscrições-assinaturas-para-vincular-ao-plano-em-one-step)
  """
  @spec create_one_step(Client.t(), Efi.Charges.Plan.plan_id(), map(), keyword()) ::
          Efi.result()
  def create_one_step(%Client{} = client, plan_id, body, opts \\ []) do
    path = Client.path("/v1/plan/:id/subscription/one-step", id: plan_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Cria uma assinatura no plano com um link de pagamento: a resposta traz a `payment_url` e o
  `charge.id` da primeira cobrança, que é o usado em `resend_link/4`.

  `POST /v1/plan/:id/subscription/one-step/link`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#associar-plano-ao-link-de-pagamento)
  """
  @spec create_with_payment_link(Client.t(), Efi.Charges.Plan.plan_id(), map(), keyword()) ::
          Efi.result()
  def create_with_payment_link(%Client{} = client, plan_id, body, opts \\ []) do
    path = Client.path("/v1/plan/:id/subscription/one-step/link", id: plan_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Define a forma de pagamento de uma assinatura `new` e os dados do cliente.

  `POST /v1/subscription/:id/pay`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#2-defina-a-forma-de-pagamento-da-assinatura-e-os-dados-do-cliente)
  """
  @spec set_payment_method(Client.t(), subscription_id(), map(), keyword()) :: Efi.result()
  def set_payment_method(%Client{} = client, subscription_id, payment, opts \\ []) do
    path = Client.path("/v1/subscription/:id/pay", id: subscription_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, payment))
  end

  @doc """
  Consulta uma assinatura: plano, próxima cobrança e histórico de cobranças.

  `GET /v1/subscription/:id`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#retornar-informações-de-uma-assinatura-vinculada-a-um-plano)
  """
  @spec get(Client.t(), subscription_id(), keyword()) :: Efi.result()
  def get(%Client{} = client, subscription_id, opts \\ []) do
    path = Client.path("/v1/subscription/:id", id: subscription_id)
    Client.request(client, :charges, :get, path, opts)
  end

  @doc """
  Altera uma assinatura ativa de cartão de crédito: plano, cliente, itens, frete ou cartão
  (`payment_token`). Assinatura de boleto não muda.

  `PUT /v1/subscription/:id`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#alterar-dados-de-uma-assinatura)
  """
  @spec update(Client.t(), subscription_id(), map(), keyword()) :: Efi.result()
  def update(%Client{} = client, subscription_id, changes, opts \\ []) do
    path = Client.path("/v1/subscription/:id", id: subscription_id)
    Client.request(client, :charges, :put, path, Keyword.put(opts, :json, changes))
  end

  @doc """
  Define ou troca a `notification_url` e o `custom_id` de uma assinatura.

  `PUT /v1/subscription/:id/metadata`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#incluir-notification_url-e-custom_id-em-uma-assinatura-existente)
  """
  @spec update_metadata(Client.t(), subscription_id(), map(), keyword()) :: Efi.result()
  def update_metadata(%Client{} = client, subscription_id, metadata, opts \\ []) do
    path = Client.path("/v1/subscription/:id/metadata", id: subscription_id)
    Client.request(client, :charges, :put, path, Keyword.put(opts, :json, metadata))
  end

  @doc """
  Cancela uma assinatura ativa. O cliente e o vendedor recebem um e-mail da Efí.

  `PUT /v1/subscription/:id/cancel`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#cancelar-uma-assinatura)
  """
  @spec cancel(Client.t(), subscription_id(), keyword()) :: Efi.result()
  def cancel(%Client{} = client, subscription_id, opts \\ []) do
    path = Client.path("/v1/subscription/:id/cancel", id: subscription_id)
    Client.request(client, :charges, :put, path, opts)
  end

  @doc """
  Acrescenta uma mensagem própria ao histórico da assinatura, de 1 a 255 caracteres, sem mudar
  a assinatura: `%{"description" => "Cliente pediu troca de horário"}`.

  `POST /v1/subscription/:id/history`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#acrescentar-descrição-ao-histórico-de-uma-assinatura)
  """
  @spec add_history(Client.t(), subscription_id(), map(), keyword()) :: Efi.result()
  def add_history(%Client{} = client, subscription_id, body, opts \\ []) do
    path = Client.path("/v1/subscription/:id/history", id: subscription_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Reenvia para o e-mail informado o link de pagamento de uma assinatura criada com
  `create_with_payment_link/4`. Recebe o `charge_id` do link, não o `subscription_id`.

  `POST /v1/charge/:id/subscription/resend`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#reenvio-do-link-associado-ao-plano-para-o-email-desejado)
  """
  @spec resend_link(Client.t(), Efi.Charges.Charge.charge_id(), map(), keyword()) ::
          Efi.result()
  def resend_link(%Client{} = client, charge_id, body, opts \\ []) do
    path = Client.path("/v1/charge/:id/subscription/resend", id: charge_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end
end
