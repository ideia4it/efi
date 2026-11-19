defmodule Efi.Charges.Charge do
  @moduledoc """
  Transação da API Cobranças: a cobrança por boleto (Bolix, com QR Code Pix), cartão de crédito
  ou link de pagamento, identificada pelo `charge_id`.

  Valores são inteiros em centavos (`5990` é R$ 59,90). Toda resposta vem embrulhada no formato
  da API Cobranças, `%{"code" => 200, "data" => ...}`.

  ## Um passo ou dois

  `create_one_step/3` cria a transação já com a forma de pagamento. Em dois passos,
  `create/3` cria a transação com status `new` e `set_payment_method/4` define o boleto ou o
  cartão, e o status passa a `waiting`.

      {:ok, %{"data" => %{"charge_id" => charge_id, "barcode" => barcode}}} =
        Efi.Charges.Charge.create_one_step(client, %{
          "items" => [%{"name" => "Corte e escova", "value" => 12_000, "amount" => 1}],
          "metadata" => %{"notification_url" => "https://app.example.com/efi/notificacoes"},
          "payment" => %{
            "banking_billet" => %{
              "customer" => %{"name" => "Cliente do Studio Ana", "cpf" => "12345678909"},
              "expire_at" => "2026-12-15",
              "configurations" => %{"fine" => 200, "interest" => 33}
            }
          }
        })

  No boleto, `configurations.days_to_write_off` define em quantos dias (de 0 a 120) depois do
  vencimento o boleto deixa de ser pagável e vai a `expired`. `message` aceita até 4 linhas de
  100 caracteres, separadas por `\\n`. Cartão de crédito exige o `payment_token` gerado no
  navegador: veja `Efi.Charges.Card`.

  Para saber quando a cobrança muda de status, informe `metadata.notification_url` na criação
  ou depois, com `update_metadata/4`, e trate o aviso com `Efi.Charges.Notification`.

  ## Pegadinhas

    * `cancel/3` só vale para status `new`, `waiting`, `unpaid` ou `link`. Um boleto impresso
      antes do cancelamento ainda pode ser pago, e a cobrança volta a `paid`;
    * `settle/3` (baixa manual) só vale para `waiting` ou `unpaid`, não movimenta dinheiro na
      conta Efí e não serve para cobrança de link de pagamento;
    * a nova data de `update_billet_due_date/4` precisa ser posterior a hoje;
    * o corpo de `set_balance_sheet/4` tem no máximo 300 KB, e a Efí não confere os valores do
      balancete;
    * `list/3` está em beta na Efí e exige `charge_type`, `begin_date` e `end_date`;
    * cada rota aceita 15.000 requisições por dia por aplicação.

  ## Split de pagamento

  O split (marketplace) não tem rota própria: é o campo `marketplace` de cada item em
  `create/3` ou `create_one_step/3`. Cada repasse leva o `payee_code` (identificador de conta)
  de outra conta Efí e uma `percentage` em centésimos de ponto percentual (`2500` é 25%) ou um
  valor `fixed` em centavos. O que sobra fica com a conta que emitiu a cobrança.

      %{
        "items" => [
          %{
            "name" => "Pacote de unhas",
            "value" => 10_000,
            "amount" => 1,
            "marketplace" => %{
              "mode" => 2,
              "repasses" => [%{"payee_code" => "payee-code-do-parceiro", "percentage" => 2500}]
            }
          }
        ]
      }

  `mode` 1 desconta a tarifa da Efí só da conta emissora; `mode` 2, o padrão, desconta de cada
  conta na proporção do repasse. Repasse `fixed` exige `mode` 1. Repasses que somam mais de 100%
  (ou mais que o valor do item) recusam a cobrança, um repasse não pode ser zero e a mesma conta
  não recebe dois repasses no mesmo item. O frete não pode ser repartido, e o estorno de cartão
  não vale para venda com split.
  """

  alias Efi.Client

  @typedoc "Identificador da transação na Efí (`charge_id`)."
  @type charge_id :: pos_integer() | String.t()

  @doc """
  Cria uma transação com status `new`, sem forma de pagamento. O passo seguinte é
  `set_payment_method/4` ou `Efi.Charges.PaymentLink.create/4`.

  `POST /v1/charge`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#1-criar-transação).
  O mesmo passo aparece nas páginas de cartão, link de pagamento e split de pagamento.
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(client, :charges, :post, "/v1/charge", Keyword.put(opts, :json, body))
  end

  @doc """
  Cria uma transação já com a forma de pagamento: boleto (`payment.banking_billet`) ou cartão
  (`payment.credit_card`).

  `POST /v1/charge/one-step`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#criação-de-boleto-bolix-em-one-step-um-passo).
  Para cartão, veja também a [página de cartão](https://dev.efipay.com.br/docs/api-cobrancas/cartao#criação-de-cobrança-por-cartão-de-crédito-em-one-step-um-passo).
  """
  @spec create_one_step(Client.t(), map(), keyword()) :: Efi.result()
  def create_one_step(%Client{} = client, body, opts \\ []) do
    Client.request(client, :charges, :post, "/v1/charge/one-step", Keyword.put(opts, :json, body))
  end

  @doc """
  Define a forma de pagamento de uma transação `new`: boleto em `payment.banking_billet` ou
  cartão em `payment.credit_card`.

  `POST /v1/charge/:id/pay`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#2-associar-à-forma-de-pagamento-via-boleto).
  Para cartão, veja também a [página de cartão](https://dev.efipay.com.br/docs/api-cobrancas/cartao#2-associar-à-forma-de-pagamento-via-cartão).
  """
  @spec set_payment_method(Client.t(), charge_id(), map(), keyword()) :: Efi.result()
  def set_payment_method(%Client{} = client, charge_id, payment, opts \\ []) do
    path = Client.path("/v1/charge/:id/pay", id: charge_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, payment))
  end

  @doc """
  Consulta uma transação: status, itens, cliente, forma de pagamento e histórico.

  `GET /v1/charge/:id`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#retornar-informações-de-cobrança-existente)
  """
  @spec get(Client.t(), charge_id(), keyword()) :: Efi.result()
  def get(%Client{} = client, charge_id, opts \\ []) do
    Client.request(client, :charges, :get, Client.path("/v1/charge/:id", id: charge_id), opts)
  end

  @doc """
  Lista as transações da aplicação. `charge_type`, `begin_date` e `end_date` são obrigatórios;
  os filtros opcionais são `customer_document`, `status`, `custom_id`, `value`, `date_of`,
  `limit`, `page` e `offset`.

  `GET /v1/charges`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#retornar-lista-de-cobranças).
  A mesma rota lista carnês e cobranças de assinatura.
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :charges, :get, "/v1/charges", Keyword.put(opts, :params, params))
  end

  @doc """
  Define ou troca a `notification_url` e o `custom_id` de uma transação já criada, por exemplo
  depois de mudar o domínio que recebe as notificações.

  `PUT /v1/charge/:id/metadata`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#incluir-notification_url-e-custom_id-em-uma-transação-existente)
  """
  @spec update_metadata(Client.t(), charge_id(), map(), keyword()) :: Efi.result()
  def update_metadata(%Client{} = client, charge_id, metadata, opts \\ []) do
    path = Client.path("/v1/charge/:id/metadata", id: charge_id)
    Client.request(client, :charges, :put, path, Keyword.put(opts, :json, metadata))
  end

  @doc """
  Muda o vencimento de um boleto ainda não pago: `%{"expire_at" => "2026-12-30"}`.

  `PUT /v1/charge/:id/billet`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#alterar-data-de-vencimento-de-uma-transação-existente)
  """
  @spec update_billet_due_date(Client.t(), charge_id(), map(), keyword()) :: Efi.result()
  def update_billet_due_date(%Client{} = client, charge_id, body, opts \\ []) do
    path = Client.path("/v1/charge/:id/billet", id: charge_id)
    Client.request(client, :charges, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Cancela uma transação com status `new`, `waiting`, `unpaid` ou `link`.

  `PUT /v1/charge/:id/cancel`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#cancelar-uma-transação-existente).
  É também como se cancela um [link de pagamento](https://dev.efipay.com.br/docs/api-cobrancas/link-de-pagamento#cancelar-um-link-de-pagamento-existente).
  """
  @spec cancel(Client.t(), charge_id(), keyword()) :: Efi.result()
  def cancel(%Client{} = client, charge_id, opts \\ []) do
    path = Client.path("/v1/charge/:id/cancel", id: charge_id)
    Client.request(client, :charges, :put, path, opts)
  end

  @doc """
  Reenvia o boleto de uma transação `waiting` ou `unpaid` para o e-mail informado:
  `%{"email" => "cliente@app.example.com"}`.

  `POST /v1/charge/:id/billet/resend`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#reenvio-do-boleto-bancário-para-o-email-desejado)
  """
  @spec resend_billet(Client.t(), charge_id(), map(), keyword()) :: Efi.result()
  def resend_billet(%Client{} = client, charge_id, body, opts \\ []) do
    path = Client.path("/v1/charge/:id/billet/resend", id: charge_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Acrescenta uma mensagem própria ao histórico da transação, de 1 a 255 caracteres:
  `%{"description" => "Pago em dinheiro no balcão"}`. A mensagem não muda a transação.

  `POST /v1/charge/:id/history`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#acrescentar-descrição-ao-histórico-de-uma-transação)
  """
  @spec add_history(Client.t(), charge_id(), map(), keyword()) :: Efi.result()
  def add_history(%Client{} = client, charge_id, body, opts \\ []) do
    path = Client.path("/v1/charge/:id/history", id: charge_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Faz o boleto da transação sair como balancete: um demonstrativo em tabela, com até 4 colunas,
  montado a partir de `title` e `body`. Chame depois de `create/3` e antes de definir o boleto.

  `POST /v1/charge/:id/balance-sheet`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#definir-que-a-transação-será-do-tipo-boleto-balancete)
  """
  @spec set_balance_sheet(Client.t(), charge_id(), map(), keyword()) :: Efi.result()
  def set_balance_sheet(%Client{} = client, charge_id, balance_sheet, opts \\ []) do
    path = Client.path("/v1/charge/:id/balance-sheet", id: charge_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, balance_sheet))
  end

  @doc """
  Marca como paga (baixa manual) uma transação `waiting` ou `unpaid` que o cliente pagou por
  fora, em dinheiro ou depósito. O status passa a `settled`.

  `PUT /v1/charge/:id/settle`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/boleto#marcar-como-pago-determinada-transação)
  """
  @spec settle(Client.t(), charge_id(), keyword()) :: Efi.result()
  def settle(%Client{} = client, charge_id, opts \\ []) do
    path = Client.path("/v1/charge/:id/settle", id: charge_id)
    Client.request(client, :charges, :put, path, opts)
  end
end
