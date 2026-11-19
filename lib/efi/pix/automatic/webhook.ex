defmodule Efi.Pix.Automatic.Webhook do
  @moduledoc """
  Webhooks do Pix Automático: um avisa as mudanças de status das recorrências (`webhookrec`) e
  outro as das cobranças de Pix Automático (`webhookcobr`). Nenhum dos dois leva chave Pix no
  caminho, e nenhum depende do webhook Pix comum, que é cadastrado por chave. O fluxo completo
  está em `Efi.Pix.Automatic.Recurrence`.

      {:ok, _} =
        Efi.Pix.Automatic.Webhook.configure_recurrence(client, %{
          "webhookUrl" => "https://app.example.com/webhooks/efi?ignorar="
        })

  O cadastro segue as mesmas regras do webhook Pix comum, explicadas em `Efi.Pix.Webhook`.
  Pegadinhas que a Efí descreve:

    * a Efí envia uma notificação de teste ao cadastrar. Nas notificações de verdade, acrescenta
      `/rec` (recorrência) ou `/cobr` (cobrança) ao fim da URL. Termine a URL com `?ignorar=`
      para receber tudo na mesma rota;
    * o servidor do webhook precisa exigir o certificado da Efí (mTLS, TLS 1.2 ou maior). Atrás
      de um proxy que encerra o TLS, passe `skip_mtls_checking: true` e proteja a URL de outra
      forma, como um HMAC na query (`?hmac=...&ignorar=`) e a conferência do IP de origem;
    * as notificações chegam por `POST` com `{"recs": [...]}` ou `{"cobsr": [...]}`. Sem
      resposta 2xx, a Efí tenta de novo em intervalos que crescem de 5 a 160 minutos, até a
      nona tentativa;
    * o reenvio manual de webhooks da API Pix não vale para o Pix Automático.
  """

  alias Efi.Client

  @doc """
  Cadastra ou troca a URL do webhook de recorrências. Só são notificadas as recorrências
  associadas à chave e à conta.

  `PUT /v2/webhookrec` · escopo `webhookrec.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#configurar-o-webhook-de-recorrência-de-pix-automático)
  """
  @spec configure_recurrence(Client.t(), map(), keyword()) :: Efi.result()
  def configure_recurrence(%Client{} = client, body, opts \\ []) do
    Client.request(client, :pix, :put, "/v2/webhookrec", Keyword.put(opts, :json, body))
  end

  @doc """
  Consulta o webhook de recorrências: a `webhookUrl` e a data de `criacao`.

  `GET /v2/webhookrec` · escopo `webhookrec.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#exibir-informações-do-webhook-de-recorrência-de-pix-automático)
  """
  @spec get_recurrence(Client.t(), keyword()) :: Efi.result()
  def get_recurrence(%Client{} = client, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/webhookrec", opts)
  end

  @doc """
  Cancela o webhook de recorrências. Devolve `{:ok, nil}`.

  `DELETE /v2/webhookrec` · escopo `webhookrec.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#cancelar-o-webhook-de-recorrência-de-pix-automático)
  """
  @spec delete_recurrence(Client.t(), keyword()) :: Efi.result()
  def delete_recurrence(%Client{} = client, opts \\ []) do
    Client.request(client, :pix, :delete, "/v2/webhookrec", opts)
  end

  @doc """
  Cadastra ou troca a URL do webhook de cobranças de Pix Automático. Só são notificadas as
  cobranças do recebedor.

  `PUT /v2/webhookcobr` · escopo `webhookcobr.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#configurar-o-webhook-de-cobrança-de-pix-automático)
  """
  @spec configure_charge(Client.t(), map(), keyword()) :: Efi.result()
  def configure_charge(%Client{} = client, body, opts \\ []) do
    Client.request(client, :pix, :put, "/v2/webhookcobr", Keyword.put(opts, :json, body))
  end

  @doc """
  Consulta o webhook de cobranças de Pix Automático: a `webhookUrl` e a data de `criacao`.

  `GET /v2/webhookcobr` · escopo `webhookcobr.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#exibir-informações-do-webhook-de-cobrança-de-pix-automático)
  """
  @spec get_charge(Client.t(), keyword()) :: Efi.result()
  def get_charge(%Client{} = client, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/webhookcobr", opts)
  end

  @doc """
  Cancela o webhook de cobranças de Pix Automático. Devolve `{:ok, nil}`.

  `DELETE /v2/webhookcobr` · escopo `webhookcobr.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/webhooks#cancelar-o-webhook-de-cobrança-de-pix-automático)
  """
  @spec delete_charge(Client.t(), keyword()) :: Efi.result()
  def delete_charge(%Client{} = client, opts \\ []) do
    Client.request(client, :pix, :delete, "/v2/webhookcobr", opts)
  end
end
