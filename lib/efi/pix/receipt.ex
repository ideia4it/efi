defmodule Efi.Pix.Receipt do
  @moduledoc """
  Comprovantes em PDF de transações Pix feitas pela API: envio, recebimento e devolução.

      {:ok, pdf} = Efi.Pix.Receipt.get(client, %{"e2eId" => sent["e2eId"]})
      File.write!("comprovante.pdf", pdf)

  A transação é identificada por um parâmetro só, e um por requisição: `e2eId`, `idEnvio`,
  `rtrId` (devolução) ou `txid` (cobrança).
  """

  alias Efi.Client

  @doc """
  Baixa o comprovante de uma transação. O PDF volta como binário.

  `GET /v2/gn/pix/comprovantes` · escopo `gn.receipts.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/endpoints-exclusivos-efi#obter-comprovantes)
  """
  @spec get(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def get(%Client{} = client, params, opts \\ []) do
    Client.request(
      client,
      :pix,
      :get,
      "/v2/gn/pix/comprovantes",
      Keyword.put(opts, :params, params)
    )
  end
end
