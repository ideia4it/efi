defmodule Efi.Pix.AccountTest do
  use ExUnit.Case, async: true

  alias Efi.Pix.Account

  setup {Req.Test, :verify_on_exit!}

  test "checks the balance, looks into the blocked amounts, requires the payer to be the debtor on a key and reads the settings and key buckets back" do
    client = Efi.Test.client()

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/saldo", fn conn, _body ->
      assert conn.query_params == %{}
      Req.Test.json(conn, %{"saldo" => "100.00"})
    end)

    key_settings = %{
      "pix" => %{
        "receberSemChave" => false,
        "chaves" => %{
          "chave-pix-do-studio-ana" => %{
            "recebimento" => %{"documentoPagadorIgualDevedor" => true}
          }
        }
      }
    }

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/saldo", fn conn, _body ->
      assert conn.query_params == %{"bloqueios" => "true"}

      Req.Test.json(conn, %{
        "saldo" => "100.00",
        "bloqueios" => %{"judicial" => "0.00", "med" => "12.00", "total" => "12.00"}
      })
    end)

    Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/gn/config", fn conn, body ->
      assert body == key_settings
      Plug.Conn.send_resp(conn, 204, "")
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/config", fn conn, _body ->
      Req.Test.json(conn, key_settings)
    end)

    Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/chaves/balde", fn conn, _body ->
      Req.Test.json(conn, %{
        "baldeA" => %{"tiposChave" => ["cpf", "cnpj", "evp"], "fichasDisponiveis" => 80},
        "baldeB" => %{"tiposChave" => ["telefone", "email"], "fichasDisponiveis" => 0}
      })
    end)

    assert {:ok, %{"saldo" => "100.00"}} = Account.get_balance(client)

    assert {:ok, %{"saldo" => "100.00", "bloqueios" => %{"med" => "12.00"}}} =
             Account.get_balance(client, params: %{"bloqueios" => true})

    assert {:ok, nil} = Account.update_settings(client, key_settings)
    assert {:ok, ^key_settings} = Account.get_settings(client)

    assert {:ok, %{"baldeB" => %{"fichasDisponiveis" => 0}}} = Account.get_key_buckets(client)
  end
end
