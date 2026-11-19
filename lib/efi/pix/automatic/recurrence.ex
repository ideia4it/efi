defmodule Efi.Pix.Automatic.Recurrence do
  @moduledoc """
  Recorrência de Pix Automático (`rec`): a autorização que o pagador dá uma única vez no app do
  banco para que o recebedor cobre todo período sem pedir um Pix por vez. É o recurso que
  substitui o débito automático em assinaturas, planos e mensalidades.

  Exige uma Conta Digital Efí Empresas.

  ## O fluxo inteiro

  1. **Recorrência.** `create/3` registra o contrato: `vinculo` (`contrato`, `devedor`,
     `objeto`), `calendario` (`dataInicial`, `periodicidade` como `MENSAL` ou `ANUAL`, e
     `dataFinal` opcional), `valor` (`valorRec` para valor fixo, ou `valorMinimoRecebedor`
     quando o valor muda a cada período) e `politicaRetentativa` (`NAO_PERMITE` ou
     `PERMITE_3R_7D`). Ao contrário do resto da API Pix, o identificador (`idRec`) é sempre
     gerado pela Efí. A recorrência nasce `CRIADA` e passa a `APROVADA` quando o pagador
     autoriza.
  2. **Location.** Nas jornadas com QR Code, a recorrência precisa de uma location própria,
     criada antes por `Efi.Pix.Automatic.Location.create/2` e informada no campo `loc`.
  3. **Solicitação de confirmação.** Na jornada sem QR Code,
     `Efi.Pix.Automatic.RecurrenceRequest.create/3` pede ao banco do pagador que mostre a
     autorização no app dele. Nas jornadas com QR Code, `get/3` devolve o
     `dadosQR.pixCopiaECola` que o pagador lê.
  4. **Cobranças.** Com a recorrência aprovada, cada período vira uma cobrança de
     `Efi.Pix.Automatic.Charge` com o `idRec` e a `calendario.dataDeVencimento`. O banco do
     pagador debita na data, sem ação dele.
  5. **Retentativa.** Se a liquidação falhar e a recorrência permitir (`PERMITE_3R_7D`),
     `Efi.Pix.Automatic.Charge.retry/4` agenda uma nova tentativa numa data.
  6. **Webhooks.** As mudanças de status de recorrências e de cobranças chegam por dois
     webhooks próprios, configurados em `Efi.Pix.Automatic.Webhook`, separados do webhook Pix
     comum.

  ## Jornadas de autorização

  | Jornada | Para quem | Passos |
  |---|---|---|
  | 1, notificação no app | negociação feita fora do Pix, como pelo WhatsApp | `create/3` sem `loc`; `RecurrenceRequest.create/3` com o `idRec` |
  | 2, QR Code | cobrança automática a partir do próximo período, sem pagamento agora | `Location.create/2`; `create/3` com `loc`; `get/3` para o copia e cola |
  | 3, QR Code com pagamento à vista | o primeiro pagamento entra na hora e a recorrência vem na mesma autorização | `Location.create/2`; uma cobrança imediata (`Efi.Pix.ImmediateCharge`); `create/3` com `loc` e `ativacao.dadosJornada.txid`; `get/3` com `params: %{"txid" => txid}` |
  | 4, fatura com QR Code | quem já envia fatura mensal com QR Code | `Location.create/2`; uma cobrança com vencimento (`PUT /v2/cobv/:txid`); `create/3` com `loc`; `get/3` com `params: %{"txid" => txid}` |

  Depois da autorização, as quatro seguem iguais: uma cobrança de `Efi.Pix.Automatic.Charge`
  por período.

  ## Exemplo, jornada 1

      {:ok, recurrence} =
        Efi.Pix.Automatic.Recurrence.create(client, %{
          "vinculo" => %{
            "contrato" => "plano-mensal-0001",
            "devedor" => %{"cpf" => "12345678909", "nome" => "Cliente do Studio Ana"},
            "objeto" => "Plano mensal de escova"
          },
          "calendario" => %{"dataInicial" => "2026-12-01", "periodicidade" => "MENSAL"},
          "valor" => %{"valorRec" => "150.00"},
          "politicaRetentativa" => "PERMITE_3R_7D"
        })

      {:ok, _request} =
        Efi.Pix.Automatic.RecurrenceRequest.create(client, %{
          "idRec" => recurrence["idRec"],
          "calendario" => %{"dataExpiracaoSolicitacao" => "2026-11-26T12:00:00Z"},
          "destinatario" => %{
            "cpf" => "12345678909",
            "agencia" => "0001",
            "conta" => "123456",
            "ispbParticipante" => "12345678"
          }
        })

  Os erros do Pix Automático seguem o padrão do Banco Central: o `name` do `%Efi.Error{}` é o
  fim do `type` (`"RecOperacaoInvalida"`, `"NaoEncontrado"`) e o `message` é o `detail`. As
  `violacoes` ficam em `body`.
  """

  alias Efi.Client

  @doc """
  Cria uma recorrência. O `idRec` é gerado pela Efí e volta na resposta, com `status`
  `CRIADA`. Sem `loc`, a autorização segue pela solicitação de confirmação (jornada 1).

  `POST /v2/rec` · escopo `rec.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#criar-recorrência-de-pix-automático)
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(client, :pix, :post, "/v2/rec", Keyword.put(opts, :json, body))
  end

  @doc """
  Consulta uma recorrência pelo `idRec`, com o status, o pagador e, nas jornadas com QR Code,
  o `dadosQR.pixCopiaECola`. Nas jornadas 3 e 4, passe o `txid` da cobrança imediata ou com
  vencimento em `params: %{"txid" => txid}` para o copia e cola trazer também essa cobrança.

  `GET /v2/rec/:idRec` · escopo `rec.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#consultar-recorrência-de-pix-automático)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, recurrence_id, opts \\ []) do
    path = Client.path("/v2/rec/:idRec", idRec: recurrence_id)
    Client.request(client, :pix, :get, path, opts)
  end

  @doc """
  Revisa uma recorrência, mudando só os campos enviados, como `loc`, `vinculo.devedor.nome`,
  `calendario.dataInicial` e `ativacao.dadosJornada.txid`.

  `PATCH /v2/rec/:idRec` · escopo `rec.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#revisar-recorrência-de-pix-automático)
  """
  @spec update(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def update(%Client{} = client, recurrence_id, changes, opts \\ []) do
    path = Client.path("/v2/rec/:idRec", idRec: recurrence_id)
    Client.request(client, :pix, :patch, path, Keyword.put(opts, :json, changes))
  end

  @doc """
  Lista as recorrências entre `inicio` e `fim` (RFC 3339, obrigatórios). Aceita filtros como
  `cpf`, `cnpj` e `status`, e a paginação em `paginacao.paginaAtual` e
  `paginacao.itensPorPagina`.

  `GET /v2/rec` · escopo `rec.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#consultar-lista-de-recorrências-de-pix-automático)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/rec", Keyword.put(opts, :params, params))
  end
end
