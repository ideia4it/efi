defmodule Efi.Pix.InfractionTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Infraction

  setup {Req.Test, :verify_on_exit!}

  @defended "8ad75c93-6150-422c-929e-822f361c7a6b"
  @expired "1f0c2d4e-6150-422c-929e-822f361c7a6b"

  test "lists the month's MED infractions, defends one and is told the deadline passed for another" do
    client = Efi.Test.client()

    defense = %{
      "analise" => "rejeitado",
      "justificativa" => "Serviço prestado no Studio Ana com agendamento confirmado."
    }

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/infracoes", fn conn, _body ->
      assert conn.query_params == %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z"
             }

      Req.Test.json(conn, %{
        "infracoes" => [
          %{"idInfracao" => @defended, "status" => "ABERTA"},
          %{"idInfracao" => @expired, "status" => "ABERTA"}
        ]
      })
    end)

    Efi.Test.expect(
      :post,
      "pix-h.api.efipay.com.br/v2/gn/infracoes/#{@defended}/defesa",
      fn conn, body ->
        assert body == defense
        Plug.Conn.send_resp(conn, 201, "")
      end
    )

    Efi.Test.expect(
      :post,
      "pix-h.api.efipay.com.br/v2/gn/infracoes/#{@expired}/defesa",
      fn conn, _body ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{
          "type" => "https://pix.bcb.gov.br/api/v2/error/InfracaoOperacaoInvalida",
          "title" => "Operação Inválida",
          "status" => 422,
          "detail" =>
            "A requisição que busca apresentar uma defesa de infração não respeita o schema ou está semanticamente errada.",
          "violacoes" => [
            %{
              "razao" => "O prazo para defesa foi excedido.",
              "propriedade" => "body.infractionId"
            }
          ]
        })
      end
    )

    assert {:ok, %{"infracoes" => [%{"idInfracao" => @defended}, %{"idInfracao" => @expired}]}} =
             Infraction.list(client, %{
               "inicio" => "2026-11-01T00:00:00Z",
               "fim" => "2026-11-30T23:59:59Z"
             })

    assert {:ok, nil} = Infraction.submit_defense(client, @defended, defense)

    assert {:error,
            %Efi.Error{
              kind: :validation,
              status: 422,
              name: "InfracaoOperacaoInvalida",
              body: body
            }} =
             Infraction.submit_defense(client, @expired, defense)

    assert [%{"razao" => "O prazo para defesa foi excedido."}] = body["violacoes"]
  end
end
