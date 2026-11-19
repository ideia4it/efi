defmodule Efi.Sandbox.ChargesTest do
  use ExUnit.Case, async: false

  alias Efi.Charges.Charge
  alias Efi.Test.Sandbox

  @moduletag :sandbox
  @moduletag timeout: :timer.minutes(2)

  test "creates a charge on Cobranças without a certificate, reads it back and cancels it" do
    client = Sandbox.client(certificate: nil)

    assert {:ok, %{"data" => %{"charge_id" => charge_id, "status" => "new"}}} =
             Charge.create(client, %{
               "items" => [%{"name" => "Corte e escova", "value" => 5000, "amount" => 1}],
               "metadata" => %{"custom_id" => "teste-da-biblioteca-efi"}
             })

    assert {:ok, %{"data" => %{"charge_id" => ^charge_id, "total" => 5000}}} =
             Charge.get(client, charge_id)

    assert {:ok, %{"code" => 200}} = Charge.cancel(client, charge_id)

    assert {:ok, %{"data" => %{"status" => "canceled"}}} = Charge.get(client, charge_id)
  end
end
