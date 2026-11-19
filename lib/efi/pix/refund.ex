defmodule Efi.Pix.Refund do
  @moduledoc """
  Devolução de um Pix recebido, total ou parcial, pelo `e2eId` do Pix.

  O `id` da devolução é escolhido por quem devolve (até 35 letras e números) e é único por Pix:
  repetir o mesmo `id` volta como `%Efi.Error{kind: :conflict, name: "devolucao_id_duplicado"}`
  em vez de devolver duas vezes, o que torna `create/5` seguro para repetir depois de um timeout.
  A soma das devoluções de um Pix não passa do valor dele.

      {:ok, refund} =
        Efi.Pix.Refund.create(
          client,
          "E12345678202611191200abcdef12345",
          "devolucaoStudioAna1",
          %{"valor" => "20.00"}
        )

      refund["status"]

  A devolução é assíncrona: nasce `EM_PROCESSAMENTO` e termina `DEVOLVIDO` ou `NAO_REALIZADO`,
  este com o `motivo`. O resultado chega pelo webhook Pix e por `get/4`.

  Em homologação, devoluções de R$ 0,01 são recusadas de propósito, para simular a falha; os
  outros valores seguem o fluxo normal. Pix repassados a outras contas por split não podem ser
  devolvidos.
  """

  alias Efi.Client

  @doc """
  Solicita a devolução de um Pix recebido, com o `id` de devolução informado.

  `PUT /v2/pix/:e2eId/devolucao/:id` · escopo `pix.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/gestao-de-pix#solicitar-devolução)
  """
  @spec create(Client.t(), String.t(), String.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, e2e_id, refund_id, body, opts \\ []) do
    path = Client.path("/v2/pix/:e2eId/devolucao/:id", e2eId: e2e_id, id: refund_id)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Consulta uma devolução pelo `e2eId` do Pix e pelo `id` da devolução.

  `GET /v2/pix/:e2eId/devolucao/:id` · escopo `pix.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/gestao-de-pix#consultar-devolução)
  """
  @spec get(Client.t(), String.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, e2e_id, refund_id, opts \\ []) do
    path = Client.path("/v2/pix/:e2eId/devolucao/:id", e2eId: e2e_id, id: refund_id)
    Client.request(client, :pix, :get, path, opts)
  end
end
