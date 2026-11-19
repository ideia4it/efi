defmodule Efi.BillPayments.Payment do
  @moduledoc """
  Pagamento de contas pelo código de barras: boletos e tributos (água, luz, telefone, gás,
  impostos) pagos com o saldo da conta Efí.

  O fluxo tem três passos:

    1. `get_barcode/3` detalha o código de barras. A Efí exige essa consulta antes de cada
       pagamento. O `tipo` da resposta muda o que vem: `"boleto"`, registrado na CIP, traz
       beneficiário, pagador, multa, juros, desconto e, em `informacoesPagamento`, se aceita
       valor divergente ou parcial; `"tributo"`, de concessionárias e convênios, traz só valor
       e vencimento.
    2. `create/4` pede o pagamento para hoje ou para uma data futura. O `valor` é inteiro, em
       centavos (R$ 10,00 é `1000`), ao contrário da API Pix.
    3. `get/3` acompanha a solicitação pelo `idPagamento`, e `summary/3` conta as solicitações
       de um período.

  `get_barcode/3` e `create/4` aceitam o código de barras ou a linha digitável.

      {:ok, bill} = Efi.BillPayments.Payment.get_barcode(client, barcode)

      {:ok, %{"idPagamento" => payment_id}} =
        Efi.BillPayments.Payment.create(client, barcode, %{
          "valor" => bill["valores"]["final"],
          "dataPagamento" => "2026-11-19",
          "descricao" => "Conta de luz do Studio Ana"
        })

  ## Horários e status

  Para pagar no mesmo dia, boletos entram até as 22h, e os acima de R$ 249.000,00 até as 14h.
  Contas de consumo (água, energia, TV a cabo, gás e telefone) e tributos, até as 18h. Depois
  disso, agende para o próximo dia útil.

  O `status` passa por `EM_PROCESSAMENTO`, `AGENDADO`, `EXECUTADO`, `LIQUIDADO`, `CANCELADO` e
  `NAO_REALIZADO` ([tabela da Efí](https://dev.efipay.com.br/docs/api-pagamento-de-contas/status#pagamento-requisitado)).
  Tributos pagos a partir de 28/08/2026 terminam em `EXECUTADO`; os anteriores terminavam em
  `LIQUIDADO`. Quem espera `LIQUIDADO` para dar um tributo por pago espera para sempre.

  Para receber as mudanças de status em vez de consultar, cadastre um
  `Efi.BillPayments.Webhook`.

  Alguns erros desta API vêm como `{"erro": 0, "descricao": "..."}`, fora do formato
  `nome`/`mensagem`; o corpo inteiro fica em `error.body`.
  """

  alias Efi.Client

  @doc """
  Detalha um código de barras antes do pagamento: tipo, banco, datas, beneficiário, pagador,
  valores e se pode ser pago.

  `GET /v1/codBarras/:codBarras` · escopo `gn.barcode.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pagamento-de-contas/pagamentos#detalhar-código-de-barras-para-pagamento)
  """
  @spec get_barcode(Client.t(), String.t(), keyword()) :: Efi.result()
  def get_barcode(%Client{} = client, barcode, opts \\ []) do
    Client.request(client, :bill_payments, :get, barcode_path(barcode), opts)
  end

  @doc """
  Pede o pagamento de um código de barras na `dataPagamento` (`AAAA-MM-DD`, hoje ou depois)
  com o `valor` em centavos. Devolve o `idPagamento` e o `status`.

  `POST /v1/codBarras/:codBarras` · escopo `gn.barcode.pay.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pagamento-de-contas/pagamentos#solicitar-pagamento-de-código-de-barras)
  """
  @spec create(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, barcode, body, opts \\ []) do
    Client.request(
      client,
      :bill_payments,
      :post,
      barcode_path(barcode),
      Keyword.put(opts, :json, body)
    )
  end

  @doc """
  Consulta uma solicitação de pagamento pelo `idPagamento`.

  `GET /v1/:idPagamento` · escopo `gn.barcode.pay.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pagamento-de-contas/pagamentos#consultar-solicitação-de-pagamento)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, payment_id, opts \\ []) do
    path = Client.path("/v1/:idPagamento", idPagamento: payment_id)
    Client.request(client, :bill_payments, :get, path, opts)
  end

  @doc """
  Resume as solicitações de pagamento entre `dataInicio` e `dataFim` (`AAAA-MM-DD`,
  obrigatórios): total, em processamento, com sucesso, com falha e canceladas.

  `GET /v1/resumo` · escopo `gn.barcode.pay.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pagamento-de-contas/pagamentos#consultar-resumo-de-solicitações-de-pagamento)
  """
  @spec summary(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def summary(%Client{} = client, params, opts \\ []) do
    Client.request(client, :bill_payments, :get, "/v1/resumo", Keyword.put(opts, :params, params))
  end

  defp barcode_path(barcode), do: Client.path("/v1/codBarras/:codBarras", codBarras: barcode)
end
