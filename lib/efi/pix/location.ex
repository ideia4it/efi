defmodule Efi.Pix.Location do
  @moduledoc """
  Payload location (`loc`): o endereço que o QR Code dinâmico guarda e de onde o app do pagador
  busca os dados da cobrança.

  Uma cobrança imediata ou com vencimento criada sem `loc` ganha um location sozinha. Criar um
  antes serve para reservar o QR Code e ligá-lo depois a uma cobrança, passando
  `"loc" => %{"id" => id}` no corpo dela. O `tipoCob` do location (`"cob"` ou `"cobv"`) precisa
  casar com o tipo da cobrança.

      {:ok, %{"id" => location_id}} = Efi.Pix.Location.create(client, %{"tipoCob" => "cob"})

      {:ok, _charge} =
        Efi.Pix.ImmediateCharge.create(client, %{
          "calendario" => %{"expiracao" => 3600},
          "loc" => %{"id" => location_id},
          "valor" => %{"original" => "50.00"},
          "chave" => "chave-pix-do-studio-ana"
        })

      {:ok, %{"imagemQrcode" => image, "linkVisualizacao" => link}} =
        Efi.Pix.Location.get_qr_code(client, location_id)

  `get_qr_code/3` devolve o Pix Copia e Cola em `qrcode`, a imagem do QR Code como data URI em
  `imagemQrcode`, pronta para um `<img src>`, e em `linkVisualizacao` uma página da Efí com a
  cobrança e o QR Code para mandar a quem paga. Esse link só funciona para cobranças de produção.

  `unlink_txid/3` solta a cobrança do location: o location fica sem `txid` e a cobrança fica sem
  location, mas o status dela não muda.

  Os locations de Pix Automático (`locrec`) não ficam aqui: estão junto do Pix Automático.
  """

  alias Efi.Client

  @doc """
  Cria um location para cobrança imediata (`%{"tipoCob" => "cob"}`) ou com vencimento
  (`%{"tipoCob" => "cobv"}`).

  `POST /v2/loc` · escopo `payloadlocation.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/payload-locations#criar-location-do-payload)
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(client, :pix, :post, "/v2/loc", Keyword.put(opts, :json, body))
  end

  @doc """
  Lista os locations criados entre `inicio` e `fim` (RFC 3339, obrigatórios). Filtros
  opcionais: `txIdPresente`, `tipoCob` (`cob` ou `cobv`), `paginacao.paginaAtual` e
  `paginacao.itensPorPagina`.

  `GET /v2/loc` · escopo `payloadlocation.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/payload-locations#consultar-locations-cadastradas)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/loc", Keyword.put(opts, :params, params))
  end

  @doc """
  Consulta um location pelo `id`, com o `txid` da cobrança ligada a ele, se houver.

  `GET /v2/loc/:id` · escopo `payloadlocation.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/payload-locations#recuperar-location-do-payload)
  """
  @spec get(Client.t(), integer() | String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, id, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/loc/:id", id: id), opts)
  end

  @doc """
  Desvincula a cobrança do location, sem mudar o status da cobrança.

  `DELETE /v2/loc/:id/txid` · escopo `payloadlocation.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/payload-locations#desvincular-um-txid-de-um-location)
  """
  @spec unlink_txid(Client.t(), integer() | String.t(), keyword()) :: Efi.result()
  def unlink_txid(%Client{} = client, id, opts \\ []) do
    Client.request(client, :pix, :delete, Client.path("/v2/loc/:id/txid", id: id), opts)
  end

  @doc """
  Gera o QR Code de um location: Pix Copia e Cola, imagem e link de visualização.

  `GET /v2/loc/:id/qrcode` · escopo `payloadlocation.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/payload-locations#gerar-qr-code-de-um-location)
  """
  @spec get_qr_code(Client.t(), integer() | String.t(), keyword()) :: Efi.result()
  def get_qr_code(%Client{} = client, id, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/loc/:id/qrcode", id: id), opts)
  end
end
