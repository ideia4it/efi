defmodule Efi.Pix.ReceiptTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Receipt

  setup {Req.Test, :verify_on_exit!}

  test "downloads the PDF receipt of a sent Pix by its e2eId" do
    client = Efi.Test.client()
    pdf = "%PDF-1.4 comprovante do Studio Ana"

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/pix/comprovantes", fn conn, _body ->
      assert conn.query_params == %{"e2eId" => "E09089356202611191226APIff82f2e5"}

      conn
      |> Plug.Conn.put_resp_content_type("application/pdf")
      |> Plug.Conn.send_resp(200, pdf)
    end)

    assert {:ok, ^pdf} = Receipt.get(client, %{"e2eId" => "E09089356202611191226APIff82f2e5"})
  end
end
