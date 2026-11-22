defmodule Efi.Pix.Infraction do
  @moduledoc """
  Infrações do MED (Mecanismo Especial de Devolução): contestações abertas contra Pix que a
  conta recebeu, em geral por suspeita de golpe, e a defesa de cada uma.

  O valor bloqueado por MED aparece no saldo com `Efi.Pix.Account.get_balance/2` e
  `params: %{"bloqueios" => true}`.

      {:ok, %{"infracoes" => infractions}} =
        Efi.Pix.Infraction.list(client, %{
          "inicio" => "2026-11-01T00:00:00Z",
          "fim" => "2026-11-30T23:59:59Z"
        })

      Efi.Pix.Infraction.submit_defense(client, infraction["idInfracao"], %{
        "analise" => "rejeitado",
        "justificativa" => "Serviço prestado no Studio Ana em 12/11, com agendamento confirmado."
      })

  Cada infração aceita uma defesa só (a segunda volta como `%Efi.Error{kind: :conflict}`), e só
  dentro do prazo de defesa: fora dele, volta `%Efi.Error{kind: :validation}`, status 422. A
  defesa pela API não substitui o ticket: ela não aceita anexos, e o analista da Efí pode pedir
  documentos pelo ticket. As duas rotas não funcionam em homologação.
  """

  alias Efi.Client

  @doc """
  Lista as infrações abertas entre `inicio` e `fim` (RFC 3339, obrigatórios) em todas as contas
  do documento da conta autenticada.

  `GET /v2/gn/infracoes` · escopo `gn.infractions.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#listar-infrações-med-da-conta)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/gn/infracoes", Keyword.put(opts, :params, params))
  end

  @doc """
  Envia a defesa de uma infração: `analise` e `justificativa`.

  `POST /v2/gn/infracoes/:idInfracao/defesa` · escopo `gn.infractions.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#submeter-defesa-de-infração-med)
  """
  @spec submit_defense(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def submit_defense(%Client{} = client, infraction_id, defense, opts \\ []) do
    path = Client.path("/v2/gn/infracoes/:idInfracao/defesa", idInfracao: infraction_id)
    Client.request(client, :pix, :post, path, Keyword.put(opts, :json, defense))
  end
end
