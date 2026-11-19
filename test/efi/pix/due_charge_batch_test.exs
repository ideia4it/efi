defmodule Efi.Pix.DueChargeBatchTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.DueChargeBatch

  setup {Req.Test, :verify_on_exit!}

  @batch_id 202_612
  @first_txid "studioana0000000000000000001"
  @second_txid "studioana0000000000000000002"

  test "sends a month of due-date charges as a batch, revises one of them and follows each charge's processing" do
    client = Efi.Test.client()

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/lotecobv/#{@batch_id}", fn conn, body ->
      assert body["descricao"] == "Mensalidades de dezembro do Studio Ana"
      assert Enum.map(body["cobsv"], & &1["txid"]) == [@first_txid, @second_txid]
      Plug.Conn.send_resp(conn, 202, "")
    end)

    Efi.Test.expect(:patch, "pix-h.api.efipay.com.br/v2/lotecobv/#{@batch_id}", fn conn, body ->
      assert body == %{
               "cobsv" => [%{"txid" => @second_txid, "valor" => %{"original" => "180.00"}}]
             }

      Plug.Conn.send_resp(conn, 202, "")
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/lotecobv/#{@batch_id}", fn conn, _body ->
      Req.Test.json(conn, %{
        "descricao" => "Mensalidades de dezembro do Studio Ana",
        "cobsv" => [
          %{"txid" => @first_txid, "status" => "CRIADA"},
          %{
            "txid" => @second_txid,
            "status" => "NEGADA",
            "problema" => %{"title" => "Cobrança inválida.", "status" => 400}
          }
        ]
      })
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/lotecobv", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z"
             }

      Req.Test.json(conn, %{
        "lotes" => [%{"descricao" => "Mensalidades de dezembro do Studio Ana"}]
      })
    end)

    assert {:ok, nil} =
             DueChargeBatch.create(client, @batch_id, %{
               "descricao" => "Mensalidades de dezembro do Studio Ana",
               "cobsv" => [monthly_charge(@first_txid), monthly_charge(@second_txid)]
             })

    assert {:ok, nil} =
             DueChargeBatch.update(client, @batch_id, %{
               "cobsv" => [%{"txid" => @second_txid, "valor" => %{"original" => "180.00"}}]
             })

    assert {:ok, %{"cobsv" => [%{"status" => "CRIADA"}, %{"status" => "NEGADA"}]}} =
             DueChargeBatch.get(client, @batch_id)

    assert {:ok, %{"lotes" => [_batch]}} =
             DueChargeBatch.list(client, %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z"
             })
  end

  defp monthly_charge(txid) do
    %{
      "txid" => txid,
      "calendario" => %{"dataDeVencimento" => "2026-12-10"},
      "devedor" => %{"cpf" => "12345678909", "nome" => "Cliente do Studio Ana"},
      "valor" => %{"original" => "150.00"},
      "chave" => "chave-pix-do-studio-ana"
    }
  end
end
