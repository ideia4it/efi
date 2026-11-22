defmodule Efi.Pix.Webhook do
  @moduledoc """
  Webhook Pix por chave: a URL que a Efí chama quando um Pix ligado à chave é recebido, enviado
  ou devolvido.

  Uma URL pode atender várias chaves, mas cada chave aponta para uma URL só: configurar de novo
  troca a anterior. Pix de QR Code estático só é notificado quando tem `txid`. Os webhooks de Pix
  Automático (`webhookrec` e `webhookcobr`) não são configurados aqui.

      {:ok, _webhook} =
        Efi.Pix.Webhook.configure(client, "chave-pix-do-studio-ana", %{
          "webhookUrl" => "https://app.example.com/webhooks/efi?ignorar="
        })

  ## O `/pix` no fim da URL

  Ao configurar, a Efí manda uma notificação de teste para a URL exatamente como foi cadastrada.
  As notificações de verdade vão para a URL com `/pix` acrescentado ao fim: quem cadastra
  `https://app.example.com/webhooks/efi` recebe em `https://app.example.com/webhooks/efi/pix`.
  Para atender as duas numa rota só, a Efí orienta terminar a URL com o parâmetro `ignorar=`
  vazio (`?ignorar=`, ou `&ignorar=` se a URL já tem query): o `/pix` vira o valor desse
  parâmetro e o caminho não muda
  ([documentação](https://dev.efipay.com.br/docs/api-pix/webhooks#configurar-o-webhook-pix)).

  ## mTLS

  Por norma do Banco Central, a Efí se autentica no servidor do webhook com certificado (mTLS,
  TLS 1.2 ou superior). Ao configurar, ela faz duas requisições: uma sem certificado, que o
  servidor precisa recusar, e outra com o certificado, que precisa completar o handshake. Para
  isso o servidor confia na cadeia pública da Efí do ambiente
  ([documentação](https://dev.efipay.com.br/docs/api-pix/webhooks#entendendo-o-padrão-mtls)):

    * produção: `https://certificados.efipay.com.br/webhooks/certificate-chain-prod.crt`;
    * homologação: `https://certificados.efipay.com.br/webhooks/certificate-chain-homolog.crt`.

  Quando a verificação falha, `configure/4` volta
  `%Efi.Error{kind: :validation, name: "webhook_invalido"}` com a mensagem da Efí, como "A
  autenticação de TLS mútuo não está configurada na URL informada".

  ## Atrás de um proxy que encerra o TLS

  Quando o TLS termina num proxy da plataforma, como no Fly.io, no Heroku e no Render na
  configuração padrão, o app nunca vê o certificado da Efí, e sem mTLS o cadastro falha. Nesse
  caso, configure com `skip_mtls_checking: true`, que envia o header `x-skip-mtls-checking: true`
  e faz a Efí aceitar a URL sem testar o mTLS. A documentação da Efí não descreve esse header,
  mas a Efí o aceita no cadastro e os SDKs oficiais o oferecem (no de Node, a opção
  `skipMtlsChecking`):

      Efi.Pix.Webhook.configure(
        client,
        "chave-pix-do-studio-ana",
        %{"webhookUrl" => "https://app.example.com/webhooks/efi?hmac=segredo-do-studio-ana&ignorar="},
        skip_mtls_checking: true
      )

  Sem mTLS, qualquer um que descubra a URL consegue chamá-la. A Efí recomenda duas camadas, de
  preferência juntas:

    * um segredo próprio na query, como o `hmac` acima, que o app compara em tempo constante
      antes de processar a notificação
      ([documentação](https://dev.efipay.com.br/docs/api-pix/webhooks#utilizando-hmac-na-url-do-webhook)).
      O segredo viaja na URL, então tire-o dos logs e do rastreador de erros;
    * aceitar só o IP de onde a Efí envia as notificações, hoje `34.193.116.226`
      ([documentação](https://dev.efipay.com.br/docs/api-pix/webhooks#validação-por-ip)).

  E trate a notificação como aviso: confira o pagamento com `Efi.Pix.Received.get/3` antes de dar
  baixa.

  ## Entrega e reenvio

  Cada notificação é um `POST` com JSON. Os Pix recebidos, enviados e devolvidos chegam em
  `"pix"`. Um recebimento que a Efí recusou por segurança chega em `"info"`, com `status`
  `RECEBIMENTO_RECUSADO` e sem `endToEndId`: o valor não entrou na conta
  ([documentação](https://dev.efipay.com.br/docs/api-pix/webhooks#requisição)).

  A Efí espera resposta 2xx em até 60 segundos. Sem ela, tenta de novo em intervalos crescentes,
  de 5 a 160 minutos, até a nona tentativa. Depois disso, `resend/3` pede um novo envio, com
  estas regras da Efí:

    * só para transações dos últimos 30 dias, de 1 a 1000 `e2eids` por chamada;
    * uma tentativa por webhook, sem reagendamento: se o servidor estiver fora, peça de novo;
    * as devoluções de um mesmo `e2eId` voltam num webhook só, com o array inteiro;
    * não vale para o Pix Automático, e em homologação a Efí recusa o pedido.
  """

  alias Efi.Client

  @doc """
  Configura a URL do webhook de uma chave Pix, trocando a anterior se houver. Para servidores
  atrás de um proxy que encerra o TLS, passe `skip_mtls_checking: true` (veja o módulo).

  `PUT /v2/webhook/:chave` · escopo `webhook.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#configurar-o-webhook-pix)
  """
  @spec configure(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def configure(%Client{} = client, key, body, opts \\ []) do
    path = Client.path("/v2/webhook/:chave", chave: key)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Consulta o webhook configurado para uma chave Pix.

  `GET /v2/webhook/:chave` · escopo `webhook.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#exibir-informações-do-webhook-pix)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, key, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/webhook/:chave", chave: key), opts)
  end

  @doc """
  Lista os webhooks configurados entre `inicio` e `fim` (RFC 3339, obrigatórios).

  `GET /v2/webhook` · escopo `webhook.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#consultar-lista-de-webhooks)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/webhook", Keyword.put(opts, :params, params))
  end

  @doc """
  Cancela o webhook de uma chave Pix. Responde sem corpo (`{:ok, nil}`).

  `DELETE /v2/webhook/:chave` · escopo `webhook.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#cancelar-o-webhook-pix)
  """
  @spec delete(Client.t(), String.t(), keyword()) :: Efi.result()
  def delete(%Client{} = client, key, opts \\ []) do
    Client.request(client, :pix, :delete, Client.path("/v2/webhook/:chave", chave: key), opts)
  end

  @doc """
  Pede o reenvio dos webhooks de até 1000 transações de um `tipo`: `PIX_RECEBIDO`,
  `PIX_ENVIADO`, `DEVOLUCAO_RECEBIDA` ou `DEVOLUCAO_ENVIADA`.

  `POST /v2/gn/webhook/reenviar` · escopo `webhook.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#reenviar-webhook-pix)
  """
  @spec resend(Client.t(), map(), keyword()) :: Efi.result()
  def resend(%Client{} = client, body, opts \\ []) do
    Client.request(client, :pix, :post, "/v2/gn/webhook/reenviar", Keyword.put(opts, :json, body))
  end
end
