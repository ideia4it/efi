defmodule Efi.Pix.Automatic.LocationTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Automatic.Location

  setup {Req.Test, :verify_on_exit!}

  @recurrence_id "RR1234567820261119studioana001"
  @location_url "pix.example.com/qr/v2/rec/studioana0000000000000000001"

  test "creates a QR Code location, sees it linked to the recurrence, finds it in the day's list and unlinks it" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/locrec", fn conn, body ->
      assert body == nil

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"id" => 12_069, "location" => @location_url})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/locrec/12069", fn conn, _body ->
      Req.Test.json(conn, %{"id" => 12_069, "idRec" => @recurrence_id})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/locrec", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-19T00:00:00Z",
               "fim" => "2026-11-19T23:59:59Z"
             }

      Req.Test.json(conn, %{"loc" => [%{"id" => 12_069, "idRec" => @recurrence_id}]})
    end)

    Efi.Test.expect(:delete, "pix-h.api.efipay.com.br/v2/locrec/12069/idRec", fn conn, _body ->
      Req.Test.json(conn, %{"id" => 12_069, "location" => @location_url})
    end)

    assert {:ok, %{"id" => 12_069, "location" => @location_url}} = Location.create(client)
    assert {:ok, %{"idRec" => @recurrence_id}} = Location.get(client, 12_069)

    assert {:ok, %{"loc" => [%{"id" => 12_069}]}} =
             Location.list(client, %{
               "inicio" => "2026-11-19T00:00:00Z",
               "fim" => "2026-11-19T23:59:59Z"
             })

    assert {:ok, unlinked} = Location.unlink_recurrence(client, 12_069)
    refute Map.has_key?(unlinked, "idRec")
  end
end
