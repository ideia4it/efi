defmodule Efi.Pix.Automatic.RecurrenceRequestTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Automatic.RecurrenceRequest

  setup {Req.Test, :verify_on_exit!}

  @recurrence_id "RR1234567820261119studioana001"
  @request_id "SC1234567820261119studioana001"

  test "sends the authorization to the payer's banking app, follows it and cancels it before the payer answers" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/solicrec", fn conn, body ->
      assert body == %{
               "idRec" => @recurrence_id,
               "calendario" => %{"dataExpiracaoSolicitacao" => "2026-11-26T12:00:00Z"},
               "destinatario" => %{
                 "cpf" => "12345678909",
                 "agencia" => "0001",
                 "conta" => "123456",
                 "ispbParticipante" => "12345678"
               }
             }

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{
        "idSolicRec" => @request_id,
        "idRec" => @recurrence_id,
        "status" => "CRIADA"
      })
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/solicrec/#{@request_id}", fn conn, _body ->
      Req.Test.json(conn, %{
        "idSolicRec" => @request_id,
        "status" => "RECEBIDA",
        "recPayload" => %{"idRec" => @recurrence_id}
      })
    end)

    Efi.Test.expect(:patch, "pix-h.api.efipay.com.br/v2/solicrec/#{@request_id}", fn conn, body ->
      assert body == %{"status" => "CANCELADA"}

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{"idSolicRec" => @request_id, "status" => "CANCELADA"})
    end)

    assert {:ok, %{"idSolicRec" => @request_id, "status" => "CRIADA"}} =
             RecurrenceRequest.create(client, %{
               "idRec" => @recurrence_id,
               "calendario" => %{"dataExpiracaoSolicitacao" => "2026-11-26T12:00:00Z"},
               "destinatario" => %{
                 "cpf" => "12345678909",
                 "agencia" => "0001",
                 "conta" => "123456",
                 "ispbParticipante" => "12345678"
               }
             })

    assert {:ok, %{"status" => "RECEBIDA", "recPayload" => %{"idRec" => @recurrence_id}}} =
             RecurrenceRequest.get(client, @request_id)

    assert {:ok, %{"status" => "CANCELADA"}} =
             RecurrenceRequest.update(client, @request_id, %{"status" => "CANCELADA"})
  end

  test "refuses to cancel a request the payer already answered" do
    client = Efi.Test.client()

    Efi.Test.expect(:patch, "pix-h.api.efipay.com.br/v2/solicrec/#{@request_id}", fn conn, body ->
      assert body == %{"status" => "CANCELADA"}

      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "type" => "https://pix.bcb.gov.br/api/v2/error/SolicRecOperacaoInvalida",
        "title" => "Operação inválida.",
        "status" => 400,
        "detail" =>
          "Não é possível cancelar uma solicitação de recorrência com o status diferente de CRIADA ou RECEBIDA."
      })
    end)

    assert {:error, %Efi.Error{kind: :validation, name: "SolicRecOperacaoInvalida"}} =
             RecurrenceRequest.update(client, @request_id, %{"status" => "CANCELADA"})
  end
end
