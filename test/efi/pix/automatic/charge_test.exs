defmodule Efi.Pix.Automatic.ChargeTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Automatic.Charge

  setup {Req.Test, :verify_on_exit!}

  @recurrence_id "RR1234567820261119studioana001"
  @txid "studioanadezembro000000000001"

  @december_charge %{
    "idRec" => @recurrence_id,
    "infoAdicional" => "Plano mensal de escova, dezembro",
    "calendario" => %{"dataDeVencimento" => "2026-12-10"},
    "valor" => %{"original" => "150.00"},
    "ajusteDiaUtil" => true,
    "recebedor" => %{"agencia" => "0001", "conta" => "123456", "tipoConta" => "PAGAMENTO"}
  }

  test "bills the December period of an approved recurrence, checks it, finds it among the plan's charges and cancels it before the debit" do
    client = Efi.Test.client()

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/cobr/#{@txid}", fn conn, body ->
      assert body == @december_charge

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"idRec" => @recurrence_id, "txid" => @txid, "status" => "CRIADA"})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cobr/#{@txid}", fn conn, _body ->
      Req.Test.json(conn, %{
        "txid" => @txid,
        "status" => "ATIVA",
        "tentativas" => [
          %{"dataLiquidacao" => "2026-12-10", "tipo" => "AGND", "status" => "AGENDADA"}
        ]
      })
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cobr", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-12-31T23:59:59Z",
               "idRec" => @recurrence_id
             }

      Req.Test.json(conn, %{"cobsr" => [%{"txid" => @txid, "status" => "ATIVA"}]})
    end)

    Efi.Test.expect(:patch, "pix-h.api.efipay.com.br/v2/cobr/#{@txid}", fn conn, body ->
      assert body == %{"status" => "CANCELADA"}

      Req.Test.json(conn, %{
        "txid" => @txid,
        "status" => "CANCELADA",
        "encerramento" => %{"cancelamento" => %{"solicitante" => "USUARIO_RECEBEDOR"}}
      })
    end)

    assert {:ok, %{"txid" => @txid, "status" => "CRIADA"}} =
             Charge.create_with_txid(client, @txid, @december_charge)

    assert {:ok, %{"tentativas" => [%{"status" => "AGENDADA"}]}} = Charge.get(client, @txid)

    assert {:ok, %{"cobsr" => [%{"txid" => @txid}]}} =
             Charge.list(client, %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-12-31T23:59:59Z",
               "idRec" => @recurrence_id
             })

    assert {:ok, %{"status" => "CANCELADA"}} =
             Charge.update(client, @txid, %{"status" => "CANCELADA"})
  end

  test "lets Efí pick the txid and schedules a new debit after the first one fails" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/cobr", fn conn, body ->
      assert body == @december_charge

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"txid" => @txid, "status" => "CRIADA"})
    end)

    Efi.Test.expect(
      :post,
      "pix-h.api.efipay.com.br/v2/cobr/#{@txid}/retentativa/2026-12-12",
      fn conn, body ->
        assert body == nil

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{
          "txid" => @txid,
          "tentativas" => [
            %{"dataLiquidacao" => "2026-12-10", "tipo" => "AGND", "status" => "EXPIRADA"},
            %{"dataLiquidacao" => "2026-12-12", "tipo" => "NTAG", "status" => "AGENDADA"}
          ]
        })
      end
    )

    assert {:ok, %{"txid" => @txid}} = Charge.create(client, @december_charge)

    assert {:ok, %{"tentativas" => [%{"status" => "EXPIRADA"}, %{"status" => "AGENDADA"}]}} =
             Charge.retry(client, @txid, ~D[2026-12-12])
  end

  test "refuses a retry when the recurrence does not allow one" do
    client = Efi.Test.client()

    Efi.Test.expect(
      :post,
      "pix-h.api.efipay.com.br/v2/cobr/#{@txid}/retentativa/2026-12-12",
      fn conn, _body ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{
          "type" => "https://pix.bcb.gov.br/api/v2/error/CobROperacaoInvalida",
          "title" => "Cobrança não encontrada.",
          "status" => 400,
          "detail" => "A política configurada na recorrência não permite retentativa de cobrança."
        })
      end
    )

    assert {:error,
            %Efi.Error{
              kind: :validation,
              name: "CobROperacaoInvalida",
              message:
                "A política configurada na recorrência não permite retentativa de cobrança."
            }} = Charge.retry(client, @txid, "2026-12-12")
  end
end
