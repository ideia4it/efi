defmodule Efi.Charges.SubscriptionTest do
  use ExUnit.Case, async: true

  alias Efi.Charges.Subscription

  setup {Req.Test, :verify_on_exit!}

  @host "cobrancas-h.api.efipay.com.br"
  @customer %{
    "name" => "Cliente do Studio Ana",
    "cpf" => "12345678909",
    "email" => "cliente@app.example.com"
  }

  test "subscribes a customer by card in one step, swaps the card, notes the history and cancels it" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:post, "#{@host}/v1/plan/7007/subscription/one-step", fn conn, body ->
      assert body["payment"]["credit_card"]["payment_token"] == "token-do-cartao"
      assert body["payment"]["credit_card"]["trial_days"] == 7

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{
          "subscription_id" => 8008,
          "status" => "active",
          "charge" => %{"id" => 9001, "status" => "waiting", "parcel" => 1}
        }
      })
    end)

    Efi.Test.expect(:put, "#{@host}/v1/subscription/8008", fn conn, body ->
      assert body == %{"payment_token" => "token-do-cartao-novo"}
      Req.Test.json(conn, %{"code" => 200, "data" => %{"subscription_id" => 8008}})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/subscription/8008/history", fn conn, body ->
      assert body == %{"description" => "Cliente trocou o cartão pelo app"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:put, "#{@host}/v1/subscription/8008/cancel", fn conn, _body ->
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:get, "#{@host}/v1/subscription/8008", fn conn, _body ->
      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"subscription_id" => 8008, "status" => "canceled"}
      })
    end)

    assert {:ok, %{"data" => %{"subscription_id" => 8008, "status" => "active"}}} =
             Subscription.create_one_step(client, 7007, %{
               "items" => [%{"name" => "Clube de escova", "value" => 9_900, "amount" => 1}],
               "payment" => %{
                 "credit_card" => %{
                   "customer" => @customer,
                   "payment_token" => "token-do-cartao",
                   "trial_days" => 7
                 }
               }
             })

    assert {:ok, %{"data" => %{"subscription_id" => 8008}}} =
             Subscription.update(client, 8008, %{"payment_token" => "token-do-cartao-novo"})

    assert {:ok, %{"code" => 200}} =
             Subscription.add_history(client, 8008, %{
               "description" => "Cliente trocou o cartão pelo app"
             })

    assert {:ok, %{"code" => 200}} = Subscription.cancel(client, 8008)

    assert {:ok, %{"data" => %{"status" => "canceled"}}} = Subscription.get(client, 8008)
  end

  test "subscribes a customer by boleto in two steps and points its notifications to the app" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:post, "#{@host}/v1/plan/7007/subscription", fn conn, body ->
      assert body == %{
               "items" => [%{"name" => "Clube de escova", "value" => 9_900, "amount" => 1}]
             }

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"subscription_id" => 8009, "status" => "new"}
      })
    end)

    Efi.Test.expect(:post, "#{@host}/v1/subscription/8009/pay", fn conn, body ->
      assert body["payment"]["banking_billet"]["expire_at"] == "2026-12-10"

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"subscription_id" => 8009, "status" => "active"}
      })
    end)

    Efi.Test.expect(:put, "#{@host}/v1/subscription/8009/metadata", fn conn, body ->
      assert body == %{
               "notification_url" => "https://app.example.com/efi/notificacoes",
               "custom_id" => "assinatura-15"
             }

      Req.Test.json(conn, %{"code" => 200})
    end)

    assert {:ok, %{"data" => %{"subscription_id" => 8009, "status" => "new"}}} =
             Subscription.create(client, 7007, %{
               "items" => [%{"name" => "Clube de escova", "value" => 9_900, "amount" => 1}]
             })

    assert {:ok, %{"data" => %{"status" => "active"}}} =
             Subscription.set_payment_method(client, 8009, %{
               "payment" => %{
                 "banking_billet" => %{"customer" => @customer, "expire_at" => "2026-12-10"}
               }
             })

    assert {:ok, %{"code" => 200}} =
             Subscription.update_metadata(client, 8009, %{
               "notification_url" => "https://app.example.com/efi/notificacoes",
               "custom_id" => "assinatura-15"
             })
  end

  test "subscribes a customer through a payment link and resends the link by e-mail" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:post, "#{@host}/v1/plan/7007/subscription/one-step/link", fn conn, body ->
      assert body["settings"] == %{"payment_method" => "all", "expire_at" => "2026-12-20"}

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{
          "subscription_id" => 8010,
          "status" => "new",
          "charge" => %{"id" => 9010, "status" => "link"},
          "payment_url" => "https://pagamento.gerencianet.com.br/identificador-do-link"
        }
      })
    end)

    Efi.Test.expect(:post, "#{@host}/v1/charge/9010/subscription/resend", fn conn, body ->
      assert body == %{"email" => "cliente@app.example.com"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    assert {:ok, %{"data" => %{"charge" => %{"id" => charge_id}, "payment_url" => _url}}} =
             Subscription.create_with_payment_link(client, 7007, %{
               "items" => [%{"name" => "Clube de escova", "value" => 9_900, "amount" => 1}],
               "settings" => %{"payment_method" => "all", "expire_at" => "2026-12-20"}
             })

    assert {:ok, %{"code" => 200}} =
             Subscription.resend_link(client, charge_id, %{"email" => "cliente@app.example.com"})
  end
end
