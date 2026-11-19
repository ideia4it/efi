defmodule Efi.Pix.ImmediateChargeTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.ImmediateCharge

  setup {Req.Test, :verify_on_exit!}

  @txid "studioana0000000000000000001"

  test "charges a customer, raises the amount, reads the revision back and finds it in the day's list" do
    client = Efi.Test.client()

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/cob/#{@txid}", fn conn, body ->
      assert body["valor"] == %{"original" => "50.00"}
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token-de-teste"]

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"txid" => @txid, "revisao" => 0, "status" => "ATIVA"})
    end)

    Efi.Test.expect(:patch, "pix-h.api.efipay.com.br/v2/cob/#{@txid}", fn conn, body ->
      assert body == %{"valor" => %{"original" => "60.00"}}
      Req.Test.json(conn, %{"txid" => @txid, "revisao" => 1})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/#{@txid}", fn conn, _body ->
      assert conn.query_params == %{"revisao" => "1"}
      Req.Test.json(conn, %{"txid" => @txid, "revisao" => 1, "valor" => %{"original" => "60.00"}})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/#{@txid}", fn conn, _body ->
      assert conn.query_params == %{}
      Req.Test.json(conn, %{"txid" => @txid, "revisao" => 1, "status" => "ATIVA"})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-19T00:00:00Z",
               "fim" => "2026-11-19T23:59:59Z"
             }

      Req.Test.json(conn, %{"cobs" => [%{"txid" => @txid}]})
    end)

    assert {:ok, %{"status" => "ATIVA"}} =
             ImmediateCharge.create_with_txid(client, @txid, %{
               "calendario" => %{"expiracao" => 3600},
               "valor" => %{"original" => "50.00"},
               "chave" => "chave-pix-do-studio-ana"
             })

    assert {:ok, %{"revisao" => 1}} =
             ImmediateCharge.update(client, @txid, %{"valor" => %{"original" => "60.00"}})

    assert {:ok, %{"valor" => %{"original" => "60.00"}}} =
             ImmediateCharge.get(client, @txid, params: %{"revisao" => 1})

    assert {:ok, %{"revisao" => 1, "status" => "ATIVA"}} = ImmediateCharge.get(client, @txid)

    assert {:ok, %{"cobs" => [%{"txid" => @txid}]}} =
             ImmediateCharge.list(client, %{
               "inicio" => "2026-11-19T00:00:00Z",
               "fim" => "2026-11-19T23:59:59Z"
             })
  end

  test "lets Efí pick the txid and reports a duplicated txid as a conflict" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/cob", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"txid" => "gerado0000000000000000000001", "status" => "ATIVA"})
    end)

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/cob/#{@txid}", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(409)
      |> Req.Test.json(%{
        "nome" => "txid_duplicado",
        "mensagem" => "Campo txid informado já foi utilizado em outra cobrança"
      })
    end)

    assert {:ok, %{"txid" => "gerado0000000000000000000001"}} =
             ImmediateCharge.create(client, %{"valor" => %{"original" => "50.00"}})

    assert {:error, %Efi.Error{kind: :conflict, status: 409, name: "txid_duplicado"}} =
             ImmediateCharge.create_with_txid(client, @txid, %{
               "valor" => %{"original" => "50.00"}
             })
  end
end
