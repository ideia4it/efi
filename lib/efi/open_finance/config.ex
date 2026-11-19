defmodule Efi.OpenFinance.Config do
  @moduledoc """
  Configuração da aplicação na API Open Finance: para onde o pagador volta depois de autorizar
  no banco e para onde a Efí manda as notificações.

  Configure antes do primeiro pagamento. Sem `redirectURL`, o pagador não tem para onde voltar;
  sem `webhookURL`, o app só descobre o resultado consultando a lista de pagamentos.

      {:ok, _settings} =
        Efi.OpenFinance.Config.put(client, %{
          "redirectURL" => "https://app.example.com/open-finance/retorno",
          "webhookURL" => "https://app.example.com/open-finance/webhook",
          "webhookSecurity" => %{"type" => "hmac", "hash" => "segredo-do-studio-ana"},
          "processPayment" => "async"
        })

  `put/3` grava a configuração inteira: um campo que fica de fora volta ao padrão da Efí, então
  mande todos os campos a cada chamada.

    * `"webhookSecurity"` - `%{"type" => "mtls"}` (padrão) exige que o servidor do webhook
      valide o certificado da Efí; `%{"type" => "hmac", "hash" => ...}` faz a Efí acrescentar
      `?hmac=<hash>` à URL de cada notificação, e o app confere o valor;
    * `"processPayment"` - `"sync"` (padrão) mostra a tela da Efí durante o redirecionamento;
      `"async"` pula essa tela, e o resultado só chega pelo webhook ou pela consulta;
    * `"generateTxIdForInic"` - com `true`, a Efí gera um `txid` para os pagamentos feitos por
      chave Pix.

  Na volta ao `redirectURL`, a Efí acrescenta `?identificadorPagamento=urn:...` e, quando o
  pagador recusa ou algo falha, `&erro=acesso_negado` (ou outro código). A volta não confirma o
  pagamento: o status final vem pelo webhook (veja `Efi.OpenFinance.ImmediatePayment`).

  A Efí recomenda ligar `receberSemChave` na configuração da conta na API Pix antes de usar o
  Open Finance, porque o valor errado afeta o recebimento das transações.
  """

  alias Efi.Client

  @doc """
  Cria ou substitui as URLs de retorno e de webhook da aplicação.

  `PUT /v1/config` · escopo `gn.opb.config.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/configuracoes-de-aplicacao#configurar-urls-da-aplicação)
  """
  @spec put(Client.t(), map(), keyword()) :: Efi.result()
  def put(%Client{} = client, settings, opts \\ []) do
    Client.request(client, :open_finance, :put, "/v1/config", Keyword.put(opts, :json, settings))
  end

  @doc """
  Consulta a configuração atual. Sem configuração gravada, volta
  `%Efi.Error{kind: :not_found, name: "configuracao_nao_encontrada"}`.

  `GET /v1/config` · escopo `gn.opb.config.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/configuracoes-de-aplicacao#retornar-as-configurações-da-aplicação)
  """
  @spec get(Client.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, opts \\ []) do
    Client.request(client, :open_finance, :get, "/v1/config", opts)
  end
end
