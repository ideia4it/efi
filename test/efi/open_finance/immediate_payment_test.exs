defmodule Efi.OpenFinance.ImmediatePaymentTest do
  use ExUnit.Case, async: true

  alias Efi.OpenFinance.ImmediatePayment

  setup {Req.Test, :verify_on_exit!}

  @idempotency_key "6f1c2b9e-6a57-4c1e-9d2a-7b3e8f0a1c55"
  @payment_id "urn:efi:ae71713f-875b-4af3-9d85-0bcb43288847"
  @encoded_payment_id "urn:efi:ae71713f-875b-4af3-9d85-0bcb43288847"
  @payment %{
    "pagador" => %{
      "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002",
      "cpf" => "12345678909"
    },
    "favorecido" => %{"chave" => "chave-pix-do-studio-ana"},
    "pagamento" => %{"valor" => "50.00", "infoPagador" => "Corte e escova"}
  }

  test "sends the payer to their bank, finds the accepted payment and refunds part of it" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "openfinance-h.api.efipay.com.br/v1/pagamentos/pix", fn conn, body ->
      assert body == @payment
      assert Plug.Conn.get_req_header(conn, "x-idempotency-key") == [@idempotency_key]

      Req.Test.json(conn, %{
        "identificadorPagamento" => @payment_id,
        "redirectURI" => "https://banco-do-pagador.example.com/authorize?request=eyJjd"
      })
    end)

    Efi.Test.expect(:get, "openfinance-h.api.efipay.com.br/v1/pagamentos/pix", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-19",
               "fim" => "2026-11-19",
               "identificador" => @payment_id
             }

      Req.Test.json(conn, %{
        "pagamentos" => [
          %{"identificadorPagamento" => @payment_id, "valor" => "50.00", "status" => "aceito"}
        ],
        "total" => 1
      })
    end)

    Efi.Test.expect(
      :post,
      "openfinance-h.api.efipay.com.br/v1/pagamentos/pix/#{@encoded_payment_id}/devolver",
      fn conn, body ->
        assert body == %{"valor" => "10.00"}

        conn
        |> Plug.Conn.put_status(202)
        |> Req.Test.json(%{
          "identificadorPagamento" => @payment_id,
          "valor" => "10.00",
          "status" => "pendente"
        })
      end
    )

    assert {:ok,
            %{
              "identificadorPagamento" => @payment_id,
              "redirectURI" => "https://banco-do-pagador.example.com/" <> _request
            }} = ImmediatePayment.create(client, @idempotency_key, @payment)

    assert {:ok, %{"pagamentos" => [%{"status" => "aceito"}]}} =
             ImmediatePayment.list(client, %{
               "inicio" => "2026-11-19",
               "fim" => "2026-11-19",
               "identificador" => @payment_id
             })

    assert {:ok, %{"status" => "pendente", "valor" => "10.00"}} =
             ImmediatePayment.refund(client, @payment_id, %{"valor" => "10.00"})
  end

  test "reports an idempotency key reused for a different payment as a conflict" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "openfinance-h.api.efipay.com.br/v1/pagamentos/pix", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(409)
      |> Req.Test.json(%{
        "nome" => "conflito_chave_idempotencia",
        "mensagem" => "Chave de idempotência repetida para pagamento diferente"
      })
    end)

    assert {:error,
            %Efi.Error{
              kind: :conflict,
              status: 409,
              name: "conflito_chave_idempotencia",
              message: "Chave de idempotência repetida para pagamento diferente"
            }} = ImmediatePayment.create(client, @idempotency_key, @payment)
  end
end
