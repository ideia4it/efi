defmodule Efi.OpenFinance.ImmediatePayment do
  @moduledoc """
  Pix imediato iniciado pelo Open Finance: o pagador aprova no app do banco dele um Pix que o
  seu sistema já preencheu, sem copiar chave nem escanear QR Code.

  ## Fluxo

  1. Configure uma vez o `redirectURL` e o `webhookURL` com `Efi.OpenFinance.Config.put/3`.
  2. O pagador escolhe o banco dele (`Efi.OpenFinance.Participant.list/2`) e informa o CPF.
  3. `create/4` registra o pagamento e devolve `identificadorPagamento` e `redirectURI`. Guarde
     o identificador junto do pedido e leve o pagador ao `redirectURI` (um botão "Pagar pelo
     meu banco", por exemplo).
  4. No banco, o pagador confere e autoriza. O banco devolve o pagador à Efí, que o devolve ao
     seu `redirectURL` com `?identificadorPagamento=urn:...`, mais `&erro=acesso_negado` (ou
     outro código) quando ele recusou ou algo falhou.
  5. O resultado chega pelo webhook. A volta ao `redirectURL` não confirma o pagamento; sem
     webhook, consulte com `list/3` passando `"identificador"`.

  O passo 3, com a chave de idempotência como segundo argumento:

      {:ok, %{"identificadorPagamento" => payment_id, "redirectURI" => bank_url}} =
        Efi.OpenFinance.ImmediatePayment.create(
          client,
          "6f1c2b9e-6a57-4c1e-9d2a-7b3e8f0a1c55",
          %{
            "pagador" => %{
              "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002",
              "cpf" => "12345678909"
            },
            "favorecido" => %{"chave" => "chave-pix-do-studio-ana"},
            "pagamento" => %{
              "valor" => "50.00",
              "infoPagador" => "Corte e escova",
              "idProprio" => "pedido-1234"
            }
          }
        )

  O destino vai em `"favorecido"`, por `"chave"` ou por `"contaBanco"`, ou em
  `"pagamento" => %{"qrCode" => ...}` para pagar um Pix Copia e Cola. Com `"cnpj"` no pagador,
  o `"cpf"` do titular da conta da empresa também é obrigatório.

  ## Chave de idempotência

  O segundo argumento de `create/4` vai no header `x-idempotency-key`, que a Efí exige: de 36
  a 72 caracteres, como um UUID. Com várias requisições iguais ao mesmo tempo, a Efí processa
  só uma; um novo pedido com uma chave já usada volta como
  `%Efi.Error{kind: :conflict, name: "conflito_chave_idempotencia"}`.

  Gere a chave antes da primeira tentativa e guarde junto do pedido. Depois de um timeout,
  repita com a mesma chave: se vier o conflito, a Efí já tinha recebido o pagamento, e ele
  aparece em `list/3` com o `idProprio` que você mandou.

  ## Webhook

  A Efí faz `POST` no `webhookURL` a cada mudança de status, com `"tipo" => "pagamento"` ou
  `"tipo" => "devolucao"`:

      %{
        "identificadorPagamento" => "urn:efi:ae71713f-875b-4af3-9d85-0bcb43288847",
        "endToEndId" => "E09089356202611191500studioana01",
        "valor" => "50.00",
        "status" => "aceito",
        "tipo" => "pagamento"
      }

  O status vai de `pendente` para `aceito`, `rejeitado` (com `"motivo"`), `cancelado` ou
  `expirado` (o pagador nunca abriu o `redirectURI`). Com segurança `hmac`, a Efí acrescenta
  `?hmac=<hash>` à URL e o app deve recusar a notificação sem o hash certo; com `mtls`, o
  servidor exige o certificado da Efí, com TLS 1.2 ou mais novo. Responda 2xx em até 25
  segundos: fora disso a Efí tenta de novo até 10 vezes, a primeira depois de 5 minutos e as
  seguintes em intervalos cada vez maiores.

  ## Homologação

  Em homologação, um pagamento de R$ 0,11 é rejeitado e qualquer outro valor é aceito, e o
  webhook chega nos dois casos.
  """

  alias Efi.Client

  @doc """
  Registra um Pix imediato e devolve o `redirectURI` que leva o pagador ao banco dele.
  `idempotency_key` vai no header `x-idempotency-key`.

  `POST /v1/pagamentos/pix` · escopo `gn.opb.payment.pix.send`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-imediatos#solicitar-iniciação-de-pix-via-open-finance)
  """
  @spec create(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, idempotency_key, payment, opts \\ []) do
    opts = Keyword.merge(opts, json: payment, idempotency_key: idempotency_key)
    Client.request(client, :open_finance, :post, "/v1/pagamentos/pix", opts)
  end

  @doc """
  Lista os pagamentos criados entre `inicio` e `fim` (datas `AAAA-MM-DD`, obrigatórios).
  Filtros opcionais: `status`, `quantidade` (até 50 por página), `pagina` e `identificador`,
  que busca um pagamento só e faz a Efí ignorar os outros filtros. Sem resultado, volta
  `%Efi.Error{kind: :not_found}`.

  `GET /v1/pagamentos/pix` · escopo `gn.opb.payment.pix.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-imediatos#listar-pagamentos-por-um-determinado-período)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    opts = Keyword.put(opts, :params, params)
    Client.request(client, :open_finance, :get, "/v1/pagamentos/pix", opts)
  end

  @doc """
  Devolve ao pagador todo ou parte de um pagamento aceito, com `%{"valor" => "10.00"}`. A
  devolução começa `pendente` e o resultado chega pelo webhook com `"tipo" => "devolucao"`.

  `POST /v1/pagamentos/pix/:identificadorPagamento/devolver` · escopo `gn.opb.payment.pix.refund`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-imediatos#efetuar-uma-devolução-de-um-pagamento)
  """
  @spec refund(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def refund(%Client{} = client, payment_id, refund, opts \\ []) do
    path =
      Client.path("/v1/pagamentos/pix/:identificadorPagamento/devolver",
        identificadorPagamento: payment_id
      )

    Client.request(client, :open_finance, :post, path, Keyword.put(opts, :json, refund))
  end
end
