defmodule Efi.OpenFinance.ScheduledPaymentTest do
  use ExUnit.Case, async: true

  alias Efi.OpenFinance.ScheduledPayment

  setup {Req.Test, :verify_on_exit!}

  @idempotency_key "0b6f3f0e-3d43-4b0e-9a6b-2a1d6c7e9f10"
  @scheduled_id "urn:efi:5c2a9e1f-0d3b-4c7a-8e6f-1a2b3c4d5e6f"
  @paid_id "urn:efi:49315a93-d39c-4564-9edb-9a73678dbdb1"
  @paid_end_to_end_id "E09089356202611191500studioana01"

  test "schedules a Pix, cancels it before the date and refunds an earlier one that was paid" do
    client = Efi.Test.client()

    payment = %{
      "pagador" => %{
        "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002",
        "cpf" => "12345678909"
      },
      "favorecido" => %{"chave" => "chave-pix-do-studio-ana"},
      "pagamento" => %{"valor" => "120.00", "dataAgendamento" => "2026-12-05"}
    }

    Efi.Test.expect(
      :post,
      "openfinance-h.api.efipay.com.br/v1/pagamentos-agendados/pix",
      fn conn, body ->
        assert body == payment
        assert Plug.Conn.get_req_header(conn, "x-idempotency-key") == [@idempotency_key]

        Req.Test.json(conn, %{
          "identificadorPagamento" => @scheduled_id,
          "redirectURI" => "https://banco-do-pagador.example.com/authorize?request=eyJjd"
        })
      end
    )

    Efi.Test.expect(
      :get,
      "openfinance-h.api.efipay.com.br/v1/pagamentos-agendados/pix",
      fn conn, _body ->
        assert conn.query_params == %{
                 "inicio" => "2026-11-01",
                 "fim" => "2026-11-30",
                 "status" => "agendado"
               }

        Req.Test.json(conn, %{
          "pagamentos" => [
            %{
              "identificadorPagamento" => @scheduled_id,
              "status" => "agendado",
              "dataOperacao" => "2026-12-05"
            }
          ],
          "total" => 1
        })
      end
    )

    Efi.Test.expect(
      :patch,
      "openfinance-h.api.efipay.com.br/v1/pagamentos-agendados/pix/urn:efi:5c2a9e1f-0d3b-4c7a-8e6f-1a2b3c4d5e6f/cancelar",
      fn conn, body ->
        assert body == nil

        Req.Test.json(conn, %{
          "identificadorPagamento" => @scheduled_id,
          "status" => "cancelado",
          "dataCancelamento" => "2026-11-19 10:02:25"
        })
      end
    )

    Efi.Test.expect(
      :post,
      "openfinance-h.api.efipay.com.br/v1/pagamentos-agendados/pix/urn:efi:49315a93-d39c-4564-9edb-9a73678dbdb1/devolver",
      fn conn, body ->
        assert body == %{"endToEndId" => @paid_end_to_end_id, "valor" => "120.00"}

        conn
        |> Plug.Conn.put_status(202)
        |> Req.Test.json(%{
          "identificadorPagamento" => @paid_id,
          "endToEndId" => @paid_end_to_end_id,
          "valor" => "120.00",
          "status" => "pendente"
        })
      end
    )

    assert {:ok, %{"identificadorPagamento" => @scheduled_id, "redirectURI" => _bank_url}} =
             ScheduledPayment.create(client, @idempotency_key, payment)

    assert {:ok, %{"pagamentos" => [%{"status" => "agendado"}]}} =
             ScheduledPayment.list(client, %{
               "inicio" => "2026-11-01",
               "fim" => "2026-11-30",
               "status" => "agendado"
             })

    assert {:ok, %{"status" => "cancelado"}} = ScheduledPayment.cancel(client, @scheduled_id)

    assert {:ok, %{"status" => "pendente", "endToEndId" => @paid_end_to_end_id}} =
             ScheduledPayment.refund(client, @paid_id, %{
               "endToEndId" => @paid_end_to_end_id,
               "valor" => "120.00"
             })
  end
end
