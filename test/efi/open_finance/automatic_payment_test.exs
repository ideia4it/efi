defmodule Efi.OpenFinance.AutomaticPaymentTest do
  use ExUnit.Case, async: true

  alias Efi.OpenFinance.AutomaticPayment

  setup {Req.Test, :verify_on_exit!}

  @payment_key "5a6b7c8d-9e0f-4a1b-8c2d-3e4f5a6b7c8d"
  @revocation_key "1f2e3d4c-5b6a-4978-8a6b-5c4d3e2f1a0b"
  @enrollment_id "urn:efi:19ba4105-9ae2-4637-89f2-96506d3c8770"
  @end_to_end_id "E09089356202612101500studioana01"
  @enrollments_url "openfinance-h.api.efipay.com.br/v1/pagamentos-automaticos/adesao"
  @payments_url "openfinance-h.api.efipay.com.br/v1/pagamentos-automaticos/pix"

  test "enrolls a customer in a monthly club, charges a cycle, cancels it and revokes the enrollment" do
    client = Efi.Test.client()

    enrollment = %{
      "pagador" => %{
        "cpf" => "12345678909",
        "nome" => "Cliente do Studio Ana",
        "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002"
      },
      "favorecido" => %{
        "contaBanco" => %{
          "nome" => "Studio Ana",
          "documento" => "11222333000181",
          "codigoBanco" => "09089356",
          "agencia" => "0001",
          "conta" => "1234567",
          "tipoConta" => "CACC"
        }
      },
      "assinatura" => %{
        "expiracao" => "2027-12-31",
        "descricao" => "Clube de escova mensal",
        "configuracao" => %{
          "automatico" => %{
            "valorFixo" => "150.00",
            "intervalo" => "MENSAL",
            "dataInicio" => "2026-12-10"
          }
        }
      }
    }

    payment = %{
      "identificadorAdesao" => @enrollment_id,
      "pagamento" => %{"valor" => "150.00", "data" => "2026-12-10", "infoPagador" => "Dezembro"}
    }

    Efi.Test.expect(:post, @enrollments_url, fn conn, body ->
      assert body == enrollment

      Req.Test.json(conn, %{
        "identificadorAdesao" => @enrollment_id,
        "redirectURI" => "https://banco-do-pagador.example.com/authorize?request=eyJjd"
      })
    end)

    Efi.Test.expect(:get, @enrollments_url, fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-19",
               "fim" => "2026-11-19",
               "status" => "autorizado"
             }

      Req.Test.json(conn, %{
        "adesoes" => [%{"identificadorAdesao" => @enrollment_id, "status" => "autorizado"}],
        "total" => 1
      })
    end)

    Efi.Test.expect(:post, @payments_url, fn conn, body ->
      assert body == payment
      assert Plug.Conn.get_req_header(conn, "x-idempotency-key") == [@payment_key]

      Req.Test.json(conn, %{
        "identificadorAdesao" => @enrollment_id,
        "endToEndId" => @end_to_end_id,
        "status" => "pendente",
        "data" => "2026-12-10"
      })
    end)

    Efi.Test.expect(:get, @payments_url, fn conn, _body ->
      assert conn.query_params == %{"identificadorAdesao" => @enrollment_id}

      Req.Test.json(conn, %{
        "identificadorAdesao" => @enrollment_id,
        "status" => "autorizado",
        "pagamentos" => [%{"endToEndId" => @end_to_end_id, "status" => "agendado"}]
      })
    end)

    Efi.Test.expect(:patch, @payments_url, fn conn, body ->
      assert body == %{"identificadorAdesao" => @enrollment_id, "endToEndId" => @end_to_end_id}

      Req.Test.json(conn, %{
        "identificadorAdesao" => @enrollment_id,
        "endToEndId" => @end_to_end_id,
        "status" => "cancelado",
        "motivo" => "Cancelado pelo integrador"
      })
    end)

    Efi.Test.expect(:patch, @enrollments_url, fn conn, body ->
      assert body == %{"identificador" => @enrollment_id, "status" => "revogado"}
      assert Plug.Conn.get_req_header(conn, "x-idempotency-key") == [@revocation_key]

      Req.Test.json(conn, %{"identificadorAdesao" => @enrollment_id, "status" => "revogado"})
    end)

    assert {:ok, %{"identificadorAdesao" => @enrollment_id, "redirectURI" => _bank_url}} =
             AutomaticPayment.create_enrollment(client, enrollment)

    assert {:ok, %{"adesoes" => [%{"status" => "autorizado"}]}} =
             AutomaticPayment.list_enrollments(client, %{
               "inicio" => "2026-11-19",
               "fim" => "2026-11-19",
               "status" => "autorizado"
             })

    assert {:ok, %{"endToEndId" => @end_to_end_id, "status" => "pendente"}} =
             AutomaticPayment.create(client, @payment_key, payment)

    assert {:ok, %{"pagamentos" => [%{"endToEndId" => @end_to_end_id}]}} =
             AutomaticPayment.list(client, %{"identificadorAdesao" => @enrollment_id})

    assert {:ok, %{"status" => "cancelado"}} =
             AutomaticPayment.cancel(client, %{
               "identificadorAdesao" => @enrollment_id,
               "endToEndId" => @end_to_end_id
             })

    assert {:ok, %{"status" => "revogado"}} =
             AutomaticPayment.update_enrollment(client, @revocation_key, %{
               "identificador" => @enrollment_id,
               "status" => "revogado"
             })
  end
end
