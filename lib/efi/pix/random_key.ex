defmodule Efi.Pix.RandomKey do
  @moduledoc """
  Chaves Pix aleatórias (EVP) da conta: o UUID que o DICT gera e que serve para receber Pix sem
  expor CPF, CNPJ, telefone ou e-mail. É a chave que vai no campo `"chave"` das cobranças e no
  cadastro do webhook.

      {:ok, %{"chave" => key}} = Efi.Pix.RandomKey.create(client)

  Remover uma chave é definitivo: o DICT nunca gera o mesmo UUID de novo, e as cobranças
  criadas com ela deixam de poder ser pagas. A conta tem um limite de chaves; ao atingi-lo, a
  criação volta como `%Efi.Error{kind: :validation, name: "limite_criacao_chave_atingido"}`.
  """

  alias Efi.Client

  @doc """
  Cria uma chave aleatória. A requisição não tem corpo; a chave nova volta em `"chave"`.

  `POST /v2/gn/evp` · escopo `gn.pix.evp.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#criar-chave-pix-aleatória)
  """
  @spec create(Client.t(), keyword()) :: Efi.result()
  def create(%Client{} = client, opts \\ []) do
    Client.request(client, :pix, :post, "/v2/gn/evp", opts)
  end

  @doc """
  Lista as chaves aleatórias da conta, em `"chaves"`. Chaves de outros tipos não aparecem.

  `GET /v2/gn/evp` · escopo `gn.pix.evp.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#listar-chaves-pix-aleatórias)
  """
  @spec list(Client.t(), keyword()) :: Efi.result()
  def list(%Client{} = client, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/gn/evp", opts)
  end

  @doc """
  Remove uma chave aleatória, de forma definitiva.

  `DELETE /v2/gn/evp/:chave` · escopo `gn.pix.evp.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#remover-chave-pix-aleatória)
  """
  @spec delete(Client.t(), String.t(), keyword()) :: Efi.result()
  def delete(%Client{} = client, key, opts \\ []) do
    Client.request(client, :pix, :delete, Client.path("/v2/gn/evp/:chave", chave: key), opts)
  end
end
