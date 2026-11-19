defmodule Efi.Charges.ChargeTest do
  use ExUnit.Case, async: true

  alias Efi.Charges.Charge

  setup {Req.Test, :verify_on_exit!}

  @host "cobrancas-h.api.efipay.com.br"
  @customer %{"name" => "Cliente do Studio Ana", "cpf" => "12345678909"}

  test "issues a balance sheet boleto in two steps, reschedules and resends it, then settles it by hand" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:post, "#{@host}/v1/charge", fn conn, body ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token-de-teste"]
      assert body == %{"items" => [%{"name" => "Corte", "value" => 8900, "amount" => 1}]}

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"charge_id" => 1001, "status" => "new", "total" => 8900}
      })
    end)

    Efi.Test.expect(:post, "#{@host}/v1/charge/1001/balance-sheet", fn conn, body ->
      assert body["title"] == "Demonstrativo de novembro"
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/charge/1001/pay", fn conn, body ->
      assert body["payment"]["banking_billet"]["customer"] == @customer
      assert body["payment"]["banking_billet"]["expire_at"] == "2026-12-15"

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"charge_id" => 1001, "status" => "waiting", "payment" => "banking_billet"}
      })
    end)

    Efi.Test.expect(:put, "#{@host}/v1/charge/1001/billet", fn conn, body ->
      assert body == %{"expire_at" => "2026-12-30"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/charge/1001/billet/resend", fn conn, body ->
      assert body == %{"email" => "cliente@app.example.com"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:put, "#{@host}/v1/charge/1001/metadata", fn conn, body ->
      assert body == %{
               "notification_url" => "https://app.example.com/efi/notificacoes",
               "custom_id" => "atendimento-42"
             }

      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/charge/1001/history", fn conn, body ->
      assert body == %{"description" => "Pago em dinheiro no balcão"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:put, "#{@host}/v1/charge/1001/settle", fn conn, body ->
      assert body == nil
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:get, "#{@host}/v1/charge/1001", fn conn, _body ->
      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"charge_id" => 1001, "status" => "settled", "custom_id" => "atendimento-42"}
      })
    end)

    assert {:ok, %{"data" => %{"charge_id" => 1001, "status" => "new"}}} =
             Charge.create(client, %{
               "items" => [%{"name" => "Corte", "value" => 8900, "amount" => 1}]
             })

    assert {:ok, %{"code" => 200}} =
             Charge.set_balance_sheet(client, 1001, %{
               "title" => "Demonstrativo de novembro",
               "body" => [%{"header" => "Serviços", "tables" => []}]
             })

    assert {:ok, %{"data" => %{"status" => "waiting"}}} =
             Charge.set_payment_method(client, 1001, %{
               "payment" => %{
                 "banking_billet" => %{"customer" => @customer, "expire_at" => "2026-12-15"}
               }
             })

    assert {:ok, %{"code" => 200}} =
             Charge.update_billet_due_date(client, 1001, %{"expire_at" => "2026-12-30"})

    assert {:ok, %{"code" => 200}} =
             Charge.resend_billet(client, 1001, %{"email" => "cliente@app.example.com"})

    assert {:ok, %{"code" => 200}} =
             Charge.update_metadata(client, 1001, %{
               "notification_url" => "https://app.example.com/efi/notificacoes",
               "custom_id" => "atendimento-42"
             })

    assert {:ok, %{"code" => 200}} =
             Charge.add_history(client, 1001, %{"description" => "Pago em dinheiro no balcão"})

    assert {:ok, %{"code" => 200}} = Charge.settle(client, 1001)

    assert {:ok, %{"data" => %{"status" => "settled", "custom_id" => "atendimento-42"}}} =
             Charge.get(client, 1001)
  end

  test "issues a one-step boleto split with a partner, finds it in the month's list and cancels it" do
    client = Efi.Test.client(certificate: nil)

    item = %{
      "name" => "Pacote de unhas",
      "value" => 10_000,
      "amount" => 1,
      "marketplace" => %{
        "mode" => 2,
        "repasses" => [%{"payee_code" => "payee-code-do-parceiro", "percentage" => 2500}]
      }
    }

    Efi.Test.expect(:post, "#{@host}/v1/charge/one-step", fn conn, body ->
      assert body["items"] == [item]
      assert body["payment"]["banking_billet"]["customer"] == @customer

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{
          "charge_id" => 2002,
          "status" => "waiting",
          "barcode" => "00000.00000 00000.000000 00000.000000 0 00000000000000",
          "pix" => %{"qrcode" => "00020101021226990014BR.GOV.BCB.PIX"}
        }
      })
    end)

    Efi.Test.expect(:get, "#{@host}/v1/charges", fn conn, _body ->
      assert conn.query_params == %{
               "charge_type" => "billet",
               "begin_date" => "2026-11-01",
               "end_date" => "2026-11-30",
               "status" => "waiting"
             }

      Req.Test.json(conn, %{"code" => 200, "data" => [%{"id" => 2002, "status" => "waiting"}]})
    end)

    Efi.Test.expect(:put, "#{@host}/v1/charge/2002/cancel", fn conn, _body ->
      Req.Test.json(conn, %{"code" => 200})
    end)

    assert {:ok, %{"data" => %{"charge_id" => 2002, "pix" => %{"qrcode" => _qrcode}}}} =
             Charge.create_one_step(client, %{
               "items" => [item],
               "payment" => %{
                 "banking_billet" => %{"customer" => @customer, "expire_at" => "2026-12-15"}
               }
             })

    assert {:ok, %{"data" => [%{"id" => 2002}]}} =
             Charge.list(client, %{
               "charge_type" => "billet",
               "begin_date" => "2026-11-01",
               "end_date" => "2026-11-30",
               "status" => "waiting"
             })

    assert {:ok, %{"code" => 200}} = Charge.cancel(client, 2002)
  end

  test "reports the property Efí rejected when a boleto due date is invalid" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:put, "#{@host}/v1/charge/1001/billet", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "code" => 3_500_034,
        "error" => "validation_error",
        "error_description" => %{
          "property" => "/expire_at",
          "message" => "A string não corresponde ao modelo."
        }
      })
    end)

    assert {:error,
            %Efi.Error{
              kind: :validation,
              status: 400,
              name: "validation_error",
              message: "A string não corresponde ao modelo.",
              body: %{"error_description" => %{"property" => "/expire_at"}}
            }} = Charge.update_billet_due_date(client, 1001, %{"expire_at" => "30/12/2026"})
  end
end
