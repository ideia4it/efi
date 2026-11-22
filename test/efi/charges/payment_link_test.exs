defmodule Efi.Charges.PaymentLinkTest do
  use ExUnit.Case, async: true

  alias Efi.Charges.Charge
  alias Efi.Charges.PaymentLink

  setup {Req.Test, :verify_on_exit!}

  @host "cobrancas-h.api.efipay.com.br"
  @payment_url "https://pagamento.gerencianet.com.br/identificador-do-link"

  test "sends the customer a payment link in one step" do
    client = Efi.Test.client(certificate: nil)

    link = %{
      "items" => [%{"name" => "Coloração", "value" => 18_000, "amount" => 1}],
      "customer" => %{"email" => "cliente@app.example.com"},
      "settings" => %{"payment_method" => "all", "expire_at" => "2026-12-20"}
    }

    Efi.Test.expect(:post, "#{@host}/v1/charge/one-step/link", fn conn, body ->
      assert body == link

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"charge_id" => 6006, "status" => "link", "payment_url" => @payment_url}
      })
    end)

    assert {:ok, %{"data" => %{"status" => "link", "payment_url" => @payment_url}}} =
             PaymentLink.create_one_step(client, link)
  end

  test "creates a charge, links it to the payment page, offers a boleto discount and resends the link" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:post, "#{@host}/v1/charge", fn conn, body ->
      assert body == %{"items" => [%{"name" => "Coloração", "value" => 18_000, "amount" => 1}]}
      Req.Test.json(conn, %{"code" => 200, "data" => %{"charge_id" => 6007, "status" => "new"}})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/charge/6007/link", fn conn, body ->
      assert body == %{"payment_method" => "credit_card", "expire_at" => "2026-12-20"}

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"charge_id" => 6007, "status" => "link", "payment_url" => @payment_url}
      })
    end)

    Efi.Test.expect(:put, "#{@host}/v1/charge/6007/link", fn conn, body ->
      assert body == %{"payment_method" => "all", "billet_discount" => 500}

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"charge_id" => 6007, "payment_method" => "all", "billet_discount" => 500}
      })
    end)

    Efi.Test.expect(:post, "#{@host}/v1/charge/6007/link/resend", fn conn, body ->
      assert body == %{"email" => "cliente@app.example.com"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    assert {:ok, %{"data" => %{"charge_id" => 6007}}} =
             Charge.create(client, %{
               "items" => [%{"name" => "Coloração", "value" => 18_000, "amount" => 1}]
             })

    assert {:ok, %{"data" => %{"payment_url" => @payment_url}}} =
             PaymentLink.create(client, 6007, %{
               "payment_method" => "credit_card",
               "expire_at" => "2026-12-20"
             })

    assert {:ok, %{"data" => %{"billet_discount" => 500}}} =
             PaymentLink.update(client, 6007, %{
               "payment_method" => "all",
               "billet_discount" => 500
             })

    assert {:ok, %{"code" => 200}} =
             PaymentLink.resend(client, 6007, %{"email" => "cliente@app.example.com"})
  end
end
