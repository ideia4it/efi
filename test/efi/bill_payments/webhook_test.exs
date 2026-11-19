defmodule Efi.BillPayments.WebhookTest do
  use ExUnit.Case, async: true

  alias Efi.BillPayments.Webhook

  setup {Req.Test, :verify_on_exit!}

  @host "pagarcontas.api.efipay.com.br"
  @webhook_url "https://app.example.com/efi/pagamentos"

  test "registers the payment webhook, finds it in the period and deletes it by url" do
    client = Efi.Test.client(environment: :production)

    Efi.Test.expect(:put, "#{@host}/v1/webhook", fn conn, body ->
      assert body == %{"url" => @webhook_url}

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"url" => @webhook_url})
    end)

    Efi.Test.expect(:get, "#{@host}/v1/webhook", fn conn, _body ->
      assert conn.query_params == %{
               "dataInicio" => "2026-11-01T00:00:00Z",
               "dataFim" => "2026-11-30T23:59:59Z"
             }

      Req.Test.json(conn, %{
        "webhooks" => [%{"url" => @webhook_url, "criacao" => "2026-11-19T10:00:00Z"}]
      })
    end)

    Efi.Test.expect(:delete, "#{@host}/v1/webhook", fn conn, body ->
      assert body == %{"url" => @webhook_url}
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert {:ok, %{"url" => @webhook_url}} = Webhook.configure(client, %{"url" => @webhook_url})

    assert {:ok, %{"webhooks" => [%{"url" => @webhook_url}]}} =
             Webhook.list(client, %{
               "dataInicio" => "2026-11-01T00:00:00Z",
               "dataFim" => "2026-11-30T23:59:59Z"
             })

    assert {:ok, nil} = Webhook.delete(client, %{"url" => @webhook_url})
  end
end
