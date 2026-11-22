defmodule Efi.Pix.ReceivedTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Received

  setup {Req.Test, :verify_on_exit!}

  @e2e_id "E12345678202611191200abcdef12345"
  @txid "studioana0000000000000000001"

  test "confirms a payment announced by the webhook with the payer's bank and finds it among the day's charge payments" do
    client = Efi.Test.client()

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/pix/#{@e2e_id}", fn conn, _body ->
      assert conn.query_params == %{"exibirCodigoBanco" => "true"}

      Req.Test.json(conn, %{
        "endToEndId" => @e2e_id,
        "txid" => @txid,
        "valor" => "50.00",
        "pagador" => %{"contaBanco" => %{"codigoBanco" => "09089356"}}
      })
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/pix", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-19T00:00:00Z",
               "fim" => "2026-11-19T23:59:59Z",
               "txIdPresente" => "true"
             }

      Req.Test.json(conn, %{"pix" => [%{"endToEndId" => @e2e_id, "txid" => @txid}]})
    end)

    assert {:ok,
            %{
              "txid" => @txid,
              "valor" => "50.00",
              "pagador" => %{"contaBanco" => %{"codigoBanco" => "09089356"}}
            }} = Received.get(client, @e2e_id, params: %{"exibirCodigoBanco" => true})

    assert {:ok, %{"pix" => [%{"endToEndId" => @e2e_id}]}} =
             Received.list(client, %{
               "inicio" => "2026-11-19T00:00:00Z",
               "fim" => "2026-11-19T23:59:59Z",
               "txIdPresente" => true
             })
  end
end
