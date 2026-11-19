defmodule Efi.Pix.Split do
  @moduledoc """
  Split de pagamento Pix: divide o valor de uma cobrança entre a conta que recebe e outras
  contas Efí no momento do pagamento.

  É o recurso que um parceiro usa para ficar com a parte dele. O cliente paga um Pix só, o
  dinheiro cai na conta do negócio e a Efí repassa na hora a fatia de cada conta da
  configuração, sem transferência manual depois e sem o parceiro tocar no dinheiro do negócio.

  ## O fluxo

  1. Crie a configuração de split com `create_config/3` (a Efí escolhe o `id`) ou
     `create_config_with_id/4` (você escolhe). Ela diz quanto fica na conta que recebe
     (`minhaParte`) e quanto vai para cada conta em `repasses`.
  2. Crie a cobrança como sempre: `Efi.Pix.ImmediateCharge.create_with_txid/4` para uma
     cobrança imediata (`cob`), ou uma cobrança com vencimento (`cobv`).
  3. Vincule a cobrança à configuração com `link_charge/4` (`cob`) ou `link_due_charge/4`
     (`cobv`), enquanto a cobrança está `ATIVA`.

  Quando a cobrança é paga, a Efí divide o valor e registra cada parte, com conta, valor,
  tarifa e data, no campo `split` que `get_charge/3` e `get_due_charge/3` devolvem.

      {:ok, config} =
        Efi.Pix.Split.create_config(client, %{
          "descricao" => "Comissão do app nos atendimentos do Studio Ana",
          "lancamento" => %{"imediato" => true},
          "split" => %{
            "divisaoTarifa" => "assumir_total",
            "minhaParte" => %{"tipo" => "porcentagem", "valor" => "95.00"},
            "repasses" => [
              %{
                "tipo" => "porcentagem",
                "valor" => "5.00",
                "favorecido" => %{"cpf" => "12345678909", "conta" => "1234567"}
              }
            ]
          }
        })

      {:ok, _charge} = Efi.Pix.ImmediateCharge.create_with_txid(client, txid, charge)
      {:ok, nil} = Efi.Pix.Split.link_charge(client, txid, config["id"])

  Uma configuração serve a quantas cobranças você quiser: se a fatia do parceiro é a mesma em
  todas, basta uma. Para um QR Code ou copia e cola estático, informe o `txid` dele na própria
  configuração.

  ## Regras da Efí

    * Os repasses só vão para contas Efí, no máximo 20, identificadas pelo número da `conta` e
      pelo documento do titular. A Efí recusa a configuração se a conta não existe ou se o
      documento não é o da conta.
    * Não dá para repassar para a própria conta. Em homologação, crie uma subconta para fazer o
      papel do parceiro.
    * Em porcentagem, `minhaParte` e os repasses somam exatamente 100%. Em valor fixo, o valor
      da cobrança precisa ser igual à soma dos valores fixos, senão o vínculo é recusado.
      Porcentagens que já somam 100% não aceitam valor fixo junto.
    * Por enquanto o repasse só acontece na hora: `lancamento.imediato` é `true`.
    * `divisaoTarifa` diz quem arca com a tarifa do Pix; os exemplos da Efí usam
      `"assumir_total"`.
    * O vínculo só pode ser feito ou desfeito com a cobrança `ATIVA`. Depois de paga, desvincular
      volta como `%Efi.Error{kind: :validation}`.
    * `create_config_with_id/4` com um `id` que já existe altera a configuração e cria uma nova
      revisão; `get_config/3` lê qualquer revisão. A Efí avisa que a consulta da configuração
      está temporariamente desativada para manutenção.

  ## Devolução

  `refund/5` devolve ao pagador parte ou todo o Pix de uma cobrança com split, e debita tudo da
  conta integradora, a que criou a configuração. As contas que receberam repasse não são
  debitadas nem avisadas: num modelo de parceria, a devolução sai inteira da conta do negócio, e
  acertar a parte do parceiro fica fora da Efí.
  """

  alias Efi.Client

  @doc """
  Cria uma configuração de split; a Efí gera o `id` e o devolve na resposta.

  `POST /v2/gn/split/config` · escopo `gn.split.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/split-de-pagamento-pix#configuração-de-um-split-de-pagamento-sem-passar-id)
  """
  @spec create_config(Client.t(), map(), keyword()) :: Efi.result()
  def create_config(%Client{} = client, config, opts \\ []) do
    Client.request(client, :pix, :post, "/v2/gn/split/config", Keyword.put(opts, :json, config))
  end

  @doc """
  Cria a configuração de split com o `id` informado ou, se ele já existe, altera a
  configuração e cria uma nova revisão.

  `PUT /v2/gn/split/config/:id` · escopo `gn.split.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/split-de-pagamento-pix#configuração-de-um-split-de-pagamento-com-id)
  """
  @spec create_config_with_id(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create_config_with_id(%Client{} = client, id, config, opts \\ []) do
    path = Client.path("/v2/gn/split/config/:id", id: id)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, config))
  end

  @doc """
  Consulta uma configuração de split. Sem parâmetros, volta a revisão mais recente; para uma
  anterior, passe `params: %{"revisao" => 1}`.

  `GET /v2/gn/split/config/:id` · escopo `gn.split.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/split-de-pagamento-pix#consultar-configuração-do-split-por-id)
  """
  @spec get_config(Client.t(), String.t(), keyword()) :: Efi.result()
  def get_config(%Client{} = client, id, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/gn/split/config/:id", id: id), opts)
  end

  @doc """
  Vincula uma cobrança imediata `ATIVA` a uma configuração de split. A Efí responde 204, que
  volta como `{:ok, nil}`.

  `PUT /v2/gn/split/cob/:txid/vinculo/:splitConfigId` · escopo `gn.split.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/split-de-pagamento-pix#vincular-uma-cobrança-a-um-split-de-pagamento)
  """
  @spec link_charge(Client.t(), String.t(), String.t(), keyword()) :: Efi.result()
  def link_charge(%Client{} = client, txid, split_config_id, opts \\ []) do
    path =
      Client.path("/v2/gn/split/cob/:txid/vinculo/:splitConfigId",
        txid: txid,
        splitConfigId: split_config_id
      )

    Client.request(client, :pix, :put, path, opts)
  end

  @doc """
  Consulta uma cobrança imediata com split: a cobrança, a configuração vinculada e, depois do
  pagamento, a parte de cada conta em `split`.

  `GET /v2/gn/split/cob/:txid` · escopo `gn.split.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/split-de-pagamento-pix#consultar-cobrança-com-split-de-pagamento-por-txid)
  """
  @spec get_charge(Client.t(), String.t(), keyword()) :: Efi.result()
  def get_charge(%Client{} = client, txid, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/gn/split/cob/:txid", txid: txid), opts)
  end

  @doc """
  Desfaz o vínculo entre uma cobrança imediata `ATIVA` e a configuração de split.

  `DELETE /v2/gn/split/cob/:txid/vinculo` · escopo `gn.split.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/split-de-pagamento-pix#deletar-o-vínculo-entre-um-split-de-pagamento-e-uma-cobrança)
  """
  @spec unlink_charge(Client.t(), String.t(), keyword()) :: Efi.result()
  def unlink_charge(%Client{} = client, txid, opts \\ []) do
    path = Client.path("/v2/gn/split/cob/:txid/vinculo", txid: txid)
    Client.request(client, :pix, :delete, path, opts)
  end

  @doc """
  Vincula uma cobrança com vencimento `ATIVA` a uma configuração de split.

  `PUT /v2/gn/split/cobv/:txid/vinculo/:splitConfigId` · escopo `gn.split.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/split-de-pagamento-pix#vincular-uma-cobrança-com-vencimento-a-um-split-de-pagamento-por-txid)
  """
  @spec link_due_charge(Client.t(), String.t(), String.t(), keyword()) :: Efi.result()
  def link_due_charge(%Client{} = client, txid, split_config_id, opts \\ []) do
    path =
      Client.path("/v2/gn/split/cobv/:txid/vinculo/:splitConfigId",
        txid: txid,
        splitConfigId: split_config_id
      )

    Client.request(client, :pix, :put, path, opts)
  end

  @doc """
  Consulta uma cobrança com vencimento e com split, como `get_charge/3`.

  `GET /v2/gn/split/cobv/:txid` · escopo `gn.split.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/split-de-pagamento-pix#consultar-cobrança-com-vencimento-e-com-split-de-pagamento-por-txid)
  """
  @spec get_due_charge(Client.t(), String.t(), keyword()) :: Efi.result()
  def get_due_charge(%Client{} = client, txid, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/gn/split/cobv/:txid", txid: txid), opts)
  end

  @doc """
  Desfaz o vínculo entre uma cobrança com vencimento `ATIVA` e a configuração de split.

  `DELETE /v2/gn/split/cobv/:txid/vinculo` · escopo `gn.split.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/split-de-pagamento-pix#deletar-o-vínculo-entre-um-split-de-pagamento-e-uma-cobrança-com-vencimento)
  """
  @spec unlink_due_charge(Client.t(), String.t(), keyword()) :: Efi.result()
  def unlink_due_charge(%Client{} = client, txid, opts \\ []) do
    path = Client.path("/v2/gn/split/cobv/:txid/vinculo", txid: txid)
    Client.request(client, :pix, :delete, path, opts)
  end

  @doc """
  Devolve ao pagador o `valor` informado de um Pix recebido numa cobrança com split. O `id` da
  devolução é seu e não se repete no mesmo Pix: repetir volta como
  `%Efi.Error{kind: :conflict}`, o que torna a chamada segura para repetir. A Efí recusa a
  devolução de um Pix sem split e de um Pix recebido há mais de 90 dias.

  `PUT /v2/gn/split/pix/:e2eid/devolucao/:id` · escopo `gn.pix.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/split-de-pagamento-pix#solicitar-devolução-de-uma-cobrança-pix-com-split-de-pagamento)
  """
  @spec refund(Client.t(), String.t(), String.t(), map(), keyword()) :: Efi.result()
  def refund(%Client{} = client, e2e_id, refund_id, body, opts \\ []) do
    path = Client.path("/v2/gn/split/pix/:e2eid/devolucao/:id", e2eid: e2e_id, id: refund_id)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, body))
  end
end
