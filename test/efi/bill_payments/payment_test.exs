defmodule Efi.BillPayments.PaymentTest do
  use ExUnit.Case, async: true

  alias Efi.BillPayments.Payment

  setup {Req.Test, :verify_on_exit!}

  @host "pagarcontas-h.api.efipay.com.br"
  @barcode "36490000000000000000000000000000000000000000"

  test "checks a bill's barcode, pays it, follows the payment and sees it in the period summary" do
    client = Efi.Test.client()

    Efi.Test.expect(:get, "#{@host}/v1/codBarras/#{@barcode}", fn conn, _body ->
      Req.Test.json(conn, %{
        "tipo" => "boleto",
        "codBarras" => @barcode,
        "valores" => %{"original" => 1000, "final" => 902},
        "informacoesPagamento" => %{"podeSerPago" => true}
      })
    end)

    Efi.Test.expect(:post, "#{@host}/v1/codBarras/#{@barcode}", fn conn, body ->
      assert body == %{
               "valor" => 902,
               "dataPagamento" => "2026-11-19",
               "descricao" => "Conta de luz do Studio Ana"
             }

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"idPagamento" => "31234652", "valorPago" => 902, "status" => "AGENDADO"})
    end)

    Efi.Test.expect(:get, "#{@host}/v1/31234652", fn conn, _body ->
      Req.Test.json(conn, %{"idPagamento" => "31234652", "status" => "LIQUIDADO"})
    end)

    Efi.Test.expect(:get, "#{@host}/v1/resumo", fn conn, _body ->
      assert conn.query_params == %{"dataInicio" => "2026-11-01", "dataFim" => "2026-11-30"}

      Req.Test.json(conn, %{
        "datas" => %{"inicial" => "2026-11-01", "final" => "2026-11-30"},
        "solicitacoes" => %{"total" => 1, "sucesso" => 1, "falha" => 0}
      })
    end)

    assert {:ok, %{"informacoesPagamento" => %{"podeSerPago" => true}} = bill} =
             Payment.get_barcode(client, @barcode)

    assert {:ok, %{"idPagamento" => payment_id, "status" => "AGENDADO"}} =
             Payment.create(client, @barcode, %{
               "valor" => bill["valores"]["final"],
               "dataPagamento" => "2026-11-19",
               "descricao" => "Conta de luz do Studio Ana"
             })

    assert {:ok, %{"status" => "LIQUIDADO"}} = Payment.get(client, payment_id)

    assert {:ok, %{"solicitacoes" => %{"total" => 1, "sucesso" => 1}}} =
             Payment.summary(client, %{"dataInicio" => "2026-11-01", "dataFim" => "2026-11-30"})
  end

  test "reports a barcode the Efí cannot find as a validation error" do
    client = Efi.Test.client()

    Efi.Test.expect(:get, "#{@host}/v1/codBarras/#{@barcode}", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "nome" => "erro_de_validacao",
        "mensagem" => "Código de barras não localizado na base centralizada"
      })
    end)

    assert {:error,
            %Efi.Error{
              kind: :validation,
              status: 400,
              name: "erro_de_validacao",
              message: "Código de barras não localizado na base centralizada"
            }} = Payment.get_barcode(client, @barcode)
  end
end
