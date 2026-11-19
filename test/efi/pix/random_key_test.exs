defmodule Efi.Pix.RandomKeyTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.RandomKey

  setup {Req.Test, :verify_on_exit!}

  @key "345e4568-e89b-12d3-a456-006655440001"

  test "creates a random key, finds it in the list, removes it and is told it is gone when removing again" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/gn/evp", fn conn, body ->
      assert body == nil

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"chave" => @key})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/evp", fn conn, _body ->
      Req.Test.json(conn, %{"chaves" => [@key]})
    end)

    Efi.Test.expect(:delete, "pix-h.api.efipay.com.br/v2/gn/evp/#{@key}", fn conn, _body ->
      Plug.Conn.send_resp(conn, 200, "")
    end)

    Efi.Test.expect(:delete, "pix-h.api.efipay.com.br/v2/gn/evp/#{@key}", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "nome" => "chave_nao_encontrada",
        "mensagem" => "A chave informada não foi encontrada"
      })
    end)

    assert {:ok, %{"chave" => @key}} = RandomKey.create(client)
    assert {:ok, %{"chaves" => [@key]}} = RandomKey.list(client)
    assert {:ok, nil} = RandomKey.delete(client, @key)

    assert {:error, %Efi.Error{kind: :validation, name: "chave_nao_encontrada"}} =
             RandomKey.delete(client, @key)
  end
end
