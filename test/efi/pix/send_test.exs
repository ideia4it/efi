defmodule Efi.Pix.SendTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Send

  setup {Req.Test, :verify_on_exit!}

  @send_id "studioana0000000000000000001"
  @other_send_id "studioana0000000000000000002"
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

  test "finds the token bucket empty and reads from the error how many seconds to wait before sending again" do
    client = Efi.Test.client()

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v3/gn/pix/#{@send_id}", fn conn, body ->
      assert body == @transfer

      conn
      |> Plug.Conn.put_resp_header("bucket-size", "0")
      |> Plug.Conn.put_resp_header("retry-after", "30")
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{
        "nome" => "balde_fichas_vazio",
        "mensagem" => "Não há fichas no balde a serem consumidas"
      })
    end)

    assert {:error, %Efi.Error{kind: :rate_limited, name: "balde_fichas_vazio"} = error} =
             Send.send(client, @send_id, @transfer)

    assert error.headers["retry-after"] == ["30"]
    assert error.headers["bucket-size"] == ["0"]
  end

  test "moves money to another account of the same owner, is told when its idEnvio is reused for another transfer and is refused a key of someone else" do
    client = Efi.Test.client()
    path = "pix-h.api.efipay.com.br/v2/gn/pix/#{@send_id}/mesma-titularidade"

    to_own_account = %{
      "valor" => "200.00",
      "pagador" => %{"chave" => "chave-pix-do-studio-ana"},
      "favorecido" => %{"chave" => "outra-chave-do-studio-ana"}
    }

    another_transfer = Map.put(to_own_account, "valor", "150.00")

    to_someone_else =
      Map.put(to_own_account, "favorecido", %{"chave" => "chave-pix-de-outra-pessoa"})

    Efi.Test.expect(:put, path, fn conn, body ->
      assert body == to_own_account

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{
        "idEnvio" => @send_id,
        "e2eId" => @e2e_id,
        "valor" => "200.00",
        "status" => "EM_PROCESSAMENTO"
      })
    end)

    Efi.Test.expect(:put, path, fn conn, body ->
      assert body == another_transfer

      conn
      |> Plug.Conn.put_status(409)
      |> Req.Test.json(%{
        "type" => "https://pix.example.com/EnvioPixOperacaoInvalida",
        "title" => "Operação Inválida",
        "status" => 409,
        "detail" =>
          "A requisição que busca enviar um pix não respeita o schema ou está semanticamente errada.",
        "violacoes" => [
          %{
            "razao" => "O parâmetro idEnvio informado já foi utilizado em outro pagamento.",
            "propriedade" => "params.idEnvio"
          }
        ]
      })
    end)

    Efi.Test.expect(
      :put,
      "pix-h.api.efipay.com.br/v2/gn/pix/#{@other_send_id}/mesma-titularidade",
      fn conn, body ->
        assert body == to_someone_else

        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{
          "type" => "https://pix.example.com/EnvioPixOperacaoInvalida",
          "title" => "Operação Inválida",
          "status" => 400,
          "detail" =>
            "A requisição que busca enviar um pix não respeita o schema ou está semanticamente errada.",
          "violacoes" => [
            %{
              "razao" => "O documento da chave do favorecido não é da mesma titularidade.",
              "propriedade" => "body.pix.favorecido.chave"
            }
          ]
        })
      end
    )

    assert {:ok, %{"e2eId" => @e2e_id, "status" => "EM_PROCESSAMENTO"}} =
             Send.send_to_same_owner(client, @send_id, to_own_account)

    assert {:error, %Efi.Error{kind: :conflict, name: "EnvioPixOperacaoInvalida"}} =
             Send.send_to_same_owner(client, @send_id, another_transfer)

    assert {:error, %Efi.Error{kind: :validation, body: %{"violacoes" => [violation]}}} =
             Send.send_to_same_owner(client, @other_send_id, to_someone_else)

    assert violation["propriedade"] == "body.pix.favorecido.chave"
  end

  test "is refused a static QR Code, reads what a dynamic one charges and pays it" do
    client = Efi.Test.client()

    static_copy_and_paste =
      "00020101021126360014BR.GOV.BCB.PIX0114chave-estatica5204000053039865802BR"

    copy_and_paste = "00020101021226830014BR.GOV.BCB.PIX2561qrcodespix.example.com/v2/studioana"
    detail_url = "pix-h.api.efipay.com.br/v2/gn/qrcodes/detalhar"

    Efi.Test.expect(:post, detail_url, fn conn, body ->
      assert body == %{"pixCopiaECola" => static_copy_and_paste}

      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "type" => "https://pix.bcb.gov.br/api/v2/error/QrcodeOperacaoInvalida",
        "title" => "Operação Inválida",
        "status" => 400,
        "detail" =>
          "A requisição que busca pagar um qrcode não respeita o schema ou está semanticamente errada.",
        "violacoes" => [
          %{
            "razao" => "O pixCopiaECola informado é referente a uma cobrança estática",
            "propriedade" => "qrcode.pixCopiaECola"
          }
        ]
      })
    end)

    Efi.Test.expect(:post, detail_url, fn conn, body ->
      assert body == %{"pixCopiaECola" => copy_and_paste}

      Req.Test.json(conn, %{
        "tipoCob" => "cob",
        "txid" => "studioana0000000000000000035",
        "status" => "ATIVA",
        "recebedor" => %{"nome" => "Studio Ana", "cnpj" => "11.222.***/****-81"},
        "valor" => %{"final" => "35.00"}
      })
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
        "e2eId" => @e2e_id,
        "valor" => "35.00",
        "status" => "EM_PROCESSAMENTO"
      })
    end)

    assert {:error, %Efi.Error{kind: :validation, name: "QrcodeOperacaoInvalida"}} =
             Send.detail_qr_code(client, %{"pixCopiaECola" => static_copy_and_paste})

    assert {:ok, %{"tipoCob" => "cob", "status" => "ATIVA", "valor" => %{"final" => "35.00"}}} =
             Send.detail_qr_code(client, %{"pixCopiaECola" => copy_and_paste})

    assert {:ok, %{"valor" => "35.00", "status" => "EM_PROCESSAMENTO"}} =
             Send.pay_qr_code(client, @send_id, %{
               "pagador" => %{"chave" => "chave-pix-do-studio-ana"},
               "pixCopiaECola" => copy_and_paste
             })
  end
end
