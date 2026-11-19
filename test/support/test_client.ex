defmodule Efi.Test do
  @moduledoc false

  import ExUnit.Assertions

  alias Efi.Certificate
  alias Efi.Client

  @stub Efi.Test.Stub

  @doc """
  Cliente de homologação com o stub do `Req.Test` e um token que nunca vence, para os testes
  das APIs não precisarem simular o pedido do token. O fluxo do token tem testes próprios.
  """
  def client(overrides \\ []) do
    {:ok, client} =
      [
        client_id: "Client_Id_studio_ana",
        client_secret: "Client_Secret_studio_ana",
        environment: :sandbox,
        certificate: fake_certificate(),
        token_store: Efi.Test.StaticTokenStore,
        req_options: [plug: {Req.Test, @stub}, retry: false]
      ]
      |> Keyword.merge(overrides)
      |> Client.new()

    client
  end

  @doc "Certificado de mentira: o stub não abre conexão TLS, então as peças nunca são lidas."
  def fake_certificate do
    %Certificate{
      certificate: "certificado",
      key: {:PrivateKeyInfo, "chave"},
      chain: [],
      not_before: ~U[2026-01-01 00:00:00Z],
      not_after: ~U[2027-01-01 00:00:00Z]
    }
  end

  @doc """
  Espera uma requisição `method` em `url` (host e caminho, sem `https://`) e responde com
  `respond.(conn, corpo_json_decodificado)`.
  """
  def expect(method, url, respond) do
    Req.Test.expect(@stub, fn conn ->
      assert conn.method == method |> Atom.to_string() |> String.upcase()
      assert conn.host <> conn.request_path == url

      respond.(conn, json_body(conn))
    end)
  end

  @doc "Corpo da requisição decodificado, ou `nil` se veio vazio."
  def json_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, "", _conn} -> nil
      {:ok, body, _conn} -> Jason.decode!(body)
    end
  end

  def stub, do: @stub
end
