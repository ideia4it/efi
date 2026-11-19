defmodule Efi.Statements.RecurrenceTest do
  use ExUnit.Case, async: true

  alias Efi.Statements.Recurrence

  setup {Req.Test, :verify_on_exit!}

  @host "extratos.api.efipay.com.br"

  test "schedules a daily statement, turns on compression and finds it among the schedules" do
    client = Efi.Test.client(environment: :production)

    Efi.Test.expect(:post, "#{@host}/v1/extrato-cnab/agendar", fn conn, body ->
      assert body == %{
               "periodicidade" => "diario",
               "envia_email" => true,
               "comprimir_arquivos" => false
             }

      Plug.Conn.send_resp(conn, 201, "")
    end)

    Efi.Test.expect(
      :patch,
      "#{@host}/v1/extrato-cnab/agendar/diario",
      fn conn, body ->
        assert body == %{
                 "periodicidade" => "diario",
                 "status" => "ativo",
                 "envia_email" => true,
                 "comprimir_arquivos" => true
               }

        Plug.Conn.send_resp(conn, 201, "")
      end
    )

    Efi.Test.expect(:get, "#{@host}/v1/extrato-cnab/agendamentos", fn conn, _body ->
      Req.Test.json(conn, [
        %{
          "status" => "ativo",
          "periodicidade" => "diario",
          "envia_email" => true,
          "comprimir_arquivos" => true,
          "data_criacao" => "2026-11-19"
        }
      ])
    end)

    assert {:ok, nil} =
             Recurrence.create(client, %{
               "periodicidade" => "diario",
               "envia_email" => true,
               "comprimir_arquivos" => false
             })

    assert {:ok, nil} =
             Recurrence.update(client, "diario", %{
               "periodicidade" => "diario",
               "status" => "ativo",
               "envia_email" => true,
               "comprimir_arquivos" => true
             })

    assert {:ok, [%{"periodicidade" => "diario", "comprimir_arquivos" => true}]} =
             Recurrence.list(client)
  end
end
