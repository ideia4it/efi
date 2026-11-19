defmodule Efi.OpenFinance.RecurringPaymentTest do
  use ExUnit.Case, async: true

  alias Efi.OpenFinance.RecurringPayment

  setup {Req.Test, :verify_on_exit!}

  @idempotency_key "9a3e1d2c-5b4f-4e6a-8c7d-1f2e3d4c5b6a"
  @payment_id "urn:efi:ae71713f-875b-4af3-9d85-0bcb43288847"
  @payment_path "openfinance-h.api.efipay.com.br/v1/pagamentos-recorrentes/pix/urn%3Aefi%3Aae71713f-875b-4af3-9d85-0bcb43288847"
  @paid_installment "E09089356202612101500studioana01"
  @rejected_installment "E09089356202701101500studioana02"

  test "sells a six-month package, replaces a rejected installment, refunds a paid one and cancels the rest" do
    client = Efi.Test.client()

    payment = %{
      "pagador" => %{
        "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002",
        "cpf" => "12345678909"
      },
      "favorecido" => %{"chave" => "chave-pix-do-studio-ana"},
      "pagamento" => %{
        "valor" => "89.90",
        "infoPagador" => "Pacote de manicure",
        "recorrencia" => %{
          "tipo" => "mensal",
          "dataInicio" => "2026-12-10",
          "diaDoMes" => 10,
          "quantidade" => 6
        }
      }
    }

    Efi.Test.expect(
      :post,
      "openfinance-h.api.efipay.com.br/v1/pagamentos-recorrentes/pix",
      fn conn, body ->
        assert body == payment
        assert Plug.Conn.get_req_header(conn, "x-idempotency-key") == [@idempotency_key]

        Req.Test.json(conn, %{
          "identificadorPagamento" => @payment_id,
          "redirectURI" => "https://banco-do-pagador.example.com/authorize?request=eyJjd"
        })
      end
    )

    Efi.Test.expect(
      :get,
      "openfinance-h.api.efipay.com.br/v1/pagamentos-recorrentes/pix",
      fn conn, _body ->
        assert conn.query_params == %{
                 "inicio" => "2026-11-19",
                 "fim" => "2026-11-19",
                 "identificador" => @payment_id
               }

        Req.Test.json(conn, %{
          "pagamentos" => [
            %{
              "identificadorPagamento" => @payment_id,
              "status" => "ativa",
              "recorrencias" => [
                %{"endToEndId" => @paid_installment, "status" => "aceito"},
                %{"endToEndId" => @rejected_installment, "status" => "rejeitado"}
              ]
            }
          ],
          "total" => 1
        })
      end
    )

    Efi.Test.expect(
      :patch,
      "#{@payment_path}/substituir/#{@rejected_installment}",
      fn conn, body ->
        assert body == %{"valor" => "79.90"}

        Req.Test.json(conn, %{
          "identificadorPagamento" => @payment_id,
          "redirectURI" => "https://banco-do-pagador.example.com/authorize?request=eyJnb"
        })
      end
    )

    Efi.Test.expect(:post, "#{@payment_path}/devolver", fn conn, body ->
      assert body == %{"devolucoes" => [%{"endToEndId" => @paid_installment, "valor" => "89.90"}]}

      conn
      |> Plug.Conn.put_status(202)
      |> Req.Test.json([
        %{
          "identificadorPagamento" => @payment_id,
          "endToEndId" => @paid_installment,
          "valor" => "89.90",
          "status" => "pendente"
        }
      ])
    end)

    Efi.Test.expect(:patch, "#{@payment_path}/cancelar", fn conn, body ->
      assert body == nil
      Req.Test.json(conn, %{"identificadorPagamento" => @payment_id, "status" => "cancelado"})
    end)

    assert {:ok, %{"identificadorPagamento" => @payment_id, "redirectURI" => _bank_url}} =
             RecurringPayment.create(client, @idempotency_key, payment)

    assert {:ok, %{"pagamentos" => [%{"recorrencias" => [_paid, %{"status" => "rejeitado"}]}]}} =
             RecurringPayment.list(client, %{
               "inicio" => "2026-11-19",
               "fim" => "2026-11-19",
               "identificador" => @payment_id
             })

    assert {:ok, %{"redirectURI" => "https://banco-do-pagador.example.com/" <> _request}} =
             RecurringPayment.replace_installment(client, @payment_id, @rejected_installment,
               json: %{"valor" => "79.90"}
             )

    assert {:ok, [%{"endToEndId" => @paid_installment, "status" => "pendente"}]} =
             RecurringPayment.refund(client, @payment_id, %{
               "devolucoes" => [%{"endToEndId" => @paid_installment, "valor" => "89.90"}]
             })

    assert {:ok, %{"status" => "cancelado"}} = RecurringPayment.cancel(client, @payment_id)
  end

  test "replaces a rejected installment at the same amount when no new amount is given" do
    client = Efi.Test.client()

    Efi.Test.expect(
      :patch,
      "#{@payment_path}/substituir/#{@rejected_installment}",
      fn conn, body ->
        assert body == nil

        Req.Test.json(conn, %{
          "identificadorPagamento" => @payment_id,
          "redirectURI" => "https://banco-do-pagador.example.com/authorize?request=eyJnb"
        })
      end
    )

    assert {:ok, %{"identificadorPagamento" => @payment_id, "redirectURI" => _bank_url}} =
             RecurringPayment.replace_installment(client, @payment_id, @rejected_installment)
  end
end
