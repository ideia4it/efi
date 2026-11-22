defmodule Efi.Pix.DueCharge do
  @moduledoc """
  Cobrança Pix com vencimento (`cobv`): o boleto do Pix, com data de vencimento e multa, juros,
  abatimento e desconto aplicados conforme o dia do pagamento.

  O `txid` é sempre escolhido por quem cobra (de 26 a 35 caracteres, só letras e números), então
  a criação é um `PUT` seguro para repetir depois de um timeout: o mesmo `txid` nunca vira duas
  cobranças.

  `devedor` é obrigatório, com `nome` e `cpf` ou `cnpj` (nunca os dois). A cobrança pode ser paga
  até `calendario.dataDeVencimento`, prorrogada para o primeiro dia útil se cair em fim de semana
  ou feriado, e depois disso por mais `calendario.validadeAposVencimento` dias corridos, já com
  multa e juros. Se o último desses dias não for útil, o prazo também passa para o próximo dia
  útil
  ([exemplos da Efí](https://dev.efipay.com.br/docs/api-pix/glossario#ilustração-do-funcionamento-das-cobranças-cobv-após-a-data-de-vencimento)).

      {:ok, charge} =
        Efi.Pix.DueCharge.create(client, "studioana0000000000000000001", %{
          "calendario" => %{"dataDeVencimento" => "2026-12-10", "validadeAposVencimento" => 30},
          "devedor" => %{"cpf" => "12345678909", "nome" => "Cliente do Studio Ana"},
          "valor" => %{
            "original" => "120.00",
            "multa" => %{"modalidade" => 2, "valorPerc" => "2.00"},
            "juros" => %{"modalidade" => 2, "valorPerc" => "0.03"}
          },
          "chave" => "chave-pix-do-studio-ana",
          "solicitacaoPagador" => "Pacote de quatro sessões"
        })

      charge["pixCopiaECola"]

  Para cancelar, revise o status com `update/4` e
  `%{"status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"}`. Só cobranças `ATIVA` aceitam revisão: as
  outras voltam como `%Efi.Error{kind: :validation, name: "CobVOperacaoInvalida"}`.

  Em homologação, cobranças de R$ 0,01 a R$ 10,00 são pagas sozinhas e disparam o webhook;
  acima disso ficam ativas sem pagamento.

  Para reservar o QR Code antes da cobrança, crie um location com `Efi.Pix.Location.create/3` e
  `%{"tipoCob" => "cobv"}` e passe `"loc" => %{"id" => id}` no corpo. A imagem do QR Code sai de
  `Efi.Pix.Location.get_qr_code/3` com o `loc.id` da resposta. Para criar muitas cobranças numa
  chamada só, veja `Efi.Pix.DueChargeBatch`.
  """

  alias Efi.Client

  @doc """
  Cria uma cobrança com vencimento com o `txid` informado.

  `PUT /v2/cobv/:txid` · escopo `cobv.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-com-vencimento#criar-cobrança-com-vencimento)
  """
  @spec create(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, txid, body, opts \\ []) do
    path = Client.path("/v2/cobv/:txid", txid: txid)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Revisa uma cobrança com vencimento: muda os campos enviados e incrementa a `revisao`. Com
  `%{"status" => "REMOVIDA_PELO_USUARIO_RECEBEDOR"}`, cancela a cobrança.

  `PATCH /v2/cobv/:txid` · escopo `cobv.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-com-vencimento#revisar-cobrança-com-vencimento)
  """
  @spec update(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def update(%Client{} = client, txid, changes, opts \\ []) do
    path = Client.path("/v2/cobv/:txid", txid: txid)
    Client.request(client, :pix, :patch, path, Keyword.put(opts, :json, changes))
  end

  @doc """
  Consulta uma cobrança com vencimento pelo `txid`. Para uma revisão anterior, passe
  `params: %{"revisao" => 1}`.

  `GET /v2/cobv/:txid` · escopo `cobv.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-com-vencimento#consultar-cobrança-com-vencimento)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, txid, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/cobv/:txid", txid: txid), opts)
  end

  @doc """
  Lista as cobranças com vencimento criadas entre `inicio` e `fim` (RFC 3339, obrigatórios).
  Filtros opcionais: `cpf`, `cnpj`, `status`, `locationPresente`, `loteCobVId`,
  `paginacao.paginaAtual` e `paginacao.itensPorPagina`.

  `GET /v2/cobv` · escopo `cobv.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/cobrancas-com-vencimento#consultar-lista-de-cobranças-com-vencimento)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/cobv", Keyword.put(opts, :params, params))
  end
end
