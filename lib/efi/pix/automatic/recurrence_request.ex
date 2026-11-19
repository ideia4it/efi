defmodule Efi.Pix.Automatic.RecurrenceRequest do
  @moduledoc """
  Solicitação de confirmação de recorrência de Pix Automático (`solicrec`): o pedido que chega
  como notificação no app do banco do pagador para ele autorizar uma recorrência sem ler QR
  Code. É a jornada 1, pensada para negociações feitas fora do Pix, como pelo WhatsApp. O
  fluxo completo está em `Efi.Pix.Automatic.Recurrence`.

  A recorrência é criada antes, sem `loc`, por `Efi.Pix.Automatic.Recurrence.create/3`, e o
  `idRec` dela vai no corpo, com o prazo para o pagador responder e a conta dele:

      {:ok, request} =
        Efi.Pix.Automatic.RecurrenceRequest.create(client, %{
          "idRec" => "RR1234567820261119studioana001",
          "calendario" => %{"dataExpiracaoSolicitacao" => "2026-11-26T12:00:00Z"},
          "destinatario" => %{
            "cpf" => "12345678909",
            "agencia" => "0001",
            "conta" => "123456",
            "ispbParticipante" => "12345678"
          }
        })

  A `destinatario.agencia` é opcional, mas a Efí recomenda sempre enviar: alguns bancos só
  encontram a conta do pagador com ela, e sem ela a solicitação pode nunca chegar ao app.

  A solicitação nasce `CRIADA`. Enquanto estiver `CRIADA` ou `RECEBIDA`, pode ser cancelada
  com `update/4` e `%{"status" => "CANCELADA"}`; em qualquer outro status a Efí recusa com
  `%Efi.Error{kind: :validation, name: "SolicRecOperacaoInvalida"}`. A resposta do pagador
  aparece na recorrência, que passa a `APROVADA`, e chega pelo webhook de recorrência
  (`Efi.Pix.Automatic.Webhook`).
  """

  alias Efi.Client

  @doc """
  Envia ao banco do pagador a solicitação de confirmação de uma recorrência.

  `POST /v2/solicrec` · escopo `solicrec.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#criar-solicitação-de-confirmação-de-recorrência-de-pix-automático)
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(client, :pix, :post, "/v2/solicrec", Keyword.put(opts, :json, body))
  end

  @doc """
  Consulta uma solicitação pelo `idSolicRec`, com o status e a recorrência em `recPayload`.

  `GET /v2/solicrec/:idSolicRec` · escopo `solicrec.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#consultar-solicitação-de-confirmação-de-recorrência-de-pix-automático)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, request_id, opts \\ []) do
    path = Client.path("/v2/solicrec/:idSolicRec", idSolicRec: request_id)
    Client.request(client, :pix, :get, path, opts)
  end

  @doc """
  Revisa uma solicitação. Com `%{"status" => "CANCELADA"}`, cancela uma solicitação que ainda
  está `CRIADA` ou `RECEBIDA`.

  `PATCH /v2/solicrec/:idSolicRec` · escopo `solicrec.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/pix-automatico#revisar-solicitação-de-confirmação-de-recorrência-de-pix-automático)
  """
  @spec update(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def update(%Client{} = client, request_id, changes, opts \\ []) do
    path = Client.path("/v2/solicrec/:idSolicRec", idSolicRec: request_id)
    Client.request(client, :pix, :patch, path, Keyword.put(opts, :json, changes))
  end
end
