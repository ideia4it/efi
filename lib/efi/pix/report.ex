defmodule Efi.Pix.Report do
  @moduledoc """
  Extrato de conciliação Pix: um CSV com as movimentações de um dia (Pix recebidos, enviados,
  devoluções, tarifas, transferências e saldos), para conferir a conta contra o seu sistema.

  O extrato é gerado em segundo plano. Peça com `create_reconciliation/3`, guarde o `id` e baixe
  com `get/3`. A Efí leva em média 30 segundos para processar, então espere antes do primeiro
  `get/3`.

      {:ok, %{"id" => id}} =
        Efi.Pix.Report.create_reconciliation(client, %{
          "dataMovimento" => "2026-11-18",
          "tipoRegistros" => %{"pixRecebido" => true, "tarifaPixRecebido" => true}
        })

      case Efi.Pix.Report.get(client, id) do
        {:ok, csv} when is_binary(csv) -> csv
        {:ok, %{"status" => _still_processing}} -> :try_again_later
      end

  `dataMovimento` precisa ser anterior a hoje. Pedir de novo com os mesmos parâmetros devolve o
  mesmo `id`, já com status `CONCLUIDO` quando o arquivo existe. Se o download falhar com erro
  interno, a Efí orienta pedir um extrato novo.
  """

  alias Efi.Client

  @doc """
  Pede o extrato de conciliação de `dataMovimento`, com os tipos de registro em
  `tipoRegistros`. A resposta traz o `id` e o status (`AGUARDANDO_PROCESSAMENTO`,
  `EM_PROCESSAMENTO` ou `CONCLUIDO`).

  `POST /v2/gn/relatorios/extrato-conciliacao` · escopo `gn.reports.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#requisitar-extrato-conciliação-pix)
  """
  @spec create_reconciliation(Client.t(), map(), keyword()) :: Efi.result()
  def create_reconciliation(%Client{} = client, body, opts \\ []) do
    Client.request(
      client,
      :pix,
      :post,
      "/v2/gn/relatorios/extrato-conciliacao",
      Keyword.put(opts, :json, body)
    )
  end

  @doc """
  Baixa um extrato pedido. Pronto, o CSV volta como binário; ainda em processamento, volta o
  mapa com o `status`.

  `GET /v2/gn/relatorios/:id` · escopo `gn.reports.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#solicitar-download-extrato-conciliação)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, id, opts \\ []) do
    Client.request(client, :pix, :get, Client.path("/v2/gn/relatorios/:id", id: id), opts)
  end
end
