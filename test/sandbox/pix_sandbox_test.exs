defmodule Efi.Sandbox.PixTest do
  use ExUnit.Case, async: false

  alias Efi.Pix.ImmediateCharge
  alias Efi.Pix.Location
  alias Efi.Test.Sandbox

  @moduletag :sandbox
  @moduletag timeout: :timer.minutes(2)

  test "opens a charge on the sandbox, reads it back, renders its QR Code and finds it in the list" do
    client = Sandbox.client()
    txid = Sandbox.txid()

    assert {:ok, %{"txid" => ^txid, "status" => "ATIVA", "loc" => %{"id" => location_id}}} =
             ImmediateCharge.create_with_txid(client, txid, %{
               "calendario" => %{"expiracao" => 3600},
               "valor" => %{"original" => "1.00"},
               "chave" => Sandbox.pix_key(),
               "solicitacaoPagador" => "Teste da biblioteca efi"
             })

    assert {:error, %Efi.Error{kind: :conflict}} =
             ImmediateCharge.create_with_txid(client, txid, %{
               "calendario" => %{"expiracao" => 3600},
               "valor" => %{"original" => "1.00"},
               "chave" => Sandbox.pix_key()
             })

    assert {:ok, %{"txid" => ^txid, "pixCopiaECola" => copy_paste}} =
             ImmediateCharge.get(client, txid)

    assert is_binary(copy_paste)

    assert {:ok, %{"imagemQrcode" => "data:image/png;base64," <> _png}} =
             Location.get_qr_code(client, location_id)

    now = DateTime.utc_now()

    assert {:ok, %{"cobs" => charges}} =
             ImmediateCharge.list(client, %{
               "inicio" => now |> DateTime.add(-1, :hour) |> DateTime.to_iso8601(),
               "fim" => now |> DateTime.add(1, :hour) |> DateTime.to_iso8601()
             })

    assert Enum.any?(charges, &(&1["txid"] == txid))

    assert {:ok, %{"status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"}} =
             ImmediateCharge.update(client, txid, %{"status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"})
  end
end
