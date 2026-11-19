defmodule Efi.OpenFinance.ParticipantTest do
  use ExUnit.Case, async: true

  alias Efi.OpenFinance.Participant

  setup {Req.Test, :verify_on_exit!}

  @participant_id "9f4cd202-8f2b-11ec-b909-0242ac120002"

  test "lists every active bank, narrows to the ones that offer payments and reports an unknown bank name as not found" do
    client = Efi.Test.client()

    Efi.Test.expect(:get, "openfinance-h.api.efipay.com.br/v1/participantes", fn conn, _body ->
      assert conn.query_params == %{}

      Req.Test.json(conn, %{
        "participantes" => [
          %{"identificador" => @participant_id, "nome" => "Banco do Pagador"},
          %{"identificador" => "0d1c2b3a-4f5e-6d7c-8b9a-0f1e2d3c4b5a", "nome" => "Outro Banco"}
        ]
      })
    end)

    Efi.Test.expect(:get, "openfinance-h.api.efipay.com.br/v1/participantes", fn conn, _body ->
      assert conn.query_params == %{"modalidade" => "pagamentos", "tipoPessoa" => "PF"}

      Req.Test.json(conn, %{
        "participantes" => [
          %{
            "identificador" => @participant_id,
            "nome" => "Banco do Pagador",
            "logo" => "https://app.example.com/logo.png"
          }
        ]
      })
    end)

    Efi.Test.expect(:get, "openfinance-h.api.efipay.com.br/v1/participantes", fn conn, _body ->
      assert conn.query_params == %{"nome" => "Banco Inexistente"}

      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{
        "nome" => "participante_nao_encontrado",
        "mensagem" => "Nenhum participante encontrado"
      })
    end)

    assert {:ok, %{"participantes" => [_payer_bank, _other_bank]}} = Participant.list(client)

    assert {:ok, %{"participantes" => [%{"identificador" => @participant_id}]}} =
             Participant.list(client,
               params: %{"modalidade" => "pagamentos", "tipoPessoa" => "PF"}
             )

    assert {:error,
            %Efi.Error{
              kind: :not_found,
              status: 404,
              name: "participante_nao_encontrado",
              message: "Nenhum participante encontrado"
            }} = Participant.list(client, params: %{"nome" => "Banco Inexistente"})
  end
end
