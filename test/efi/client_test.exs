defmodule Efi.ClientTest do
  use ExUnit.Case, async: true

  alias Efi.Client
  alias Efi.Error
  alias Efi.Pix.ImmediateCharge
  alias Efi.Test.ProcessTokenStore
  alias Efi.Token

  doctest Efi.Client

  setup {Req.Test, :verify_on_exit!}

  @basic_auth "Basic " <> Base.encode64("Client_Id_studio_ana:Client_Secret_studio_ana")
  @pix_key {:pix, :sandbox, "Client_Id_studio_ana"}

  describe "new/1" do
    test "builds a client and refuses a missing credential, an unknown environment or a bad certificate" do
      assert {:ok, %Client{environment: :production, receive_timeout: 30_000}} =
               Client.new(client_id: "id", client_secret: "secret", environment: :production)

      assert {:error, %Error{kind: :configuration, reason: {:client_secret, :required}}} =
               Client.new(client_id: "id", client_secret: "", environment: :sandbox)

      assert {:error, %Error{kind: :configuration, reason: {:environment, :invalid}}} =
               Client.new(client_id: "id", client_secret: "secret", environment: :homologacao)

      assert {:error, %Error{kind: :configuration, reason: {:certificate, :invalid}}} =
               Client.new(
                 client_id: "id",
                 client_secret: "secret",
                 environment: :sandbox,
                 certificate: "producao.p12"
               )
    end

    test "keeps the secret, the partner token and the access token out of inspect and crash reports" do
      client = Efi.Test.client(partner_token: "parceiro-studio-ana")
      inspected = inspect({client, token("token-secreto", expires_in: 600)})

      assert inspected =~ "Client_Id_studio_ana"
      refute inspected =~ "Client_Secret_studio_ana"
      refute inspected =~ "parceiro-studio-ana"
      refute inspected =~ "token-secreto"
    end
  end

  describe "access token" do
    test "without a token store, asks Efí for a token before every call" do
      client = Efi.Test.client(token_store: nil)

      for _call <- 1..2 do
        expect_token_request("pix-h.api.efipay.com.br/oauth/token", "novo-token")

        Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer novo-token"]
          Req.Test.json(conn, %{"txid" => "abc"})
        end)

        assert {:ok, %{"txid" => "abc"}} = ImmediateCharge.get(client, "abc")
      end
    end

    test "reuses a stored token, renews it a minute before it expires and keeps the new one" do
      client = Efi.Test.client(token_store: ProcessTokenStore)
      ProcessTokenStore.seed(@pix_key, token("guardado", expires_in: 3600))

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer guardado"]
        Req.Test.json(conn, %{"txid" => "abc"})
      end)

      assert {:ok, _charge} = ImmediateCharge.get(client, "abc")

      ProcessTokenStore.seed(@pix_key, token("quase-vencido", expires_in: 30))
      expect_token_request("pix-h.api.efipay.com.br/oauth/token", "renovado")

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer renovado"]
        Req.Test.json(conn, %{"txid" => "abc"})
      end)

      assert {:ok, _charge} = ImmediateCharge.get(client, "abc")

      assert %Token{access_token: "renovado", scope: "cob.read cob.write"} =
               ProcessTokenStore.stored(@pix_key)
    end

    test "asks for a new token and repeats once when Efí revokes a stored token" do
      client = Efi.Test.client(token_store: ProcessTokenStore)
      ProcessTokenStore.seed(@pix_key, token("revogado", expires_in: 3600))

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"nome" => "nao_autorizado"})
      end)

      expect_token_request("pix-h.api.efipay.com.br/oauth/token", "novo")

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer novo"]
        Req.Test.json(conn, %{"txid" => "abc"})
      end)

      assert {:ok, %{"txid" => "abc"}} = ImmediateCharge.get(client, "abc")
      assert %Token{access_token: "novo"} = ProcessTokenStore.stored(@pix_key)
    end

    test "returns a fresh token's 401 as is, without asking again" do
      client = Efi.Test.client(token_store: nil)
      expect_token_request("pix-h.api.efipay.com.br/oauth/token", "sem-escopo")

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"nome" => "nao_autorizado"})
      end)

      assert {:error, %Error{kind: :unauthorized, name: "nao_autorizado"}} =
               ImmediateCharge.get(client, "abc")
    end

    test "reports refused credentials as an authentication error and leaves the API untouched" do
      client = Efi.Test.client(token_store: nil)

      Efi.Test.expect(:post, "pix-h.api.efipay.com.br/oauth/token", fn conn, _body ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{
          "error" => "invalid_client",
          "error_description" => "Invalid or inactive credentials"
        })
      end)

      assert {:error,
              %Error{
                kind: :authentication,
                status: 401,
                name: "invalid_client",
                message: "Invalid or inactive credentials"
              }} = ImmediateCharge.get(client, "abc")
    end

    test "reports a token answer without an access token as an authentication error" do
      client = Efi.Test.client(token_store: nil)

      Efi.Test.expect(:post, "pix-h.api.efipay.com.br/oauth/token", fn conn, _body ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<html>Em manutenção</html>")
      end)

      assert {:error,
              %Error{kind: :authentication, status: 200, body: "<html>Em manutenção</html>"}} =
               ImmediateCharge.get(client, "abc")
    end

    test "reports a token request that never got an answer as a transport error" do
      client = Efi.Test.client(token_store: nil)

      Efi.Test.expect(:post, "pix-h.api.efipay.com.br/oauth/token", fn conn, _body ->
        Req.Test.transport_error(conn, :timeout)
      end)

      assert {:error, %Error{kind: :transport, reason: %Req.TransportError{reason: :timeout}}} =
               ImmediateCharge.get(client, "abc")
    end

    test "authorizes each API on its own production token route and keeps the tokens apart" do
      client = Efi.Test.client(environment: :production, token_store: ProcessTokenStore)

      routes = [
        pix: {"pix.api.efipay.com.br/oauth/token", token_response("token-pix")},
        charges:
          {"cobrancas.api.efipay.com.br/v1/authorize", charges_token_response("token-charges")},
        open_finance:
          {"openfinance.api.efipay.com.br/v1/oauth/token", token_response("token-open_finance")},
        accounts:
          {"abrircontas.api.efipay.com.br/v1/oauth/token", token_response("token-accounts")},
        bill_payments:
          {"pagarcontas.api.efipay.com.br/v1/oauth/token", token_response("token-bill_payments")},
        statements:
          {"extratos.api.efipay.com.br/v1/oauth/token", token_response("token-statements")}
      ]

      for {api, {route, response}} <- routes do
        expect_token_request(route, response)
        assert {:ok, %Token{} = token} = Client.authorize(client, api)

        assert token.access_token == "token-#{api}"
        assert token.scope == response["scope"]
        expires_in = response["expires_in"]
        assert DateTime.diff(token.expires_at, DateTime.utc_now()) in (expires_in - 5)..expires_in
        assert ProcessTokenStore.stored({api, :production, "Client_Id_studio_ana"}) == token
      end
    end
  end

  describe "request/5" do
    test "sends the partner, idempotency, mTLS skip and extra headers only when asked" do
      client = Efi.Test.client(partner_token: "parceiro-studio-ana")

      Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/webhook/chave", fn conn, body ->
        assert body == %{"webhookUrl" => "https://app.example.com/efi"}
        assert Plug.Conn.get_req_header(conn, "partner-token") == ["parceiro-studio-ana"]
        assert Plug.Conn.get_req_header(conn, "x-idempotency-key") == ["pedido-1"]
        assert Plug.Conn.get_req_header(conn, "x-skip-mtls-checking") == ["true"]
        assert Plug.Conn.get_req_header(conn, "x-extra") == ["sim"]
        Req.Test.json(conn, %{"webhookUrl" => "https://app.example.com/efi"})
      end)

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/webhook/chave", fn conn, _body ->
        assert Plug.Conn.get_req_header(conn, "x-idempotency-key") == []
        assert Plug.Conn.get_req_header(conn, "x-skip-mtls-checking") == []
        Req.Test.json(conn, %{})
      end)

      assert {:ok, _webhook} =
               Client.request(client, :pix, :put, "/v2/webhook/chave",
                 json: %{"webhookUrl" => "https://app.example.com/efi"},
                 idempotency_key: "pedido-1",
                 skip_mtls_checking: true,
                 headers: [{"x-extra", "sim"}]
               )

      assert {:ok, %{}} = Client.request(client, :pix, :get, "/v2/webhook/chave")
    end

    test "keeps the token when the app adds its own headers through req_options" do
      client =
        Efi.Test.client(
          req_options: [
            plug: {Req.Test, Efi.Test.stub()},
            retry: false,
            headers: [{"x-request-id", "pedido-1"}]
          ]
        )

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer token-de-teste"]
        assert Plug.Conn.get_req_header(conn, "x-request-id") == ["pedido-1"]
        Req.Test.json(conn, %{"txid" => "abc"})
      end)

      assert {:ok, %{"txid" => "abc"}} = ImmediateCharge.get(client, "abc")
    end

    test "returns nil for an empty body and the raw bytes for a file" do
      client = Efi.Test.client()

      Efi.Test.expect(:delete, "pix-h.api.efipay.com.br/v2/webhook/chave", fn conn, _body ->
        Plug.Conn.send_resp(conn, 204, "")
      end)

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/pix/comprovantes", fn conn, _body ->
        conn
        |> Plug.Conn.put_resp_content_type("application/pdf")
        |> Plug.Conn.send_resp(200, "%PDF-1.7 comprovante")
      end)

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/gn/saldo", fn conn, _body ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, "{quebrado")
      end)

      assert {:ok, nil} = Client.request(client, :pix, :delete, "/v2/webhook/chave")

      assert {:ok, "%PDF-1.7 comprovante"} =
               Client.request(client, :pix, :get, "/v2/gn/pix/comprovantes")

      assert {:ok, "{quebrado"} = Client.request(client, :pix, :get, "/v2/gn/saldo")
    end

    test "reads each API's documented error formats into the same fields" do
      client = Efi.Test.client(environment: :production)

      # A doc do Pix põe o "não encontrado" de cobranças, locations e Pix na aba 400: ele chega
      # como :validation, e só o `name` diz que o recurso não existe.
      cases = [
        {:pix, :put, "pix.api.efipay.com.br/v2/webhook/chave-pix-do-studio-ana", 400,
         %{
           "nome" => "webhook_invalido",
           "mensagem" => "A autenticação de TLS mútuo não está configurada na URL informada"
         }, :validation, "webhook_invalido",
         "A autenticação de TLS mútuo não está configurada na URL informada"},
        {:pix, :get, "pix.api.efipay.com.br/v2/cob/abc", 400,
         %{
           "nome" => "cobranca_nao_encontrada",
           "mensagem" => "Nenhuma cobrança encontrada para o txid informado"
         }, :validation, "cobranca_nao_encontrada",
         "Nenhuma cobrança encontrada para o txid informado"},
        {:pix, :post, "pix.api.efipay.com.br/v2/loc", 400,
         %{
           "nome" => "json_invalido",
           "mensagem" => "Valores ou tipos de campo inválidos",
           "erros" => [
             %{
               "chave" => "enum",
               "caminho" => ".body.tipoCob",
               "mensagem" => "deve ser igual a um dos valores predefinidos"
             }
           ]
         }, :validation, "json_invalido", "Valores ou tipos de campo inválidos"},
        {:pix, :post, "pix.api.efipay.com.br/v2/gn/webhook/reenviar", 422,
         %{
           "type" => "https://pix.bcb.gov.br/api/v2/error/WebhooksOperacaoInvalida",
           "title" => "Operação Inválida",
           "status" => 422,
           "detail" =>
             "A requisição que busca solicitar o reenvios de webhooks não respeita o schema ou está semanticamente errada.",
           "violacoes" => [
             %{
               "razao" => "Nenhuma devolução foi encontrada para os e2eids informados.",
               "propriedade" => "body.e2eIds"
             }
           ]
         }, :validation, "WebhooksOperacaoInvalida",
         "A requisição que busca solicitar o reenvios de webhooks não respeita o schema ou está semanticamente errada."},
        {:pix, :put, "pix.api.efipay.com.br/v2/gn/pix/envio-1/qrcode", 403,
         %{
           "error" => "insufficient_scope",
           "error_description" => "Access token has insufficient scope"
         }, :forbidden, "insufficient_scope", "Access token has insufficient scope"},
        {:pix, :get, "pix.api.efipay.com.br/v2/webhookrec", 404,
         %{
           "type" => "https://pix.bcb.gov.br/api/v2/error/NaoEncontrado",
           "title" => "Não Encontrado",
           "status" => 404,
           "detail" => "Entidade não encontrada."
         }, :not_found, "NaoEncontrado", "Entidade não encontrada."},
        {:pix, :post, "pix.api.efipay.com.br/v2/cob", 429,
         %{
           "nome" => "Limite de Requisições Excedido",
           "mensagem" =>
             "As requisições estão temporariamente limitadas. Aguarde um momento e tente novamente"
         }, :rate_limited, "Limite de Requisições Excedido",
         "As requisições estão temporariamente limitadas. Aguarde um momento e tente novamente"},
        {:pix, :post, "pix.api.efipay.com.br/v2/cob", 500,
         %{"nome" => "erro_aplicacao", "mensagem" => "Ocorreu um erro ao validar a chave"},
         :server, "erro_aplicacao", "Ocorreu um erro ao validar a chave"},
        {:charges, :put, "cobrancas.api.efipay.com.br/v1/carnet/1/parcels", 400,
         %{
           "code" => 3_500_034,
           "error" => "validation_error",
           "error_description" => %{
             "property" => "/parcels/0",
             "message" => "A propriedade [expire_at] é obrigatória."
           }
         }, :validation, "validation_error", "A propriedade [expire_at] é obrigatória."},
        {:charges, :put, "cobrancas.api.efipay.com.br/v1/carnet/1/parcels", 400,
         %{
           "code" => 3_500_101,
           "error" => "update_parcels",
           "error_description" => "A propriedade [parcel] informada não existe. Parcela: [9]."
         }, :validation, "update_parcels",
         "A propriedade [parcel] informada não existe. Parcela: [9]."},
        {:charges, :post, "cobrancas.api.efipay.com.br/v1/charge/card", 422,
         %{
           "title" => "Unprocessable Entity",
           "status" => 422,
           "detail" => "The request contains invalid or incomplete data"
         }, :validation, nil, "The request contains invalid or incomplete data"},
        {:accounts, :get,
         "abrircontas.api.efipay.com.br/v1/conta-simplificada/conta-1/credenciais", 412,
         %{
           "nome" => "conta_em_processamento",
           "mensagem" => "A Efí está processando a conta simplificada."
         }, :precondition_failed, "conta_em_processamento",
         "A Efí está processando a conta simplificada."},
        {:accounts, :post, "abrircontas.api.efipay.com.br/v1/conta-simplificada", 405, nil, :http,
         nil, nil},
        {:bill_payments, :get, "pagarcontas.api.efipay.com.br/v1/codBarras/123", 400,
         %{"erro" => 0, "descricao" => "Código de barras inválido"}, :validation, nil,
         "Código de barras inválido"}
      ]

      for {api, method, url, status, body, kind, name, message} <- cases do
        Efi.Test.expect(method, url, fn conn, _body ->
          conn = Plug.Conn.put_status(conn, status)
          if body, do: Req.Test.json(conn, body), else: Plug.Conn.send_resp(conn, status, "")
        end)

        [_host, path] = String.split(url, "/", parts: 2)
        assert {:error, %Error{} = error} = Client.request(client, api, method, "/" <> path)

        assert {error.kind, error.status, error.name, error.message, error.body} ==
                 {kind, status, name, message, body}
      end
    end

    test "repeats a read after a transient failure but never a write that may have reached Efí" do
      client =
        Efi.Test.client(
          req_options: [plug: {Req.Test, Efi.Test.stub()}, retry_delay: 0, retry_log_level: false]
        )

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        Plug.Conn.send_resp(conn, 503, "")
      end)

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        Req.Test.transport_error(conn, :timeout)
      end)

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        Req.Test.json(conn, %{"txid" => "abc"})
      end)

      Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        Req.Test.transport_error(conn, :timeout)
      end)

      Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/cob/def", fn conn, _body ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v2/cob/def", fn conn, _body ->
        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"txid" => "def"})
      end)

      assert {:ok, %{"txid" => "abc"}} = ImmediateCharge.get(client, "abc")

      assert {:error, %Error{kind: :transport, reason: %Req.TransportError{reason: :timeout}}} =
               ImmediateCharge.create_with_txid(client, "abc", %{})

      assert {:ok, %{"txid" => "def"}} = ImmediateCharge.create_with_txid(client, "def", %{})
    end

    test "waits as Efí asks before repeating a read, unless the wait is long or unreadable" do
      client =
        Efi.Test.client(req_options: [plug: {Req.Test, Efi.Test.stub()}, retry_log_level: false])

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        conn |> Plug.Conn.put_resp_header("retry-after", "0") |> Plug.Conn.send_resp(429, "")
      end)

      Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
        Req.Test.json(conn, %{"txid" => "abc"})
      end)

      for retry_after <- ["600", "1.5"] do
        Efi.Test.expect(:get, "pix-h.api.efipay.com.br/v2/cob/abc", fn conn, _body ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", retry_after)
          |> Plug.Conn.send_resp(503, "")
        end)
      end

      assert {:ok, %{"txid" => "abc"}} = ImmediateCharge.get(client, "abc")

      assert {:error, %Error{kind: :server, headers: %{"retry-after" => ["600"]}}} =
               ImmediateCharge.get(client, "abc")

      assert {:error, %Error{kind: :server, headers: %{"retry-after" => ["1.5"]}}} =
               ImmediateCharge.get(client, "abc")
    end

    test "returns a Pix send refused for an empty token bucket at once, with the wait Efí asks for" do
      client =
        Efi.Test.client(req_options: [plug: {Req.Test, Efi.Test.stub()}, retry_log_level: false])

      Efi.Test.expect(:put, "pix-h.api.efipay.com.br/v3/gn/pix/envio-1", fn conn, _body ->
        conn
        |> Plug.Conn.put_resp_header("retry-after", "1")
        |> Plug.Conn.put_resp_header("bucket-size", "0")
        |> Plug.Conn.put_status(429)
        |> Req.Test.json(%{
          "type" =>
            "https://gn-pix-api.m12680221.orp-1.colaboradores.labgerencianet.com.br/BaldeFichasVazio",
          "title" => "Balde de Fichas Vazio",
          "status" => 429,
          "detail" => "Não há fichas no balde a serem consumidas"
        })
      end)

      assert {:error,
              %Error{
                kind: :rate_limited,
                name: "BaldeFichasVazio",
                message: "Não há fichas no balde a serem consumidas",
                headers: %{"retry-after" => ["1"], "bucket-size" => ["0"]}
              }} =
               Client.request(client, :pix, :put, "/v3/gn/pix/envio-1",
                 json: %{
                   "valor" => "12.34",
                   "favorecido" => %{"chave" => "chave-pix-do-studio-ana"}
                 }
               )
    end

    test "reports a failure Req could not classify as transport, without repeating it" do
      client = Efi.Test.client(req_options: [adapter: Efi.Test.UnexpectedFailureAdapter])

      assert {:error, %Error{kind: :transport, reason: %RuntimeError{}}} =
               ImmediateCharge.get(client, "abc")

      assert {:error, %Error{kind: :transport, reason: %RuntimeError{}}} =
               ImmediateCharge.create(client, %{})
    end

    test "requires a certificate for every API except Cobranças" do
      client = Efi.Test.client(certificate: nil)

      Efi.Test.expect(:get, "cobrancas-h.api.efipay.com.br/v1/charge/1", fn conn, _body ->
        Req.Test.json(conn, %{"code" => 200, "data" => %{"charge_id" => 1}})
      end)

      assert {:error, %Error{kind: :configuration, reason: {:certificate, :required}}} =
               ImmediateCharge.get(client, "abc")

      assert {:error, %Error{kind: :configuration, reason: {:certificate, :required}}} =
               Client.authorize(client, :open_finance)

      assert {:ok, %{"data" => %{"charge_id" => 1}}} =
               Client.request(client, :charges, :get, "/v1/charge/1")
    end

    test "refuses an expired certificate before calling Efí, except for Cobranças" do
      expired = %{Efi.Test.fake_certificate() | not_after: ~U[2026-01-01 00:00:00Z]}
      client = Efi.Test.client(certificate: expired)

      Efi.Test.expect(:get, "cobrancas-h.api.efipay.com.br/v1/charge/1", fn conn, _body ->
        Req.Test.json(conn, %{"code" => 200, "data" => %{"charge_id" => 1}})
      end)

      assert {:error, %Error{kind: :certificate, reason: :expired}} =
               ImmediateCharge.get(client, "abc")

      assert {:ok, %{"data" => %{"charge_id" => 1}}} =
               Client.request(client, :charges, :get, "/v1/charge/1")
    end

    test "refuses the sandbox for Pagamento de Contas and Extratos, which Efí only runs in production" do
      client = Efi.Test.client()

      for api <- [:bill_payments, :statements] do
        assert {:error, %Error{kind: :configuration, reason: {:environment, :unsupported}}} =
                 Client.request(client, api, :get, "/v1/qualquer")

        assert {:error, %Error{kind: :configuration, reason: {:environment, :unsupported}}} =
                 Client.authorize(client, api)
      end
    end

    test "refuses an unknown request option and a path value that is missing or would change the route" do
      client = Efi.Test.client()

      assert_raise ArgumentError, fn ->
        Client.request(client, :pix, :get, "/v2/cob", param: %{})
      end

      assert_raise ArgumentError, ~r/missing value for :txid/, fn ->
        Client.path("/v2/cob/:txid", id: "abc")
      end

      for value <- [nil, "", ".", ".."] do
        assert_raise ArgumentError, ~r/invalid value .* for :txid/, fn ->
          ImmediateCharge.get(client, value)
        end
      end
    end
  end

  test "an error explains itself when raised" do
    error = %Error{
      kind: :validation,
      status: 400,
      name: "valor_invalido",
      message: "O valor é inválido."
    }

    assert Exception.message(error) == ":validation 400 valor_invalido O valor é inválido."

    assert Exception.message(%Error{kind: :certificate, reason: :invalid_password}) ==
             ":certificate :invalid_password"

    assert_raise Error, ":configuration", fn -> raise Error, kind: :configuration end
  end

  defp expect_token_request(url, access_token) when is_binary(access_token),
    do: expect_token_request(url, token_response(access_token))

  defp expect_token_request(url, %{} = response) do
    Efi.Test.expect(:post, url, fn conn, body ->
      assert body == %{"grant_type" => "client_credentials"}
      assert Plug.Conn.get_req_header(conn, "authorization") == [@basic_auth]
      Req.Test.json(conn, response)
    end)
  end

  defp token_response(access_token) do
    %{
      "access_token" => access_token,
      "token_type" => "Bearer",
      "expires_in" => 3600,
      "scope" => "cob.read cob.write"
    }
  end

  # A Cobranças responde no formato da própria doc: 10 minutos, refresh_token e sem scope.
  defp charges_token_response(access_token) do
    %{
      "access_token" => access_token,
      "refresh_token" => "refresh-#{access_token}",
      "expires_in" => 600,
      "expire_at" => "1690986856033",
      "token_type" => "Bearer"
    }
  end

  defp token(access_token, expires_in: seconds) do
    %Token{
      access_token: access_token,
      token_type: "Bearer",
      expires_at: DateTime.add(DateTime.utc_now(), seconds, :second)
    }
  end
end
