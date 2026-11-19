defmodule Efi.Pix.SendTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Send

  setup {Req.Test, :verify_on_exit!}

  @send_id "studioana0000000000000000001"
  @e2e_id "E09089356202611191226APIff82f2e5"

  @transfer %{
    "valor" => "8.50",
    "pagador" => %{"chave" => "chave-pix-do-studio-ana", "infoPagador" => "Repasse de novembro"},
    "favorecido" => %{"chave" => "efipay@sejaefi.com.br"}
  }

  test "sends a Pix that fails mid-way, finds no trace of it by idEnvio, resends with the same idEnvio and sees it settled in the day's list" do
    client = Efi.Test.client()

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v3/gn/pix/#{@send_id}", fn conn, body ->
      assert body == @transfer

      conn
      |> Plug.Conn.put_status(500)
      |> Req.Test.json(%{
        "nome" => "erro_aplicacao",
        "mensagem" => "Ocorreu um erro ao validar a chave"
      })
    end)

    Efi.Test.expect(
      :get,
      "pix-h.api.efipay.com.br/v2/gn/pix/enviados/id-envio/#{@send_id}",
      fn conn, _body ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{
          "type" => "https://pix.bcb.gov.br/api/v2/error/PixEnviadoNaoEncontrado",
          "title" => "Não Encontrado",
          "status" => 404,
          "detail" => "Pix enviado não encontrado para o idEnvio informado."
        })
      end
    )

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v3/gn/pix/#{@send_id}", fn conn, body ->
      assert body == @transfer

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{
        "idEnvio" => @send_id,
        "e2eId" => @e2e_id,
        "valor" => "8.50",
        "status" => "EM_PROCESSAMENTO"
      })
    end)

    Efi.Test.expect(
      :get,
      "pix-h.api.efipay.com.br/v2/gn/pix/enviados/#{@e2e_id}",
      fn conn, _body ->
        Req.Test.json(conn, %{
          "endToEndId" => @e2e_id,
          "idEnvio" => @send_id,
          "status" => "REALIZADO"
        })
      end
    )

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/pix/enviados", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-19T00:00:00Z",
               "fim" => "2026-11-19T23:59:59Z"
             }

      Req.Test.json(conn, %{"pix" => [%{"endToEndId" => @e2e_id, "status" => "REALIZADO"}]})
    end)

    assert {:error, %Efi.Error{kind: :server, status: 500, name: "erro_aplicacao"}} =
             Send.send(client, @send_id, @transfer)

    assert {:error, %Efi.Error{kind: :not_found, name: "PixEnviadoNaoEncontrado"}} =
             Send.get_by_send_id(client, @send_id)

    assert {:ok, %{"e2eId" => @e2e_id, "status" => "EM_PROCESSAMENTO"}} =
             Send.send(client, @send_id, @transfer)

    assert {:ok, %{"status" => "REALIZADO"}} = Send.get(client, @e2e_id)

    assert {:ok, %{"pix" => [%{"endToEndId" => @e2e_id}]}} =
             Send.list(client, %{
               "inicio" => "2026-11-19T00:00:00Z",
               "fim" => "2026-11-19T23:59:59Z"
             })
  end

  test "moves money to another account of the same owner and is told when the idEnvio was already used" do
    client = Efi.Test.client()
    path = "pix-h.api.efipay.com.br/v2/gn/pix/#{@send_id}/mesma-titularidade"

    Efi.Test.expect(:put, path, fn conn, body ->
      assert body["favorecido"] == %{"chave" => "outra-chave-do-studio-ana"}

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"idEnvio" => @send_id, "status" => "EM_PROCESSAMENTO"})
    end)

    Efi.Test.expect(:put, path, fn conn, _body ->
      conn
      |> Plug.Conn.put_status(409)
      |> Req.Test.json(%{
        "type" => "https://pix.example.com/EnvioPixOperacaoInvalida",
        "title" => "Operação Inválida",
        "status" => 409,
        "detail" => "A requisição que busca enviar um pix não respeita o schema.",
        "violacoes" => [%{"propriedade" => "params.idEnvio"}]
      })
    end)

    same_owner_transfer = %{
      "valor" => "200.00",
      "pagador" => %{"chave" => "chave-pix-do-studio-ana"},
      "favorecido" => %{"chave" => "outra-chave-do-studio-ana"}
    }

    assert {:ok, %{"status" => "EM_PROCESSAMENTO"}} =
             Send.send_to_same_owner(client, @send_id, same_owner_transfer)

    assert {:error, %Efi.Error{kind: :conflict, name: "EnvioPixOperacaoInvalida"}} =
             Send.send_to_same_owner(client, @send_id, same_owner_transfer)
  end

  test "reads what a QR Code charges before paying it" do
    client = Efi.Test.client()
    copy_and_paste = "00020101021226830014BR.GOV.BCB.PIX2561qrcodespix.example.com/v2/cobv"

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/gn/qrcodes/detalhar", fn conn, body ->
      assert body == %{"pixCopiaECola" => copy_and_paste}
      Req.Test.json(conn, %{"valor" => %{"original" => "35.00"}})
    end)

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/gn/pix/#{@send_id}/qrcode", fn conn, body ->
      assert body == %{
               "pagador" => %{"chave" => "chave-pix-do-studio-ana"},
               "pixCopiaECola" => copy_and_paste
             }

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{
        "idEnvio" => @send_id,
        "valor" => "35.00",
        "status" => "EM_PROCESSAMENTO"
      })
    end)

    assert {:ok, %{"valor" => %{"original" => "35.00"}}} =
             Send.detail_qr_code(client, %{"pixCopiaECola" => copy_and_paste})

    assert {:ok, %{"valor" => "35.00", "status" => "EM_PROCESSAMENTO"}} =
             Send.pay_qr_code(client, @send_id, %{
               "pagador" => %{"chave" => "chave-pix-do-studio-ana"},
               "pixCopiaECola" => copy_and_paste
             })
  end
end
