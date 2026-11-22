defmodule Efi.Pix.Automatic.Location do
  @moduledoc """
  Location de recorrência de Pix Automático (`locrec`): a URL que o QR Code de autorização
  aponta, usada nas jornadas 2, 3 e 4 descritas em `Efi.Pix.Automatic.Recurrence`. É separada
  das locations de cobrança imediata e com vencimento.

  A location é criada sem corpo e o `id` dela vai no campo `loc` da recorrência:

      {:ok, %{"id" => location_id}} = Efi.Pix.Automatic.Location.create(client)

      {:ok, recurrence} =
        Efi.Pix.Automatic.Recurrence.create(client, %{
          "loc" => location_id,
          "vinculo" => %{
            "contrato" => "plano-mensal-0001",
            "devedor" => %{"cpf" => "12345678909", "nome" => "Cliente do Studio Ana"},
            "objeto" => "Plano mensal de escova"
          },
          "calendario" => %{"dataInicial" => "2026-12-01", "periodicidade" => "MENSAL"},
          "valor" => %{"valorRec" => "150.00"},
          "politicaRetentativa" => "NAO_PERMITE"
        })

  Depois de vinculada, a location passa a mostrar o `idRec`. `unlink_recurrence/3` desfaz o
  vínculo.
  """

  alias Efi.Client

  @doc """
  Cria uma location de recorrência. A requisição não tem corpo.

  `POST /v2/locrec` · escopo `payloadlocationrec.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/payload-locations#criar-location-do-payload-de-recorrência-de-pix-automático)
  """
  @spec create(Client.t(), keyword()) :: Efi.result()
  def create(%Client{} = client, opts \\ []) do
    Client.request(client, :pix, :post, "/v2/locrec", opts)
  end

  @doc """
  Lista as locations de recorrência criadas entre `inicio` e `fim` (RFC 3339, obrigatórios).
  As locations voltam em `loc`.

  `GET /v2/locrec` · escopo `payloadlocationrec.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/payload-locations#consultar-locations-de-recorrência-de-pix-automático-cadastradas)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/locrec", Client.put_params(opts, params))
  end

  @doc """
  Consulta uma location de recorrência pelo `id`, com o `idRec` quando está vinculada.

  `GET /v2/locrec/:id` · escopo `payloadlocationrec.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/payload-locations#recuperar-location-do-payload-de-recorrência-de-pix-automático)
  """
  @spec get(Client.t(), integer() | String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, location_id, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/locrec/:id", id: location_id), opts)
  end

  @doc """
  Desvincula a recorrência da location. A resposta é a location sem o `idRec`.

  `DELETE /v2/locrec/:id/idRec` · escopo `payloadlocationrec.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/payload-locations#desvincular-uma-recorrência-de-pix-automático-de-um-location)
  """
  @spec unlink_recurrence(Client.t(), integer() | String.t(), keyword()) :: Efi.result()
  def unlink_recurrence(%Client{} = client, location_id, opts \\ []) do
    path = Client.path("/v2/locrec/:id/idRec", id: location_id)
    Client.request(client, :pix, :delete, path, opts)
  end
end
