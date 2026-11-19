defmodule Efi.Statements.CnabFileTest do
  use ExUnit.Case, async: true

  alias Efi.Statements.CnabFile

  setup {Req.Test, :verify_on_exit!}

  @host "extratos-h.api.efipay.com.br"
  @file_name "EFI_00000000_20261118_000000_CNAB_240.txt"

  test "finds yesterday's statement among the generated files and downloads it as it came" do
    client = Efi.Test.client()
    cnab = "36400000         2112223330001810000000000000000000000STUDIO ANA LTDA\r\n"

    Efi.Test.expect(:get, "#{@host}/v1/extrato-cnab/arquivos", fn conn, _body ->
      Req.Test.json(conn, [
        %{
          "nome" => @file_name,
          "data_geracao" => "2026-11-19",
          "periodo_inicio" => "2026-11-18",
          "periodo_fim" => "2026-11-18"
        }
      ])
    end)

    Efi.Test.expect(
      :get,
      "#{@host}/v1/extrato-cnab/download/#{@file_name}",
      fn conn, _body ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, cnab)
      end
    )

    assert {:ok, [%{"nome" => file_name, "periodo_fim" => "2026-11-18"}]} = CnabFile.list(client)
    assert {:ok, ^cnab} = CnabFile.download(client, file_name)
  end

  test "reports a file the Efí cannot find with its message" do
    client = Efi.Test.client()

    Efi.Test.expect(
      :get,
      "#{@host}/v1/extrato-cnab/download/#{@file_name}",
      fn conn, _body ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"mensagem" => "Arquivo não encontrado"})
      end
    )

    assert {:error,
            %Efi.Error{
              kind: :validation,
              status: 400,
              name: nil,
              message: "Arquivo não encontrado"
            }} =
             CnabFile.download(client, @file_name)
  end
end
