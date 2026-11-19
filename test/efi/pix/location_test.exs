defmodule Efi.Pix.LocationTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Location

  setup {Req.Test, :verify_on_exit!}

  @txid "studioana0000000000000000001"

  test "reserves a QR Code, shares it once a charge is linked, then frees it for another charge" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/loc", fn conn, body ->
      assert body == %{"tipoCob" => "cob"}

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{
        "id" => 66,
        "location" => "qrcodes-pix.example.com/v2/66",
        "tipoCob" => "cob"
      })
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/loc/66", fn conn, _body ->
      Req.Test.json(conn, %{"id" => 66, "txid" => @txid, "tipoCob" => "cob"})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/loc/66/qrcode", fn conn, _body ->
      Req.Test.json(conn, %{
        "qrcode" => "00020101021226990014BR.GOV.BCB.PIX",
        "imagemQrcode" => "data:image/svg+xml;base64,PHN2Zz4=",
        "linkVisualizacao" => "https://pix.example.com/cob/pagar/66"
      })
    end)

    Efi.Test.expect(:delete, "pix-h.api.efipay.com.br/v2/loc/66/txid", fn conn, _body ->
      Req.Test.json(conn, %{"id" => 66, "tipoCob" => "cob"})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/loc", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-19T00:00:00Z",
               "fim" => "2026-11-19T23:59:59Z",
               "txIdPresente" => "false"
             }

      Req.Test.json(conn, %{"loc" => [%{"id" => 66, "tipoCob" => "cob"}]})
    end)

    assert {:ok, %{"id" => 66}} = Location.create(client, %{"tipoCob" => "cob"})

    assert {:ok, %{"txid" => @txid}} = Location.get(client, 66)

    assert {:ok, %{"imagemQrcode" => "data:image/svg+xml;base64," <> _image}} =
             Location.get_qr_code(client, 66)

    assert {:ok, unlinked} = Location.unlink_txid(client, 66)
    refute Map.has_key?(unlinked, "txid")

    assert {:ok, %{"loc" => [%{"id" => 66}]}} =
             Location.list(client, %{
               "inicio" => "2026-11-19T00:00:00Z",
               "fim" => "2026-11-19T23:59:59Z",
               "txIdPresente" => false
             })
  end
end
