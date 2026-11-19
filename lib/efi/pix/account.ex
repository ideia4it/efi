defmodule Efi.Pix.Account do
  @moduledoc """
  Saldo, configurações de recebimento Pix e baldes de fichas da conta Efí autenticada.

      {:ok, %{"saldo" => "100.00"}} = Efi.Pix.Account.get_balance(client)

      {:ok, nil} =
        Efi.Pix.Account.update_settings(client, %{
          "pix" => %{
            "receberSemChave" => false,
            "chaves" => %{
              "chave-pix-do-studio-ana" => %{
                "recebimento" => %{"documentoPagadorIgualDevedor" => true}
              }
            }
          }
        })

  ## Configurações

  `receberSemChave` vale para a conta: com `false`, a conta só recebe Pix por chave; com
  `true`, recebe também por dados bancários. O resto vale por chave, em `pix.chaves`:
  `txidObrigatorio`, `recusarTipoPessoa` (`"PF"` ou `"PJ"`), `qrCodeEstatico.recusarTodos` e o
  que vai nos webhooks de recebimento e de envio (tarifa, pagador, favorecido, Pix sem `txid`).

  Com `documentoPagadorIgualDevedor: true`, um pagamento de `cob` ou `cobv` nessa chave só
  entra se o CPF ou CNPJ de quem paga for o do `devedor` da cobrança; se não for, a cobrança
  continua `ATIVA`. Uma `cob` sem `devedor` é paga normalmente. Chave sem a configuração conta
  como `false`.

  ## Baldes de fichas

  O envio de Pix para uma chave consome fichas de um balde, que se reabastece com o tempo: o
  `baldeA` serve chaves CPF, CNPJ e aleatória; o `baldeB`, telefone e e-mail. Com o balde
  vazio, `Efi.Pix.Send.send/4` volta como `%Efi.Error{kind: :rate_limited}`.
  """

  alias Efi.Client

  @doc """
  Consulta o saldo da conta. Com `params: %{"bloqueios" => true}`, a resposta traz também os
  valores bloqueados por MED e por ordem judicial.

  `GET /v2/gn/saldo` · escopo `gn.balance.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#buscar-o-saldo-da-conta)
  """
  @spec get_balance(Client.t(), keyword()) :: Efi.result()
  def get_balance(%Client{} = client, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/gn/saldo", opts)
  end

  @doc """
  Cria ou altera as configurações Pix da conta e das chaves. A Efí responde 204, que volta
  como `{:ok, nil}`.

  `PUT /v2/gn/config` · escopo `gn.settings.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#criarmodificar-configurações-da-conta)
  """
  @spec update_settings(Client.t(), map(), keyword()) :: Efi.result()
  def update_settings(%Client{} = client, settings, opts \\ []) do
    Client.request(client, :pix, :put, "/v2/gn/config", Keyword.put(opts, :json, settings))
  end

  @doc """
  Lê as configurações Pix da conta e das chaves.

  `GET /v2/gn/config` · escopo `gn.settings.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#listar-configurações-da-conta)
  """
  @spec get_settings(Client.t(), keyword()) :: Efi.result()
  def get_settings(%Client{} = client, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/gn/config", opts)
  end

  @doc """
  Consulta a capacidade, as fichas disponíveis e a reposição de cada balde de fichas.

  `GET /v2/gn/chaves/balde` · escopo `gn.keys.bucket.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#consultar-baldes-de-fichas)
  """
  @spec get_key_buckets(Client.t(), keyword()) :: Efi.result()
  def get_key_buckets(%Client{} = client, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/gn/chaves/balde", opts)
  end
end
