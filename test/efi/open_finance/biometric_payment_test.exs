defmodule Efi.OpenFinance.BiometricPaymentTest do
  use ExUnit.Case, async: true

  alias Efi.OpenFinance.BiometricPayment

  setup {Req.Test, :verify_on_exit!}

  @enrollment_key "2d7c9b1a-8e6f-4a3b-9c2d-5e4f3a2b1c0d"
  @payment_key "7e8f9a0b-1c2d-4e3f-8a9b-0c1d2e3f4a5b"
  @revocation_key "3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e6f"
  @enrollment_id "urn:efi:c0498e81-2c3a-4b29-931a-5c5ba2b1599a"
  @payment_id "urn:efi:49315a93-d39c-4564-9edb-9a73678dbdb1"
  @enrollments_url "openfinance-h.api.efipay.com.br/v1/pagamentos-biometria/vinculos"
  @payments_url "openfinance-h.api.efipay.com.br/v1/pagamentos-biometria/pix"

  test "links the payer's bank account once, pays with biometrics, finds the payment and revokes the link" do
    client = Efi.Test.client()

    payment = %{
      "identificadorVinculo" => @enrollment_id,
      "favorecido" => %{"chave" => "chave-pix-do-studio-ana"},
      "pagamento" => %{"valor" => "50.00", "infoPagador" => "Corte e escova"}
    }

    Efi.Test.expect(:post, @enrollments_url, fn conn, body ->
      assert body == %{
               "pagador" => %{
                 "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002",
                 "cpf" => "12345678909"
               }
             }

      assert Plug.Conn.get_req_header(conn, "x-idempotency-key") == [@enrollment_key]

      Req.Test.json(conn, %{
        "identificadorVinculo" => @enrollment_id,
        "redirectURI" => "https://efibank.com.br/create-enrollment?identifier=#{@enrollment_id}"
      })
    end)

    Efi.Test.expect(:get, @enrollments_url, fn conn, _body ->
      assert conn.query_params == %{"cpf" => "12345678909"}

      Req.Test.json(conn, %{
        "vinculos" => [
          %{
            "identificador" => @enrollment_id,
            "limiteTransacao" => "500.00",
            "participante" => %{"nome" => "Banco do Pagador"}
          }
        ]
      })
    end)

    Efi.Test.expect(:post, @payments_url, fn conn, body ->
      assert body == payment
      assert Plug.Conn.get_req_header(conn, "x-idempotency-key") == [@payment_key]

      Req.Test.json(conn, %{
        "identificadorPagamento" => @payment_id,
        "redirectURI" => "https://banco-do-pagador.example.com/authorize?request=eyJjd"
      })
    end)

    Efi.Test.expect(:get, @payments_url, fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-19",
               "fim" => "2026-11-19",
               "status" => "aceito"
             }

      Req.Test.json(conn, %{
        "vinculos" => [
          %{"identificadorPagamento" => @payment_id, "valor" => "50.00", "status" => "aceito"}
        ]
      })
    end)

    Efi.Test.expect(:patch, @enrollments_url, fn conn, body ->
      assert body == %{
               "identificadorVinculo" => @enrollment_id,
               "motivo" => "Cliente pediu para desvincular a conta"
             }

      assert Plug.Conn.get_req_header(conn, "x-idempotency-key") == [@revocation_key]

      Req.Test.json(conn, %{
        "identificadorVinculo" => @enrollment_id,
        "status" => "revogado",
        "data" => "2026-11-19"
      })
    end)

    assert {:ok, %{"identificadorVinculo" => @enrollment_id, "redirectURI" => _bank_url}} =
             BiometricPayment.create_enrollment(client, @enrollment_key, %{
               "pagador" => %{
                 "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002",
                 "cpf" => "12345678909"
               }
             })

    assert {:ok, %{"vinculos" => [%{"identificador" => @enrollment_id}]}} =
             BiometricPayment.list_enrollments(client, %{"cpf" => "12345678909"})

    assert {:ok, %{"identificadorPagamento" => @payment_id}} =
             BiometricPayment.create(client, @payment_key, payment)

    assert {:ok, %{"vinculos" => [%{"identificadorPagamento" => @payment_id}]}} =
             BiometricPayment.list(client, %{
               "inicio" => "2026-11-19",
               "fim" => "2026-11-19",
               "status" => "aceito"
             })

    assert {:ok, %{"status" => "revogado"}} =
             BiometricPayment.revoke_enrollment(client, @revocation_key, %{
               "identificadorVinculo" => @enrollment_id,
               "motivo" => "Cliente pediu para desvincular a conta"
             })
  end
end
