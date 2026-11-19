defmodule Efi.Accounts.WebhookTest do
  use ExUnit.Case, async: true

  alias Efi.Accounts.Webhook

  setup {Req.Test, :verify_on_exit!}

  @host "abrircontas-h.api.efipay.com.br"
  @webhook_id "92ecc0a8-9631-4601-a188-feacf8288c13"
  @webhook_url "https://app.example.com/efi/contas"
  @new_webhook_url "https://app.example.com/efi/abertura-de-contas"

  test "registers the account webhook, moves it to a new url, finds it and then cancels it" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "#{@host}/v1/webhook", fn conn, body ->
      assert body == %{"webhookUrl" => @webhook_url}
      Req.Test.json(conn, %{"identificadorWebhook" => @webhook_id})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/webhook", fn conn, body ->
      assert body == %{"url" => @new_webhook_url, "chave" => @webhook_id}
      Req.Test.json(conn, %{"identificadorWebhook" => @webhook_id})
    end)

    Efi.Test.expect(
      :get,
      "#{@host}/v1/webhook/#{@webhook_id}",
      fn conn, _body ->
        Req.Test.json(conn, %{
          "webhookUrl" => @new_webhook_url,
          "identificadorWebhook" => @webhook_id,
          "criacao" => "2026-11-19T10:00:00.000Z"
        })
      end
    )

    Efi.Test.expect(:get, "#{@host}/v1/webhooks", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z"
             }

      Req.Test.json(conn, %{
        "webhooks" => [%{"webhookUrl" => @new_webhook_url, "identificadorWebhook" => @webhook_id}]
      })
    end)

    Efi.Test.expect(
      :delete,
      "#{@host}/v1/webhook/#{@webhook_id}",
      fn conn, _body -> Plug.Conn.send_resp(conn, 204, "") end
    )

    assert {:ok, %{"identificadorWebhook" => @webhook_id}} =
             Webhook.configure(client, %{"webhookUrl" => @webhook_url})

    assert {:ok, %{"identificadorWebhook" => @webhook_id}} =
             Webhook.configure(client, %{"url" => @new_webhook_url, "chave" => @webhook_id})

    assert {:ok, %{"webhookUrl" => @new_webhook_url}} = Webhook.get(client, @webhook_id)

    assert {:ok, %{"webhooks" => [%{"identificadorWebhook" => @webhook_id}]}} =
             Webhook.list(client, %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z"
             })

    assert {:ok, nil} = Webhook.delete(client, @webhook_id)
  end
end
