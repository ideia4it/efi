defmodule Efi.Pix.ReportTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Report

  setup {Req.Test, :verify_on_exit!}

  @report_id "b02c2b3a-0ab2-4ab5-bc8e-b3ce607e7829"

  test "requests yesterday's reconciliation statement, polls while it is processing and downloads the CSV" do
    client = Efi.Test.client()

    csv =
      "CA;Efi;364;1;517613;Studio Ana;2026-11-19;2026-11-18;Extrato de Conciliação API Pix;1.0\n"

    Efi.Test.expect(
      :post,
      "pix-h.api.efipay.com.br/v2/gn/relatorios/extrato-conciliacao",
      fn conn, body ->
        assert body == %{
                 "dataMovimento" => "2026-11-18",
                 "tipoRegistros" => %{"pixRecebido" => true}
               }

        conn
        |> Plug.Conn.put_status(202)
        |> Req.Test.json(%{"id" => @report_id, "status" => "AGUARDANDO_PROCESSAMENTO"})
      end
    )

    report_url = "pix-h.api.efipay.com.br/v2/gn/relatorios/#{@report_id}"

    Efi.Test.expect(:get, report_url, fn conn, _body ->
      conn
      |> Plug.Conn.put_status(202)
      |> Req.Test.json(%{"id" => @report_id, "status" => "EM_PROCESSAMENTO"})
    end)

    Efi.Test.expect(:get, report_url, fn conn, _body ->
      conn
      |> Plug.Conn.put_resp_content_type("text/csv")
      |> Plug.Conn.send_resp(200, csv)
    end)

    assert {:ok, %{"id" => @report_id, "status" => "AGUARDANDO_PROCESSAMENTO"}} =
             Report.create_reconciliation(client, %{
               "dataMovimento" => "2026-11-18",
               "tipoRegistros" => %{"pixRecebido" => true}
             })

    assert {:ok, %{"status" => "EM_PROCESSAMENTO"}} = Report.get(client, @report_id)
    assert {:ok, ^csv} = Report.get(client, @report_id)
  end
end
