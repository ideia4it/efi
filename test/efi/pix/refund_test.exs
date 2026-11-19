defmodule Efi.Pix.RefundTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Refund

  setup {Req.Test, :verify_on_exit!}

  @e2e_id "E12345678202611191200abcdef12345"
  @refund_id "devolucaoStudioAna1"
  @refund_url "pix-h.api.efipay.com.br/v2/pix/#{@e2e_id}/devolucao/#{@refund_id}"

  test "refunds part of a payment, follows it until settled and refuses the same refund id twice" do
    client = Efi.Test.client()

    Efi.Test.expect(:put, @refund_url, fn conn, body ->
      assert body == %{"valor" => "20.00"}

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"id" => @refund_id, "valor" => "20.00", "status" => "EM_PROCESSAMENTO"})
    end)

    Efi.Test.expect(:get, @refund_url, fn conn, _body ->
      Req.Test.json(conn, %{"id" => @refund_id, "valor" => "20.00", "status" => "DEVOLVIDO"})
    end)

    Efi.Test.expect(:put, @refund_url, fn conn, _body ->
      conn
      |> Plug.Conn.put_status(409)
      |> Req.Test.json(%{
        "nome" => "devolucao_id_duplicado",
        "mensagem" => "O id informado já foi utilizado em outra devolução"
      })
    end)

    assert {:ok, %{"status" => "EM_PROCESSAMENTO"}} =
             Refund.create(client, @e2e_id, @refund_id, %{"valor" => "20.00"})

    assert {:ok, %{"status" => "DEVOLVIDO"}} = Refund.get(client, @e2e_id, @refund_id)

    assert {:error, %Efi.Error{kind: :conflict, status: 409, name: "devolucao_id_duplicado"}} =
             Refund.create(client, @e2e_id, @refund_id, %{"valor" => "20.00"})
  end
end
