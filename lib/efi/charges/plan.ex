defmodule Efi.Charges.Plan do
  @moduledoc """
  Plano de assinatura: o molde das cobranças recorrentes. Define o nome, de quantos em quantos
  meses se cobra (`interval`) e quantas cobranças gerar (`repeats`; `nil` cobra até alguém
  cancelar). As assinaturas de cada cliente ficam em `Efi.Charges.Subscription`.

      {:ok, %{"data" => %{"plan_id" => plan_id}}} =
        Efi.Charges.Plan.create(client, %{
          "name" => "Clube de escova mensal",
          "interval" => 1,
          "repeats" => 12
        })

  As cobranças seguintes caem no mesmo dia do mês da primeira. Se a primeira cair no último dia
  do mês, as seguintes caem sempre no último dia; se o dia não existir no mês (29 a 31), a
  cobrança daquele mês cai no último dia dele.

  Depois de criado, o plano só muda de nome.
  """

  alias Efi.Client

  @typedoc "Identificador do plano na Efí (`plan_id`)."
  @type plan_id :: pos_integer() | String.t()

  @doc """
  Cria um plano de assinatura.

  `POST /v1/plan`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#crie-o-plano-de-assinatura)
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(client, :charges, :post, "/v1/plan", Keyword.put(opts, :json, body))
  end

  @doc """
  Lista os planos. Filtros opcionais em `params`: `name`, `limit` e `offset`.

  `GET /v1/plans`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#retornar-informações-de-um-plano)
  """
  @spec list(Client.t(), keyword()) :: Efi.result()
  def list(%Client{} = client, opts \\ []) do
    Client.request(client, :charges, :get, "/v1/plans", opts)
  end

  @doc """
  Muda o nome de um plano: `%{"name" => "Clube de escova"}`.

  `PUT /v1/plan/:id`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#permitir-a-edição-do-nome-do-plano-de-assinatura)
  """
  @spec update(Client.t(), plan_id(), map(), keyword()) :: Efi.result()
  def update(%Client{} = client, plan_id, changes, opts \\ []) do
    path = Client.path("/v1/plan/:id", id: plan_id)
    Client.request(client, :charges, :put, path, Keyword.put(opts, :json, changes))
  end

  @doc """
  Cancela um plano de assinatura.

  `DELETE /v1/plan/:id`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/assinatura#cancelar-um-plano-de-assinatura)
  """
  @spec delete(Client.t(), plan_id(), keyword()) :: Efi.result()
  def delete(%Client{} = client, plan_id, opts \\ []) do
    Client.request(client, :charges, :delete, Client.path("/v1/plan/:id", id: plan_id), opts)
  end
end
