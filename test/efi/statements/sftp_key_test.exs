defmodule Efi.Statements.SftpKeyTest do
  use ExUnit.Case, async: true

  alias Efi.Statements.SftpKey

  setup {Req.Test, :verify_on_exit!}

  @host "extratos.api.efipay.com.br"

  test "generates the SFTP key of the account and returns the private key" do
    client = Efi.Test.client(environment: :production)

    Efi.Test.expect(:post, "#{@host}/v1/extrato-cnab/gerar-chaves", fn conn, body ->
      assert body == %{"conta" => 123_456}
      Req.Test.json(conn, %{"privateKey" => "chave-privada-de-teste"})
    end)

    assert {:ok, %{"privateKey" => "chave-privada-de-teste"}} =
             SftpKey.generate(client, %{"conta" => 123_456})
  end
end
