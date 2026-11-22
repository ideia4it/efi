defmodule Efi.Pix.Automatic.RecurrenceTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Automatic.Recurrence

  setup {Req.Test, :verify_on_exit!}

  @recurrence_id "RR1234567820261119studioana001"
  @immediate_txid "studioana0000000000000000001"

  test "signs a customer up with a QR Code that also pays the first month, fixes the payer's name, sees the approval and finds the plan in the month's list" do
    client = Efi.Test.client()

    plan = %{
      "vinculo" => %{
        "contrato" => "plano-mensal-0001",
        "devedor" => %{"cpf" => "12345678909", "nome" => "Cliente do Studio Ana"},
        "objeto" => "Plano mensal de escova"
      },
      "calendario" => %{"dataInicial" => "2026-12-01", "periodicidade" => "MENSAL"},
      "valor" => %{"valorRec" => "150.00"},
      "politicaRetentativa" => "PERMITE_3R_7D",
      "loc" => 108,
      "ativacao" => %{"dadosJornada" => %{"txid" => @immediate_txid}}
    }

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/rec", fn conn, body ->
      assert body == plan

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{
        "idRec" => @recurrence_id,
        "status" => "CRIADA",
        "loc" => %{"id" => 108, "idRec" => @recurrence_id},
        "ativacao" => %{"dadosJornada" => %{"tipoJornada" => "JORNADA_3"}}
      })
    end)

    Efi.Test.expect(:patch, "pix-h.api.efipay.com.br/v2/rec/#{@recurrence_id}", fn conn, body ->
      assert body == %{"vinculo" => %{"devedor" => %{"nome" => "Cliente Fiel do Studio Ana"}}}

      Req.Test.json(conn, %{
        "idRec" => @recurrence_id,
        "vinculo" => %{"devedor" => %{"nome" => "Cliente Fiel do Studio Ana"}}
      })
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/rec/#{@recurrence_id}", fn conn, _body ->
      assert conn.query_params == %{"txid" => @immediate_txid}

      Req.Test.json(conn, %{
        "idRec" => @recurrence_id,
        "status" => "CRIADA",
        "dadosQR" => %{"jornada" => "JORNADA_3", "pixCopiaECola" => "00020126copiaecola"}
      })
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/rec/#{@recurrence_id}", fn conn, _body ->
      assert conn.query_params == %{}
      Req.Test.json(conn, %{"idRec" => @recurrence_id, "status" => "APROVADA"})
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/rec", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z",
               "cpf" => "12345678909"
             }

      Req.Test.json(conn, %{"recs" => [%{"idRec" => @recurrence_id, "status" => "APROVADA"}]})
    end)

    assert {:ok, %{"idRec" => @recurrence_id, "status" => "CRIADA"}} =
             Recurrence.create(client, plan)

    assert {:ok, %{"vinculo" => %{"devedor" => %{"nome" => "Cliente Fiel do Studio Ana"}}}} =
             Recurrence.update(client, @recurrence_id, %{
               "vinculo" => %{"devedor" => %{"nome" => "Cliente Fiel do Studio Ana"}}
             })

    assert {:ok, %{"dadosQR" => %{"pixCopiaECola" => "00020126copiaecola"}}} =
             Recurrence.get(client, @recurrence_id, params: %{"txid" => @immediate_txid})

    assert {:ok, %{"status" => "APROVADA"}} = Recurrence.get(client, @recurrence_id)

    assert {:ok, %{"recs" => [%{"idRec" => @recurrence_id, "status" => "APROVADA"}]}} =
             Recurrence.list(client, %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z",
               "cpf" => "12345678909"
             })
  end

  test "reports a recurrence that breaks the schema with the Central Bank error name and the violated field" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/rec", fn conn, body ->
      assert body == %{
               "calendario" => %{"dataInicial" => "01/12/2026", "periodicidade" => "MENSAL"}
             }

      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{
        "type" => "https://pix.bcb.gov.br/api/v2/error/RecOperacaoInvalida",
        "title" => "Operação inválida.",
        "status" => 400,
        "detail" => "A recorrência não respeita o schema.",
        "violacoes" => [
          %{
            "razao" => "O campo rec.calendario.dataInicial não respeita o schema.",
            "propriedade" => "rec.calendario.dataInicial"
          }
        ]
      })
    end)

    assert {:error,
            %Efi.Error{
              kind: :validation,
              status: 400,
              name: "RecOperacaoInvalida",
              message: "A recorrência não respeita o schema.",
              body: %{"violacoes" => [%{"propriedade" => "rec.calendario.dataInicial"}]}
            }} =
             Recurrence.create(client, %{
               "calendario" => %{"dataInicial" => "01/12/2026", "periodicidade" => "MENSAL"}
             })
  end
end
