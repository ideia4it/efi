defmodule Efi.OpenFinance.ConfigTest do
  use ExUnit.Case, async: true

  alias Efi.OpenFinance.Config

  setup {Req.Test, :verify_on_exit!}

  @settings %{
    "redirectURL" => "https://app.example.com/open-finance/retorno",
    "webhookURL" => "https://app.example.com/open-finance/webhook",
    "webhookSecurity" => %{"type" => "hmac", "hash" => "segredo-do-studio-ana"},
    "processPayment" => "async"
  }

  test "finds no settings on the first run, points the payer's return and the notifications to the app and reads them back" do
    client = Efi.Test.client()

    Efi.Test.expect(:get, "openfinance-h.api.efipay.com.br/v1/config", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{
        "nome" => "configuracao_nao_encontrada",
        "mensagem" => "Nenhuma configuração encontrada"
      })
    end)

    Efi.Test.expect(:put, "openfinance-h.api.efipay.com.br/v1/config", fn conn, body ->
      assert body == @settings

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(@settings)
    end)

    Efi.Test.expect(:get, "openfinance-h.api.efipay.com.br/v1/config", fn conn, body ->
      assert body == nil
      Req.Test.json(conn, Map.put(@settings, "generateTxIdForInic", false))
    end)

    assert {:error,
            %Efi.Error{kind: :not_found, status: 404, name: "configuracao_nao_encontrada"}} =
             Config.get(client)

    assert {:ok, @settings} = Config.update(client, @settings)

    assert {:ok, %{"webhookURL" => "https://app.example.com/open-finance/webhook"}} =
             Config.get(client)
  end

  test "switches the webhook to hmac when the Efí cannot complete the mTLS handshake" do
    client = Efi.Test.client()
    mtls_settings = Map.put(@settings, "webhookSecurity", %{"type" => "mtls"})

    Efi.Test.expect(:put, "openfinance-h.api.efipay.com.br/v1/config", fn conn, body ->
      assert body == mtls_settings

      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{
        "nome" => "webhook_url_invalido",
        "mensagem" => "Erro ao fazer handshake com mTLS no webhookURL"
      })
    end)

    Efi.Test.expect(:put, "openfinance-h.api.efipay.com.br/v1/config", fn conn, body ->
      assert body == @settings

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(@settings)
    end)

    assert {:error,
            %Efi.Error{
              kind: :validation,
              status: 422,
              name: "webhook_url_invalido",
              message: "Erro ao fazer handshake com mTLS no webhookURL"
            }} = Config.update(client, mtls_settings)

    assert {:ok, %{"webhookSecurity" => %{"type" => "hmac"}}} = Config.update(client, @settings)
  end
end
