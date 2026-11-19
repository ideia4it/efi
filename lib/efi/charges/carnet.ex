defmodule Efi.Charges.Carnet do
  @moduledoc """
  Carnê: um lote de boletos (parcelas) que vencem todo mês, a partir do vencimento da primeira.

  O carnê tem o próprio `carnet_id`, e cada parcela é uma transação com `charge_id` e número
  (`parcel`, a partir de 1). As funções de parcela recebem o `carnet_id` e esse número.

      {:ok, %{"data" => %{"carnet_id" => carnet_id, "charges" => parcels}}} =
        Efi.Charges.Carnet.create(client, %{
          "items" => [%{"name" => "Pacote mensal de manicure", "value" => 15_000, "amount" => 1}],
          "customer" => %{"name" => "Cliente do Studio Ana", "cpf" => "12345678909"},
          "expire_at" => "2026-12-10",
          "repeats" => 6,
          "split_items" => false,
          "metadata" => %{"notification_url" => "https://app.example.com/efi/notificacoes"}
        })

  `repeats` é o número de parcelas, `expire_at` o vencimento da primeira e `message` aceita até
  80 caracteres. O carnê nasce `up_to_date`, vai a `unpaid` quando alguma parcela fica
  inadimplente e a `finished` quando todas chegam a um status final.

  ## Pegadinhas

    * só parcelas `waiting` ou `unpaid` mudam de vencimento, e a data nova não pode ser
      anterior a hoje nem antecipar o vencimento;
    * a baixa manual (`settle/3`, `settle_parcel/4`) só vale para `waiting` ou `unpaid` e não
      movimenta dinheiro na conta Efí;
    * a listagem de carnês é `Efi.Charges.Charge.list/3`, filtrando por `charge_type`;
    * cada rota aceita 15.000 requisições por dia por aplicação.
  """

  alias Efi.Client

  @typedoc "Identificador do carnê na Efí (`carnet_id`)."
  @type carnet_id :: pos_integer() | String.t()

  @typedoc "Número da parcela no carnê, a partir de 1."
  @type parcel :: pos_integer() | String.t()

  @doc """
  Cria um carnê com as parcelas já emitidas.

  `POST /v1/carnet`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#criando-carnês)
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(client, :charges, :post, "/v1/carnet", Keyword.put(opts, :json, body))
  end

  @doc """
  Consulta um carnê e as suas parcelas.

  `GET /v1/carnet/:id`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#retornar-informações-de-carnê-existente)
  """
  @spec get(Client.t(), carnet_id(), keyword()) :: Efi.result()
  def get(%Client{} = client, carnet_id, opts \\ []) do
    Client.request(client, :charges, :get, Client.path("/v1/carnet/:id", id: carnet_id), opts)
  end

  @doc """
  Define ou troca a `notification_url` e o `custom_id` de um carnê.

  `PUT /v1/carnet/:id/metadata`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#incluir-notification_url-e-custom_id-de-carnês)
  """
  @spec update_metadata(Client.t(), carnet_id(), map(), keyword()) :: Efi.result()
  def update_metadata(%Client{} = client, carnet_id, metadata, opts \\ []) do
    path = Client.path("/v1/carnet/:id/metadata", id: carnet_id)
    Client.request(client, :charges, :put, path, Keyword.put(opts, :json, metadata))
  end

  @doc """
  Muda o vencimento de uma parcela: `%{"expire_at" => "2027-01-10"}`.

  `PUT /v1/carnet/:id/parcel/:parcel`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#alterar-vencimento-de-parcela-específica-do-carnê)
  """
  @spec update_parcel_due_date(Client.t(), carnet_id(), parcel(), map(), keyword()) ::
          Efi.result()
  def update_parcel_due_date(%Client{} = client, carnet_id, parcel, body, opts \\ []) do
    path = Client.path("/v1/carnet/:id/parcel/:parcel", id: carnet_id, parcel: parcel)
    Client.request(client, :charges, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Muda o vencimento de várias parcelas de uma vez:
  `%{"parcels" => [%{"parcel" => 2, "expire_at" => "2027-02-10"}]}`.

  `PUT /v1/carnet/:id/parcels`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#alterar-vencimento-de-parcelas-de-um-carnê)
  """
  @spec update_parcels_due_dates(Client.t(), carnet_id(), map(), keyword()) :: Efi.result()
  def update_parcels_due_dates(%Client{} = client, carnet_id, body, opts \\ []) do
    path = Client.path("/v1/carnet/:id/parcels", id: carnet_id)
    Client.request(client, :charges, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Cancela o carnê inteiro.

  `PUT /v1/carnet/:id/cancel`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#cancelar-um-carnê)
  """
  @spec cancel(Client.t(), carnet_id(), keyword()) :: Efi.result()
  def cancel(%Client{} = client, carnet_id, opts \\ []) do
    path = Client.path("/v1/carnet/:id/cancel", id: carnet_id)
    Client.request(client, :charges, :put, path, opts)
  end

  @doc """
  Cancela uma parcela do carnê.

  `PUT /v1/carnet/:id/parcel/:parcel/cancel`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#cancelar-parcela-específica-de-carnê)
  """
  @spec cancel_parcel(Client.t(), carnet_id(), parcel(), keyword()) :: Efi.result()
  def cancel_parcel(%Client{} = client, carnet_id, parcel, opts \\ []) do
    path = Client.path("/v1/carnet/:id/parcel/:parcel/cancel", id: carnet_id, parcel: parcel)
    Client.request(client, :charges, :put, path, opts)
  end

  @doc """
  Reenvia o carnê para o e-mail informado: `%{"email" => "cliente@app.example.com"}`.

  `POST /v1/carnet/:id/resend`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#reenvio-do-carnê-para-o-email-desejado)
  """
  @spec resend(Client.t(), carnet_id(), map(), keyword()) :: Efi.result()
  def resend(%Client{} = client, carnet_id, body, opts \\ []) do
    path = Client.path("/v1/carnet/:id/resend", id: carnet_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Reenvia uma parcela `waiting` para o e-mail informado.

  `POST /v1/carnet/:id/parcel/:parcel/resend`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#reenvio-de-uma-parcela-específica-de-carnê-por-e-mail)
  """
  @spec resend_parcel(Client.t(), carnet_id(), parcel(), map(), keyword()) :: Efi.result()
  def resend_parcel(%Client{} = client, carnet_id, parcel, body, opts \\ []) do
    path = Client.path("/v1/carnet/:id/parcel/:parcel/resend", id: carnet_id, parcel: parcel)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Acrescenta uma mensagem própria ao histórico do carnê, sem mudar o carnê:
  `%{"description" => "Cliente pediu o carnê impresso"}`.

  `POST /v1/carnet/:id/history`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#acrescentar-descrição-ao-histórico-de-uma-transação)
  """
  @spec add_history(Client.t(), carnet_id(), map(), keyword()) :: Efi.result()
  def add_history(%Client{} = client, carnet_id, body, opts \\ []) do
    path = Client.path("/v1/carnet/:id/history", id: carnet_id)
    Client.request(client, :charges, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Marca como pago (baixa manual) o carnê inteiro, pago por fora da Efí.

  `PUT /v1/carnet/:id/settle`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#marcar-como-pago-baixa-manual-um-determinado-carnê)
  """
  @spec settle(Client.t(), carnet_id(), keyword()) :: Efi.result()
  def settle(%Client{} = client, carnet_id, opts \\ []) do
    path = Client.path("/v1/carnet/:id/settle", id: carnet_id)
    Client.request(client, :charges, :put, path, opts)
  end

  @doc """
  Marca como paga (baixa manual) uma parcela do carnê, paga por fora da Efí.

  `PUT /v1/carnet/:id/parcel/:parcel/settle`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/carne#marcar-como-pago-determinada-parcela-de-carnê)
  """
  @spec settle_parcel(Client.t(), carnet_id(), parcel(), keyword()) :: Efi.result()
  def settle_parcel(%Client{} = client, carnet_id, parcel, opts \\ []) do
    path = Client.path("/v1/carnet/:id/parcel/:parcel/settle", id: carnet_id, parcel: parcel)
    Client.request(client, :charges, :put, path, opts)
  end
end
