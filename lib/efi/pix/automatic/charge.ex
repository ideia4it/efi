defmodule Efi.Pix.Automatic.Charge do
  @moduledoc """
  Cobrança de Pix Automático (`cobr`): o valor de um período de uma recorrência já autorizada,
  que o banco do pagador debita sozinho no vencimento. O fluxo completo, da recorrência aos
  webhooks, está em `Efi.Pix.Automatic.Recurrence`.

  Cada cobrança leva o `idRec` da recorrência aprovada, a `calendario.dataDeVencimento`, o
  `valor.original` e a conta do recebedor (`recebedor.agencia`, `conta` e `tipoConta`). Com
  `"ajusteDiaUtil" => true`, um vencimento em dia não útil passa para o dia útil seguinte.

      {:ok, charge} =
        Efi.Pix.Automatic.Charge.create(client, %{
          "idRec" => "RR1234567820261119studioana001",
          "infoAdicional" => "Plano mensal de escova, dezembro",
          "calendario" => %{"dataDeVencimento" => "2026-12-10"},
          "valor" => %{"original" => "150.00"},
          "ajusteDiaUtil" => true,
          "devedor" => %{
            "cep" => "01001000",
            "cidade" => "São Paulo",
            "email" => "cliente@app.example.com",
            "logradouro" => "Rua do Studio Ana 100",
            "uf" => "SP"
          },
          "recebedor" => %{"agencia" => "0001", "conta" => "123456", "tipoConta" => "PAGAMENTO"}
        })

  `create/3` deixa a Efí escolher o `txid`; `create_with_txid/4` usa o seu, o que torna a
  criação segura para repetir depois de um timeout.

  A cobrança nasce `CRIADA` e passa a `ATIVA`. Cada débito tentado aparece em `tentativas`, com
  `dataLiquidacao`, `tipo` e `status`. Para cancelar, `update/4` com
  `%{"status" => "CANCELADA"}`, mas só antes da data prevista da primeira tentativa de
  liquidação: a partir dela a Efí recusa com `%Efi.Error{kind: :validation, name:
  "CobROperacaoInvalida"}`.

  Se uma tentativa falhar, `retry/4` agenda outra numa data, desde que a
  `politicaRetentativa` da recorrência seja `PERMITE_3R_7D`. Com `NAO_PERMITE`, a Efí recusa com
  `CobROperacaoInvalida`.
  """

  alias Efi.Client

  @doc """
  Cria uma cobrança de Pix Automático sem `txid`: a Efí gera o identificador e o devolve na
  resposta.

  `POST /v2/cobr` · escopo `cobr.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#criar-cobrança-de-pix-automático-sem-txid)
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(client, :pix, :post, "/v2/cobr", Keyword.put(opts, :json, body))
  end

  @doc """
  Cria uma cobrança de Pix Automático com o `txid` informado.

  `PUT /v2/cobr/:txid` · escopo `cobr.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#criar-cobrança-de-pix-automático-com-txid)
  """
  @spec create_with_txid(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create_with_txid(%Client{} = client, txid, body, opts \\ []) do
    path = Client.path("/v2/cobr/:txid", txid: txid)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Revisa uma cobrança. Com `%{"status" => "CANCELADA"}`, cancela a cobrança antes da data
  prevista da primeira tentativa de liquidação.

  `PATCH /v2/cobr/:txid` · escopo `cobr.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#revisar-cobrança-de-pix-automático)
  """
  @spec update(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def update(%Client{} = client, txid, changes, opts \\ []) do
    path = Client.path("/v2/cobr/:txid", txid: txid)
    Client.request(client, :pix, :patch, path, Keyword.put(opts, :json, changes))
  end

  @doc """
  Consulta uma cobrança pelo `txid`, com as `tentativas` de liquidação.

  `GET /v2/cobr/:txid` · escopo `cobr.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#consultar-cobrança-de-pix-automático)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, txid, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/cobr/:txid", txid: txid), opts)
  end

  @doc """
  Lista as cobranças entre `inicio` e `fim` (RFC 3339, obrigatórios). Aceita filtros como
  `idRec`, `cpf`, `cnpj`, `status` e `convenio`. As cobranças voltam em `cobsr`.

  `GET /v2/cobr` · escopo `cobr.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#consultar-lista-de-cobranças-de-pix-automático)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/cobr", Keyword.put(opts, :params, params))
  end

  @doc """
  Pede uma nova tentativa de liquidação da cobrança na data informada (`Date` ou
  `"AAAA-MM-DD"`). A nova tentativa aparece em `tentativas`.

  `POST /v2/cobr/:txid/retentativa/:data` · escopo `cobr.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#solicitar-retentativa-de-pix-automático)
  """
  @spec retry(Client.t(), String.t(), Date.t() | String.t(), keyword()) :: Efi.result()
  def retry(%Client{} = client, txid, settlement_date, opts \\ []) do
    path = Client.path("/v2/cobr/:txid/retentativa/:data", txid: txid, data: settlement_date)
    Client.request(client, :pix, :post, path, opts)
  end
end
