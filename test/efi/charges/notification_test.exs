defmodule Efi.Charges.NotificationTest do
  use ExUnit.Case, async: true

  alias Efi.Charges.Notification

  setup {Req.Test, :verify_on_exit!}

  @token "09027955-5e06-4ff0-a9c7-46b47b8f1b27"

  test "reads every status change behind the token Efí posted to the notification URL" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:get, "cobrancas-h.api.efipay.com.br/v1/notification/#{@token}", fn conn,
                                                                                        _body ->
      Req.Test.json(conn, %{
        "code" => 200,
        "data" => [
          %{
            "id" => 1,
            "type" => "charge",
            "identifiers" => %{"charge_id" => 1001},
            "status" => %{"current" => "waiting", "previous" => "new"}
          },
          %{
            "id" => 2,
            "type" => "charge",
            "identifiers" => %{"charge_id" => 1001},
            "status" => %{"current" => "paid", "previous" => "waiting"},
            "value" => 8900,
            "received_by_bank_at" => "2026-11-19"
          }
        ]
      })
    end)

    assert {:ok, %{"data" => [_waiting, %{"id" => 2, "status" => %{"current" => "paid"}}]}} =
             Notification.get(client, @token)
  end
end
