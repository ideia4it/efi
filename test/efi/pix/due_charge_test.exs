defmodule Efi.Pix.DueChargeTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.DueCharge

  setup {Req.Test, :verify_on_exit!}

  @txid "studioana0000000000000000001"

  test "bills a customer with a due date, raises the amount, reads the revision back and finds it by CPF" do
    client = Efi.Test.client()

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/cobv/#{@txid}", fn conn, body ->
      assert body["calendario"] == %{
               "dataDeVencimento" => "2026-12-10",
               "validadeAposVencimento" => 30
             }

      assert body["valor"]["multa"] == %{"modalidade" => 2, "valorPerc" => "2.00"}

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{
        "txid" => @txid,
        "revisao" => 0,
        "status" => "ATIVA",
        "loc" => %{"id" => 789, "tipoCob" => "cobv"},
        "pixCopiaECola" => "00020101021226880014BR.GOV.BCB.PIX"
      })
    end)

    Efi.Test.expect(:patch, "pix-h.api.efipay.com.br/v2/cobv/#{@txid}", fn conn, body ->
      assert body == %{"valor" => %{"original" => "150.00"}}
      Req.Test.json(conn, %{"txid" => @txid, "revisao" => 1, "status" => "ATIVA"})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cobv/#{@txid}", fn conn, _body ->
      assert conn.query_params == %{"revisao" => "1"}

      Req.Test.json(conn, %{
        "txid" => @txid,
        "revisao" => 1,
        "valor" => %{"original" => "150.00"}
      })
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cobv", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z",
               "cpf" => "12345678909"
             }

      Req.Test.json(conn, %{
        "parametros" => %{"paginacao" => %{"paginaAtual" => 0, "quantidadeTotalDeItens" => 1}},
        "cobs" => [%{"txid" => @txid, "status" => "ATIVA"}]
      })
    end)

    assert {:ok, %{"status" => "ATIVA", "loc" => %{"id" => 789}}} =
             DueCharge.create(client, @txid, %{
               "calendario" => %{
                 "dataDeVencimento" => "2026-12-10",
                 "validadeAposVencimento" => 30
               },
               "devedor" => %{"cpf" => "12345678909", "nome" => "Cliente do Studio Ana"},
               "valor" => %{
                 "original" => "120.00",
                 "multa" => %{"modalidade" => 2, "valorPerc" => "2.00"}
               },
               "chave" => "chave-pix-do-studio-ana"
             })

    assert {:ok, %{"revisao" => 1}} =
             DueCharge.update(client, @txid, %{"valor" => %{"original" => "150.00"}})

    assert {:ok, %{"valor" => %{"original" => "150.00"}}} =
             DueCharge.get(client, @txid, params: %{"revisao" => 1})

    assert {:ok, %{"cobs" => [%{"txid" => @txid}]}} =
             DueCharge.list(client, %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z",
               "cpf" => "12345678909"
             })
  end

  test "cancels a charge, sees it removed and is refused when revising it afterwards" do
    client = Efi.Test.client()

    Efi.Test.expect(:patch, "pix-h.api.efipay.com.br/v2/cobv/#{@txid}", fn conn, body ->
      assert body == %{"status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"}

      Req.Test.json(conn, %{
        "txid" => @txid,
        "revisao" => 1,
        "status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"
      })
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cobv/#{@txid}", fn conn, _body ->
      assert conn.query_params == %{}
      Req.Test.json(conn, %{"txid" => @txid, "status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"})
    end)

    Efi.Test.expect(:patch, "pix-h.api.efipay.com.br/v2/cobv/#{@txid}", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "type" => "https://pix.bcb.gov.br/api/v2/error/CobVOperacaoInvalida",
        "title" => "Operação inválida.",
        "status" => 400,
        "detail" =>
          "Cobrança não encontra-se mais com o status ATIVA, somente cobranças ativas podem ser revisadas."
      })
    end)

    assert {:ok, %{"status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"}} =
             DueCharge.update(client, @txid, %{"status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"})

    assert {:ok, %{"status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"}} = DueCharge.get(client, @txid)

    assert {:error,
            %Efi.Error{
              kind: :validation,
              status: 400,
              name: "CobVOperacaoInvalida",
              message: "Cobrança não encontra-se mais com o status ATIVA" <> _rest
            }} = DueCharge.update(client, @txid, %{"valor" => %{"original" => "90.00"}})
  end
end
