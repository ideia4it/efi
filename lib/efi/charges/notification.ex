defmodule Efi.Charges.Notification do
  @moduledoc """
  Notificações da API Cobranças: como o app fica sabendo que uma transação, um carnê ou uma
  assinatura mudou de status.

  ## O fluxo

  1. Na criação (ou depois, pelo `update_metadata` do recurso) o app informa uma
     `notification_url`.
  2. A cada mudança de status, a Efí faz um `POST` nessa URL com um único campo de formulário,
     `notification=<token>`. O token é o mesmo durante toda a vida da cobrança.
  3. O app consulta `get/3` com o token e recebe, em `data`, a lista das mudanças dos últimos
     6 meses, em ordem.

  O `POST` não traz dado nenhum da cobrança, então não há assinatura a conferir: quem garante
  que a notificação é verdadeira é a consulta autenticada à Efí. A Efí só considera a
  notificação entregue depois dessa consulta e, sem ela, continua reenviando por até 3 dias. Se
  a URL não responder 2xx, a Efí tenta de novo até 10 vezes, em intervalos crescentes a partir
  de 5 minutos.

      def create(conn, %{"notification" => token}) do
        {:ok, %{"data" => changes}} = Efi.Charges.Notification.get(client, token)

        for %{"id" => change_id, "identifiers" => identifiers, "status" => status} <- changes do
          MyApp.Billing.apply_change(change_id, identifiers, status["current"])
        end

        send_resp(conn, 200, "")
      end

  Cada mudança tem um `id` crescente, o `type` (`charge`, `carnet`, `carnet_charge`,
  `subscription`, `subscription_charge`), os `identifiers` (`charge_id`, `carnet_id`,
  `subscription_id`) e o `status` com `current` e `previous`. Uma confirmação de pagamento traz
  também `value` e `received_by_bank_at`. Uma consulta pode trazer várias mudanças de uma vez:
  guarde o último `id` processado em vez de olhar só a última posição da lista.

  A rota aceita 30.000 requisições por dia por aplicação.
  """

  alias Efi.Client

  @doc """
  Consulta as mudanças de status ligadas a um token de notificação.

  `GET /v1/notification/:token`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-cobrancas/notificacoes#consultando-detalhes-de-uma-notificação)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, token, opts \\ []) do
    path = Client.path("/v1/notification/:token", token: token)
    Client.request(client, :charges, :get, path, opts)
  end
end
