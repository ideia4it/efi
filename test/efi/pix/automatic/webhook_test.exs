defmodule Efi.Pix.Automatic.WebhookTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Automatic.Webhook

  setup {Req.Test, :verify_on_exit!}

  @webhook_url "https://app.example.com/webhooks/efi?hmac=assinatura&ignorar="

  test "registers the recurrence webhook without mTLS checking after Efí rejects the proxied URL, reads it back and removes it" do
    client = Efi.Test.client()

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/webhookrec", fn conn, body ->
      assert body == %{"webhookUrl" => @webhook_url}
      assert Plug.Conn.get_req_header(conn, "x-skip-mtls-checking") == []

      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "type" => "https://pix.bcb.gov.br/api/v2/error/WebhookOperacaoInvalida",
        "title" => "Webhook inválido.",
        "status" => 400,
        "detail" =>
          "A presente requisição busca criar um webhook sem respeitar o _schema_ ou, ainda, com sentido semanticamente inválido."
      })
    end)

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/webhookrec", fn conn, body ->
      assert body == %{"webhookUrl" => @webhook_url}
      assert Plug.Conn.get_req_header(conn, "x-skip-mtls-checking") == ["true"]
      Req.Test.json(conn, %{"webhookUrl" => @webhook_url})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/webhookrec", fn conn, _body ->
      Req.Test.json(conn, %{"webhookUrl" => @webhook_url, "criacao" => "2026-11-19T12:51:16.485Z"})
    end)

    Efi.Test.expect(:delete, "pix-h.api.efipay.com.br/v2/webhookrec", fn conn, _body ->
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert {:error, %Efi.Error{kind: :validation, name: "WebhookOperacaoInvalida"}} =
             Webhook.configure_recurrence(client, %{"webhookUrl" => @webhook_url})

    assert {:ok, _configured} =
             Webhook.configure_recurrence(client, %{"webhookUrl" => @webhook_url},
               skip_mtls_checking: true
             )

    assert {:ok, %{"webhookUrl" => @webhook_url}} = Webhook.get_recurrence(client)
    assert {:ok, nil} = Webhook.delete_recurrence(client)
  end

  test "registers the automatic charge webhook, removes it and finds nothing registered afterwards" do
    client = Efi.Test.client()

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/webhookcobr", fn conn, body ->
      assert body == %{"webhookUrl" => @webhook_url}
      assert Plug.Conn.get_req_header(conn, "x-skip-mtls-checking") == []
      Req.Test.json(conn, %{"webhookUrl" => @webhook_url})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/webhookcobr", fn conn, _body ->
      Req.Test.json(conn, %{"webhookUrl" => @webhook_url, "criacao" => "2026-11-19T12:51:16.485Z"})
    end)

    Efi.Test.expect(:delete, "pix-h.api.efipay.com.br/v2/webhookcobr", fn conn, _body ->
      Plug.Conn.send_resp(conn, 204, "")
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/webhookcobr", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{
        "type" => "https://pix.bcb.gov.br/api/v2/error/NaoEncontrado",
        "title" => "Não Encontrado",
        "status" => 404,
        "detail" => "Entidade não encontrada."
      })
    end)

    assert {:ok, _configured} =
             Webhook.configure_charge(client, %{"webhookUrl" => @webhook_url})

    assert {:ok, %{"webhookUrl" => @webhook_url}} = Webhook.get_charge(client)
    assert {:ok, nil} = Webhook.delete_charge(client)

    assert {:error, %Efi.Error{kind: :not_found, status: 404, name: "NaoEncontrado"}} =
             Webhook.get_charge(client)
  end
end
