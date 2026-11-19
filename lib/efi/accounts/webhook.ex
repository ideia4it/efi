defmodule Efi.Accounts.Webhook do
  @moduledoc """
  Webhook da Abertura de Contas: a URL que a Efí chama quando o cliente final aprova ou recusa
  a conta pedida em `Efi.Accounts.SimplifiedAccount.create/3`.

  Cadastre antes da primeira abertura: sem webhook, a Efí recusa o pedido de conta com status
  412 e `name: "webhook_nao_cadastrado"`.

      {:ok, %{"identificadorWebhook" => webhook_id}} =
        Efi.Accounts.Webhook.configure(client, %{
          "webhookUrl" => "https://app.example.com/efi/contas"
        })

  A URL precisa de HTTPS, TLS 1.2 ou mais novo e mTLS com a cadeia pública da Efí
  (`https://certificados.efipay.com.br/webhooks/certificate-chain-prod.crt` em produção,
  `https://certificados.efipay.com.br/webhooks/certificate-chain-homolog.crt` em homologação).
  No cadastro, a Efí chama a URL uma vez sem certificado, chamada que o servidor deve recusar,
  e outra com o certificado. Se a verificação falha, o erro volta com status 400 e um `name`
  como `"mtls_nao_configurado"`, `"url_inacessivel"` ou `"url_cadastrada"`.

  ## A notificação

  A Efí faz um `POST` na URL com:

      %{"contaSimplificada" => %{"identificador" => "..."}, "evento" => "conta_aberta"}

  `evento` é `"conta_aberta"` ou `"conta_recusada_pelo_cliente_final"`. A Efí espera um 2xx em
  até 60 segundos. Sem isso, tenta de novo até 10 vezes: a primeira 5 minutos depois e as
  seguintes em intervalos cada vez maiores.

  Um identificador que não existe volta com status 400 e `name: "identificador_webhook"`, não
  com 404.
  """

  alias Efi.Client

  @doc """
  Cadastra a URL do webhook e devolve o `identificadorWebhook`.

  Para trocar a URL de um webhook cadastrado, a tabela de atributos da Efí pede `webhookUrl`
  com o `identificadorWebhook`, enquanto o exemplo de edição da mesma página usa `url` e
  `chave`. O mapa vai como está, então siga o formato que a Efí aceitar.

  `POST /v1/webhook` · escopo `gn.registration.webhook.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-abertura-de-contas/webhook#configurar-o-webhook)
  """
  @spec configure(Client.t(), map(), keyword()) :: Efi.result()
  def configure(%Client{} = client, body, opts \\ []) do
    Client.request(client, :accounts, :post, "/v1/webhook", Keyword.put(opts, :json, body))
  end

  @doc """
  Consulta um webhook pelo `identificadorWebhook`: a URL e a data de criação.

  `GET /v1/webhook/:identificadorWebhook` · escopo `gn.registration.webhook.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-abertura-de-contas/webhook#detalhar-webhook)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, webhook_id, opts \\ []) do
    Client.request(client, :accounts, :get, webhook_path(webhook_id), opts)
  end

  @doc """
  Lista os webhooks criados entre `inicio` e `fim` (data e hora em RFC 3339, obrigatórios).
  Filtros opcionais: `paginacao.paginaAtual` e `paginacao.itensPorPagina` (até 1000).

  `GET /v1/webhooks` · escopo `gn.registration.webhook.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-abertura-de-contas/webhook#listar-webhooks)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :accounts, :get, "/v1/webhooks", Keyword.put(opts, :params, params))
  end

  @doc """
  Cancela um webhook. A resposta não tem corpo e volta como `{:ok, nil}`.

  `DELETE /v1/webhook/:identificadorWebhook` · escopo `gn.registration.webhook.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-abertura-de-contas/webhook#cancelar-webhook)
  """
  @spec delete(Client.t(), String.t(), keyword()) :: Efi.result()
  def delete(%Client{} = client, webhook_id, opts \\ []) do
    Client.request(client, :accounts, :delete, webhook_path(webhook_id), opts)
  end

  defp webhook_path(webhook_id),
    do: Client.path("/v1/webhook/:identificadorWebhook", identificadorWebhook: webhook_id)
end
