defmodule Efi.Pix.WebhookTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Webhook

  setup {Req.Test, :verify_on_exit!}

  @key "chave-pix-do-studio-ana"
  @webhook_url "https://app.example.com/webhooks/efi?hmac=segredo-do-studio-ana&ignorar="

  test "registers the webhook from behind a TLS-terminating proxy, then reads, lists and cancels it" do
    client = Efi.Test.client()

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/webhook/#{@key}", fn conn, _body ->
      assert Plug.Conn.get_req_header(conn, "x-skip-mtls-checking") == []

      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "nome" => "webhook_invalido",
        "mensagem" => "A autenticação de TLS mútuo não está configurada na URL informada"
      })
    end)

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/webhook/#{@key}", fn conn, body ->
      assert Plug.Conn.get_req_header(conn, "x-skip-mtls-checking") == ["true"]
      assert body == %{"webhookUrl" => @webhook_url}
      Plug.Conn.send_resp(conn, 201, "")
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/webhook/#{@key}", fn conn, _body ->
      Req.Test.json(conn, %{"webhookUrl" => @webhook_url, "chave" => @key})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/webhook", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z"
             }

      Req.Test.json(conn, %{"webhooks" => [%{"webhookUrl" => @webhook_url, "chave" => @key}]})
    end)

    Efi.Test.expect(:delete, "pix-h.api.efipay.com.br/v2/webhook/#{@key}", fn conn, _body ->
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert {:error,
            %Efi.Error{
              kind: :validation,
              name: "webhook_invalido",
              message: "A autenticação de TLS mútuo não está configurada na URL informada"
            }} = Webhook.configure(client, @key, %{"webhookUrl" => @webhook_url})

    assert {:ok, nil} =
             Webhook.configure(client, @key, %{"webhookUrl" => @webhook_url},
               skip_mtls_checking: true
             )

    assert {:ok, %{"chave" => @key}} = Webhook.get(client, @key)

    assert {:ok, %{"webhooks" => [%{"chave" => @key}]}} =
             Webhook.list(client, %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z"
             })

    assert {:ok, nil} = Webhook.delete(client, @key)
  end

  test "asks Efí to deliver again the notifications of payments the server missed" do
    client = Efi.Test.client(environment: :production)
    e2e_ids = ["E12345678202611191200abcdef12345", "E12345678202611191201abcdef12346"]

    Efi.Test.expect(:post, "pix.api.efipay.com.br/v2/gn/webhook/reenviar", fn conn, body ->
      assert body == %{"tipo" => "PIX_RECEBIDO", "e2eids" => e2e_ids}
      Plug.Conn.send_resp(conn, 202, "")
    end)

    assert {:ok, nil} = Webhook.resend(client, %{"tipo" => "PIX_RECEBIDO", "e2eids" => e2e_ids})
  end

  test "is told by the sandbox that resending notifications only works in production" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/gn/webhook/reenviar", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(500)
      |> Req.Test.json(%{
        "type" => "https://pix.bcb.gov.br/api/v2/error/WebhooksErroInterno",
        "title" => "Erro Interno",
        "status" => 500,
        "detail" => "Funcionalidade desabilitada em ambiente de homologação."
      })
    end)

    assert {:error,
            %Efi.Error{
              kind: :server,
              name: "WebhooksErroInterno",
              message: "Funcionalidade desabilitada em ambiente de homologação."
            }} =
             Webhook.resend(client, %{
               "tipo" => "PIX_RECEBIDO",
               "e2eids" => ["E12345678202611191200abcdef12345"]
             })
  end
end
