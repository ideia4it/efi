defmodule Efi.Charges.CarnetTest do
  use ExUnit.Case, async: true

  alias Efi.Charges.Carnet

  setup {Req.Test, :verify_on_exit!}

  @host "cobrancas-h.api.efipay.com.br"

  test "issues a carnet, moves and resends one parcel, settles another by hand and cancels the last" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:post, "#{@host}/v1/carnet", fn conn, body ->
      assert body["repeats"] == 3
      assert body["expire_at"] == "2026-12-10"
      assert body["customer"] == %{"name" => "Cliente do Studio Ana", "cpf" => "12345678909"}

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{
          "carnet_id" => 4004,
          "status" => "up_to_date",
          "charges" => [
            %{"charge_id" => 5001, "parcel" => "1", "status" => "waiting"},
            %{"charge_id" => 5002, "parcel" => "2", "status" => "waiting"},
            %{"charge_id" => 5003, "parcel" => "3", "status" => "waiting"}
          ]
        }
      })
    end)

    Efi.Test.expect(:put, "#{@host}/v1/carnet/4004/metadata", fn conn, body ->
      assert body == %{"notification_url" => "https://app.example.com/efi/notificacoes"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:put, "#{@host}/v1/carnet/4004/parcel/2", fn conn, body ->
      assert body == %{"expire_at" => "2027-01-20"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/carnet/4004/parcel/2/resend", fn conn, body ->
      assert body == %{"email" => "cliente@app.example.com"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:put, "#{@host}/v1/carnet/4004/parcel/1/settle", fn conn, _body ->
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:put, "#{@host}/v1/carnet/4004/parcel/3/cancel", fn conn, _body ->
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/carnet/4004/history", fn conn, body ->
      assert body == %{"description" => "Parcela 1 paga em dinheiro, parcela 3 dispensada"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:get, "#{@host}/v1/carnet/4004", fn conn, _body ->
      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{
          "carnet_id" => 4004,
          "charges" => [
            %{"parcel" => "1", "status" => "settled"},
            %{"parcel" => "2", "status" => "waiting", "expire_at" => "2027-01-20"},
            %{"parcel" => "3", "status" => "canceled"}
          ]
        }
      })
    end)

    assert {:ok, %{"data" => %{"carnet_id" => 4004, "charges" => [_, _, _]}}} =
             Carnet.create(client, %{
               "items" => [%{"name" => "Pacote de manicure", "value" => 15_000, "amount" => 1}],
               "customer" => %{"name" => "Cliente do Studio Ana", "cpf" => "12345678909"},
               "expire_at" => "2026-12-10",
               "repeats" => 3,
               "split_items" => false
             })

    assert {:ok, %{"code" => 200}} =
             Carnet.update_metadata(client, 4004, %{
               "notification_url" => "https://app.example.com/efi/notificacoes"
             })

    assert {:ok, %{"code" => 200}} =
             Carnet.update_parcel_due_date(client, 4004, 2, %{"expire_at" => "2027-01-20"})

    assert {:ok, %{"code" => 200}} =
             Carnet.resend_parcel(client, 4004, 2, %{"email" => "cliente@app.example.com"})

    assert {:ok, %{"code" => 200}} = Carnet.settle_parcel(client, 4004, 1)
    assert {:ok, %{"code" => 200}} = Carnet.cancel_parcel(client, 4004, 3)

    assert {:ok, %{"code" => 200}} =
             Carnet.add_history(client, 4004, %{
               "description" => "Parcela 1 paga em dinheiro, parcela 3 dispensada"
             })

    assert {:ok, %{"data" => %{"charges" => [%{"status" => "settled"}, _, _]}}} =
             Carnet.get(client, 4004)
  end

  test "is told it cannot bring parcels forward, pushes them later instead and resends the carnet" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:put, "#{@host}/v1/carnet/4004/parcels", fn conn, body ->
      assert body == %{"parcels" => [%{"parcel" => 2, "expire_at" => "2026-12-01"}]}

      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "code" => 3_500_101,
        "error" => "update_parcels",
        "error_description" =>
          "A propriedade [expire_at] informada é inválida. Não é possível antecipar o vencimento Parcela: [2]."
      })
    end)

    Efi.Test.expect(:put, "#{@host}/v1/carnet/4004/parcels", fn conn, body ->
      assert body == %{
               "parcels" => [
                 %{"parcel" => 2, "expire_at" => "2027-02-15"},
                 %{"parcel" => 3, "expire_at" => "2027-03-15"}
               ]
             }

      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/carnet/4004/resend", fn conn, body ->
      assert body == %{"email" => "cliente@app.example.com"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    assert {:error, %Efi.Error{kind: :validation, name: "update_parcels", message: message}} =
             Carnet.update_parcels_due_dates(client, 4004, %{
               "parcels" => [%{"parcel" => 2, "expire_at" => "2026-12-01"}]
             })

    assert message =~ "Não é possível antecipar o vencimento"

    assert {:ok, %{"code" => 200}} =
             Carnet.update_parcels_due_dates(client, 4004, %{
               "parcels" => [
                 %{"parcel" => 2, "expire_at" => "2027-02-15"},
                 %{"parcel" => 3, "expire_at" => "2027-03-15"}
               ]
             })

    assert {:ok, %{"code" => 200}} =
             Carnet.resend(client, 4004, %{"email" => "cliente@app.example.com"})
  end

  test "settles a whole carnet the customer paid off at the counter" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:put, "#{@host}/v1/carnet/4004/settle", fn conn, _body ->
      Req.Test.json(conn, %{"code" => 200})
    end)

    assert {:ok, %{"code" => 200}} = Carnet.settle(client, 4004)
  end

  test "cancels the carnet of a customer who gave up the package" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:put, "#{@host}/v1/carnet/4004/cancel", fn conn, _body ->
      Req.Test.json(conn, %{"code" => 200})
    end)

    assert {:ok, %{"code" => 200}} = Carnet.cancel(client, 4004)
  end
end
