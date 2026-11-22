defmodule Efi.Accounts.SimplifiedAccountTest do
  use ExUnit.Case, async: true

  alias Efi.Accounts.SimplifiedAccount
  alias Efi.Accounts.Webhook

  setup {Req.Test, :verify_on_exit!}

  @host "abrircontas-h.api.efipay.com.br"
  @account_id "92ccd29b-54c9-49fc-b8e8-717a3b373c5e"

  @customer %{
    "clienteFinal" => %{
      "cpf" => "12345678909",
      "nomeCompleto" => "Ana Exemplo",
      "dataNascimento" => "13/08/1990",
      "celular" => "31900000000",
      "email" => "ana@example.com",
      "cnpj" => "11222333000181",
      "razaoSocial" => "Studio Ana LTDA",
      "endereco" => %{
        "cep" => "35400000",
        "estado" => "MG",
        "cidade" => "Ouro Preto",
        "bairro" => "Centro",
        "logradouro" => "Rua Exemplo",
        "numero" => "100"
      }
    },
    "meioDeNotificacao" => ["whatsapp"],
    "escoposIntegrados" => ["cob.write", "cob.read"]
  }

  test "opens an account for a customer and fetches the credentials and certificate once approved" do
    client = Efi.Test.client()
    certificate_base64 = Base.encode64("conteudo do p12")

    Efi.Test.expect(:post, "#{@host}/v1/conta-simplificada", fn conn, body ->
      assert body == @customer
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token-de-teste"]

      Req.Test.json(conn, %{"contaSimplificada" => %{"identificador" => @account_id}})
    end)

    Efi.Test.expect(
      :get,
      "#{@host}/v1/conta-simplificada/#{@account_id}/credenciais",
      fn conn, _body ->
        Req.Test.json(conn, %{
          "clientId" => "Client_Id_conta_do_studio_ana",
          "clientSecret" => "Client_Secret_conta_do_studio_ana",
          "conta" => %{"numero" => "10000", "digito" => "1"},
          "escopos" => ["cob.write", "cob.read"],
          "ativo" => true
        })
      end
    )

    Efi.Test.expect(
      :post,
      "#{@host}/v1/conta-simplificada/#{@account_id}/certificado",
      fn conn, body ->
        assert body == nil

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(certificate_base64)
      end
    )

    assert {:ok, %{"contaSimplificada" => %{"identificador" => @account_id}}} =
             SimplifiedAccount.create(client, @customer)

    assert {:ok, %{"clientId" => "Client_Id_conta_do_studio_ana", "ativo" => true}} =
             SimplifiedAccount.get_credentials(client, @account_id)

    assert {:ok, p12_base64} = SimplifiedAccount.create_certificate(client, @account_id)
    assert Base.decode64!(p12_base64) == "conteudo do p12"
  end

  test "hands back the certificate without quotes when the Efí sends it as plain text" do
    client = Efi.Test.client()
    certificate_base64 = Base.encode64(<<0xFB, 0xFF>> <> "conteudo do p12")

    Efi.Test.expect(
      :post,
      "#{@host}/v1/conta-simplificada/#{@account_id}/certificado",
      fn conn, _body ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(201, ~s("#{certificate_base64}"))
      end
    )

    assert {:ok, ^certificate_base64} = SimplifiedAccount.create_certificate(client, @account_id)
  end

  test "asks the partner to register the account webhook before opening the first account" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "#{@host}/v1/conta-simplificada", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(412)
      |> Req.Test.json(%{
        "nome" => "webhook_nao_cadastrado",
        "mensagem" => "Sua conta não possui webhook cadastrado na API de Cadastro."
      })
    end)

    Efi.Test.expect(:post, "#{@host}/v1/webhook", fn conn, body ->
      assert body == %{"webhookUrl" => "https://app.example.com/efi/contas"}
      Req.Test.json(conn, %{"identificadorWebhook" => "92ecc0a8-9631-4601-a188-feacf8288c13"})
    end)

    Efi.Test.expect(:post, "#{@host}/v1/conta-simplificada", fn conn, body ->
      assert body == @customer
      Req.Test.json(conn, %{"contaSimplificada" => %{"identificador" => @account_id}})
    end)

    assert {:error,
            %Efi.Error{
              kind: :precondition_failed,
              status: 412,
              name: "webhook_nao_cadastrado"
            }} = SimplifiedAccount.create(client, @customer)

    assert {:ok, _webhook} =
             Webhook.configure(client, %{"webhookUrl" => "https://app.example.com/efi/contas"})

    assert {:ok, %{"contaSimplificada" => %{"identificador" => @account_id}}} =
             SimplifiedAccount.create(client, @customer)
  end

  test "refuses another certificate once the account reached its limit" do
    client = Efi.Test.client()

    Efi.Test.expect(
      :post,
      "#{@host}/v1/conta-simplificada/#{@account_id}/certificado",
      fn conn, _body ->
        conn
        |> Plug.Conn.put_status(403)
        |> Req.Test.json(%{
          "nome" => "quantidade_limite_de_certificados",
          "mensagem" => "A conta atingiu a quantidade máxima de certificados."
        })
      end
    )

    assert {:error,
            %Efi.Error{
              kind: :forbidden,
              status: 403,
              name: "quantidade_limite_de_certificados"
            }} = SimplifiedAccount.create_certificate(client, @account_id)
  end

  test "refuses a duplicated opening request and asks to wait while the account is processed" do
    client = Efi.Test.client()

    Efi.Test.expect(:post, "#{@host}/v1/conta-simplificada", fn conn, _body ->
      conn
      |> Plug.Conn.put_status(409)
      |> Req.Test.json(%{
        "nome" => "solicitacao_duplicada",
        "mensagem" =>
          "Já existe uma solicitação de abertura de conta aberta para este cliente final."
      })
    end)

    Efi.Test.expect(
      :get,
      "#{@host}/v1/conta-simplificada/#{@account_id}/credenciais",
      fn conn, _body ->
        conn
        |> Plug.Conn.put_status(412)
        |> Req.Test.json(%{
          "nome" => "conta_em_processamento",
          "mensagem" => "A Efí está processando a conta simplificada."
        })
      end
    )

    assert {:error, %Efi.Error{kind: :conflict, status: 409, name: "solicitacao_duplicada"}} =
             SimplifiedAccount.create(client, @customer)

    assert {:error, %Efi.Error{status: 412, name: "conta_em_processamento"}} =
             SimplifiedAccount.get_credentials(client, @account_id)
  end
end
