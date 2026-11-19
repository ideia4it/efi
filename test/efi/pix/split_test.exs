defmodule Efi.Pix.SplitTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Split

  setup {Req.Test, :verify_on_exit!}

  @txid "studioana0000000000000000001"
  @config_id "comissaodoapp0000000000001"
  @e2e_id "E090893562026111912492e0c4b9b253"

  @partner_share %{
    "descricao" => "Comissão do app nos atendimentos do Studio Ana",
    "lancamento" => %{"imediato" => true},
    "split" => %{
      "divisaoTarifa" => "assumir_total",
      "minhaParte" => %{"tipo" => "porcentagem", "valor" => "95.00"},
      "repasses" => [
        %{
          "tipo" => "porcentagem",
          "valor" => "5.00",
          "favorecido" => %{"cpf" => "12345678909", "conta" => "1234567"}
        }
      ]
    }
  }

  test "gives the partner its share of an immediate charge, keeps the split once paid and refunds the payer from the business account" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "pix-h.api.efipay.com.br/v2/gn/split/config", fn conn, body ->
      assert body == @partner_share

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(Map.merge(@partner_share, %{"id" => @config_id, "status" => "ATIVA"}))
    end)

    Efi.Test.expect(
      :get,
      "pix-h.api.efipay.com.br/v2/gn/split/config/#{@config_id}",
      fn conn, _body ->
        assert conn.query_params == %{"revisao" => "0"}
        Req.Test.json(conn, Map.merge(@partner_share, %{"id" => @config_id, "revisao" => 0}))
      end
    )

    Efi.Test.expect(
      :put,
      "pix-h.api.efipay.com.br/v2/gn/split/cob/#{@txid}/vinculo/#{@config_id}",
      fn conn, body ->
        assert body == nil
        Plug.Conn.send_resp(conn, 204, "")
      end
    )

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/split/cob/#{@txid}", fn conn, _body ->
      Req.Test.json(conn, %{
        "txid" => @txid,
        "status" => "CONCLUIDA",
        "pix" => %{"endToEndId" => @e2e_id, "valor" => "100.00"},
        "config" => %{"id" => @config_id, "status" => "ATIVA"},
        "split" => %{
          "minhaParte" => %{"conta" => "7654321", "valor" => 9500},
          "repasses" => %{"conta" => "1234567", "valor" => 500}
        }
      })
    end)

    Efi.Test.expect(
      :delete,
      "pix-h.api.efipay.com.br/v2/gn/split/cob/#{@txid}/vinculo",
      fn conn, _body ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{
          "type" => "https://pix.bcb.gov.br/api/v2/error/SplitOperacaoInvalida",
          "title" => "Operação inválida",
          "status" => 400,
          "detail" =>
            "A requisição que busca remover um vínculo entre cobrança e configuração de split não respeita o schema ou está semanticamente errada.",
          "violacoes" => [
            %{
              "razao" => "A cobrança não está ATIVA, invalidando a presente operação.",
              "propriedade" => "cob.status"
            }
          ]
        })
      end
    )

    Efi.Test.expect(
      :put,
      "pix-h.api.efipay.com.br/v2/gn/split/pix/#{@e2e_id}/devolucao/devolucao0001",
      fn conn, body ->
        assert body == %{"valor" => "20.00"}

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{
          "id" => "devolucao0001",
          "valor" => "20.00",
          "status" => "EM_PROCESSAMENTO"
        })
      end
    )

    assert {:ok, %{"id" => @config_id, "status" => "ATIVA"}} =
             Split.create_config(client, @partner_share)

    assert {:ok, %{"revisao" => 0}} =
             Split.get_config(client, @config_id, params: %{"revisao" => 0})

    assert {:ok, nil} = Split.link_charge(client, @txid, @config_id)

    assert {:ok, %{"status" => "CONCLUIDA", "split" => %{"repasses" => %{"valor" => 500}}}} =
             Split.get_charge(client, @txid)

    assert {:error, %Efi.Error{kind: :validation, name: "SplitOperacaoInvalida"}} =
             Split.unlink_charge(client, @txid)

    assert {:ok, %{"status" => "EM_PROCESSAMENTO"}} =
             Split.refund(client, @e2e_id, "devolucao0001", %{"valor" => "20.00"})
  end

  test "chooses the config id, reads its latest revision, links it to a due charge and unlinks it before the customer pays" do
    client = Efi.Test.client()

    config_url = "pix-h.api.efipay.com.br/v2/gn/split/config/#{@config_id}"

    Efi.Test.expect(:put, config_url, fn conn, body ->
      assert body == @partner_share

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(Map.merge(@partner_share, %{"id" => @config_id, "status" => "ATIVA"}))
    end)

    Efi.Test.expect(:get, config_url, fn conn, _body ->
      assert conn.query_params == %{}
      Req.Test.json(conn, Map.merge(@partner_share, %{"id" => @config_id, "revisao" => 0}))
    end)

    Efi.Test.expect(
      :put,
      "pix-h.api.efipay.com.br/v2/gn/split/cobv/#{@txid}/vinculo/#{@config_id}",
      fn conn, _body -> Plug.Conn.send_resp(conn, 204, "") end
    )

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/split/cobv/#{@txid}", fn conn, _body ->
      Req.Test.json(conn, %{
        "txid" => @txid,
        "status" => "ATIVA",
        "config" => %{"id" => @config_id, "status" => "ATIVA"}
      })
    end)

    Efi.Test.expect(
      :delete,
      "pix-h.api.efipay.com.br/v2/gn/split/cobv/#{@txid}/vinculo",
      fn conn, _body -> Plug.Conn.send_resp(conn, 200, "") end
    )

    assert {:ok, %{"id" => @config_id}} =
             Split.create_config_with_id(client, @config_id, @partner_share)

    assert {:ok, %{"revisao" => 0}} = Split.get_config(client, @config_id)
    assert {:ok, nil} = Split.link_due_charge(client, @txid, @config_id)

    assert {:ok, %{"status" => "ATIVA", "config" => %{"id" => @config_id}}} =
             Split.get_due_charge(client, @txid)

    assert {:ok, nil} = Split.unlink_due_charge(client, @txid)
  end
end
