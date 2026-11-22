defmodule Efi.Charges.CardTest do
  use ExUnit.Case, async: true

  alias Efi.Charges.Card
  alias Efi.Charges.Charge

  setup {Req.Test, :verify_on_exit!}

  @host "cobrancas-h.api.efipay.com.br"
  @customer %{
    "name" => "Cliente do Studio Ana",
    "cpf" => "12345678909",
    "email" => "cliente@app.example.com"
  }
  @billing_address %{
    "street" => "Rua das Flores",
    "number" => "100",
    "neighborhood" => "Centro",
    "zipcode" => "35400000",
    "city" => "Ouro Preto",
    "state" => "MG"
  }

  test "shows the installments, charges the card with 3DS and gets a challenge back" do
    client = Efi.Test.client(certificate: nil)

    charge = %{
      "items" => [%{"name" => "Pacote de 4 escovas", "value" => 20_000, "amount" => 1}],
      "customer" => @customer,
      "installments" => 2,
      "payment_token" => "token-do-cartao-gerado-no-navegador",
      "tds_info" => %{
        "tds_identifier" => "f81d4fae-7dec-11d0-a765-00a0c91e6bf6",
        "challenge_callback_url" => "https://app.example.com/pagamento/3ds"
      }
    }

    Efi.Test.expect(:get, "#{@host}/v1/installments", fn conn, _body ->
      assert conn.query_params == %{"brand" => "visa", "total" => "20000"}

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{
          "name" => "visa",
          "installments" => [
            %{"installment" => 1, "has_interest" => false, "value" => 20_000},
            %{"installment" => 2, "has_interest" => true, "value" => 10_300}
          ]
        }
      })
    end)

    Efi.Test.expect(:post, "#{@host}/v1/charge/card", fn conn, body ->
      assert body == charge

      Req.Test.json(conn, %{
        "charge_id" => 3003,
        "status" => "waiting",
        "total" => 20_000,
        "tds_challenge" => %{
          "form_data" => %{"method" => "POST", "action_url" => "https://3ds.example.com"},
          "html_template" => "<html></html>"
        }
      })
    end)

    assert {:ok, %{"data" => %{"installments" => [_one, %{"installment" => 2}]}}} =
             Card.list_installments(client, %{"brand" => "visa", "total" => 20_000})

    assert {:ok, %{"status" => "waiting", "tds_challenge" => %{"html_template" => _html}}} =
             Card.create(client, charge)
  end

  test "is refused by the issuer, pays on the retry with another card and refunds part of it" do
    client = Efi.Test.client(certificate: nil)

    first_attempt = %{
      "items" => [%{"name" => "Coloração", "value" => 18_000, "amount" => 1}],
      "payment" => %{
        "credit_card" => %{
          "customer" => @customer,
          "installments" => 1,
          "billing_address" => @billing_address,
          "payment_token" => "token-do-cartao-recusado"
        }
      }
    }

    retry = %{
      "payment" => %{
        "credit_card" => %{
          "customer" => @customer,
          "billing_address" => @billing_address,
          "payment_token" => "token-do-cartao-novo",
          "update_card" => true
        }
      }
    }

    Efi.Test.expect(:post, "#{@host}/v1/charge/one-step", fn conn, body ->
      assert body == first_attempt

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{
          "charge_id" => 3003,
          "status" => "unpaid",
          "refusal" => %{
            "reason" => "Transação não autorizada, tente novamente mais tarde.",
            "retry" => true
          },
          "total" => 18_000,
          "payment" => "credit_card"
        }
      })
    end)

    Efi.Test.expect(:post, "#{@host}/v1/charge/3003/retry", fn conn, body ->
      assert body == retry

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"charge_id" => 3003, "status" => "waiting", "payment" => "credit_card"}
      })
    end)

    Efi.Test.expect(:get, "#{@host}/v1/charge/3003", fn conn, _body ->
      Req.Test.json(conn, %{"code" => 200, "data" => %{"charge_id" => 3003, "status" => "paid"}})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/charge/card/3003/refund", fn conn, body ->
      assert body == %{"amount" => 5000}
      Req.Test.json(conn, %{"code" => 200, "data" => "Reembolso em processamento"})
    end)

    assert {:ok, %{"data" => %{"status" => "unpaid", "refusal" => %{"retry" => true}}}} =
             Charge.create_one_step(client, first_attempt)

    assert {:ok, %{"data" => %{"status" => "waiting"}}} = Card.retry(client, 3003, retry)
    assert {:ok, %{"data" => %{"status" => "paid"}}} = Charge.get(client, 3003)

    assert {:ok, %{"data" => "Reembolso em processamento"}} =
             Card.refund(client, 3003, json: %{"amount" => 5000})
  end

  test "refunds the whole card payment when no amount is given" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:post, "#{@host}/v1/charge/card/3004/refund", fn conn, body ->
      assert body == %{}
      Req.Test.json(conn, %{"code" => 200, "data" => "Reembolso em processamento"})
    end)

    assert {:ok, %{"data" => "Reembolso em processamento"}} = Card.refund(client, 3004)
  end

  test "reports a refused 3DS charge in the problem format of that route" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:post, "#{@host}/v1/charge/card", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(422)
      |> Req.Test.json(%{
        "title" => "Unprocessable Entity",
        "status" => 422,
        "detail" => "The request contains invalid or incomplete data"
      })
    end)

    assert {:error,
            %Efi.Error{
              kind: :validation,
              status: 422,
              message: "The request contains invalid or incomplete data"
            }} = Card.create(client, %{"items" => [], "payment_token" => "token-vencido"})
  end
end
