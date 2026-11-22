defmodule Efi.Pix.ImmediateCharge do
  @moduledoc """
  Cobrança Pix imediata (`cob`): o QR Code que o pagador escaneia na hora.

  O `txid` identifica a cobrança e é escolhido pelo recebedor: de 26 a 35 caracteres, só letras
  e números. `create/3` deixa a Efí escolher; `create_with_txid/4` usa o seu, o que torna a
  criação segura para repetir depois de um timeout (o segundo `PUT` com o mesmo `txid` volta
  como `%Efi.Error{kind: :conflict}` em vez de criar outra cobrança).

      {:ok, charge} =
        Efi.Pix.ImmediateCharge.create_with_txid(client, "studioana0000000000000000001", %{
          "calendario" => %{"expiracao" => 3600},
          "devedor" => %{"cpf" => "12345678909", "nome" => "Cliente do Studio Ana"},
          "valor" => %{"original" => "50.00"},
          "chave" => "chave-pix-do-studio-ana",
          "solicitacaoPagador" => "Corte e escova"
        })

      charge["pixCopiaECola"]

  Em homologação, cobranças de R$ 0,01 a R$ 10,00 são pagas sozinhas e disparam o webhook;
  acima disso ficam ativas sem pagamento.

  Para o QR Code em imagem, use `Efi.Pix.Location.get_qr_code/3` com o `loc.id` da resposta.
  """

  alias Efi.Client

  @doc """
  Cria uma cobrança imediata sem `txid`: a Efí gera o identificador e o devolve na resposta.

  `POST /v2/cob` · escopo `cob.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-imediatas#criar-cobrança-imediata-sem-txid)
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(client, :pix, :post, "/v2/cob", Keyword.put(opts, :json, body))
  end

  @doc """
  Cria uma cobrança imediata com o `txid` informado.

  `PUT /v2/cob/:txid` · escopo `cob.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-imediatas#criar-cobrança-imediata-com-txid)
  """
  @spec create_with_txid(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create_with_txid(%Client{} = client, txid, body, opts \\ []) do
    path = Client.path("/v2/cob/:txid", txid: txid)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Revisa uma cobrança: muda os campos enviados e incrementa a `revisao`. Com
  `%{"status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"}`, cancela a cobrança. Só cobranças `ATIVA`
  aceitam revisão: as outras voltam como
  `%Efi.Error{kind: :validation, name: "status_cobranca_invalido"}`.

  `PATCH /v2/cob/:txid` · escopo `cob.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-imediatas#revisar-cobrança)
  """
  @spec update(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def update(%Client{} = client, txid, changes, opts \\ []) do
    path = Client.path("/v2/cob/:txid", txid: txid)
    Client.request(client, :pix, :patch, path, Keyword.put(opts, :json, changes))
  end

  @doc """
  Consulta uma cobrança pelo `txid`. Para uma revisão anterior, passe
  `params: %{"revisao" => 1}`.

  `GET /v2/cob/:txid` · escopo `cob.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-imediatas#consultar-cobrança)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, txid, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/cob/:txid", txid: txid), opts)
  end

  @doc """
  Lista as cobranças criadas entre `inicio` e `fim` (RFC 3339, obrigatórios). Filtros
  opcionais: `cpf`, `cnpj`, `status`, `paginacao.paginaAtual` e `paginacao.itensPorPagina`.

  `GET /v2/cob` · escopo `cob.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-imediatas#consultar-lista-de-cobranças)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/cob", Keyword.put(opts, :params, params))
  end
end
