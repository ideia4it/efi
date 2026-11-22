defmodule Efi.Pix.Send do
  @moduledoc """
  Envio de Pix pela API: transferência para uma chave Pix ou para dados bancários, e pagamento
  de um QR Code de outra pessoa.

  O `idEnvio` é escolhido por você e identifica o envio, por isso a rota é idempotente: repetir
  o `PUT` com o mesmo `idEnvio` nunca debita duas vezes. Guarde o `idEnvio` antes de chamar e
  use um novo só para um envio novo. Ele é único também entre envios e pagamentos de QR Code.

      {:ok, sent} =
        Efi.Pix.Send.send(client, "studioana0000000000000000001", %{
          "valor" => "12.34",
          "pagador" => %{
            "chave" => "chave-pix-do-studio-ana",
            "infoPagador" => "Repasse de novembro"
          },
          "favorecido" => %{"chave" => "chave-pix-do-fornecedor"}
        })

      sent["status"]
      #=> "EM_PROCESSAMENTO"

  O envio é assíncrono: a resposta volta `EM_PROCESSAMENTO` e o resultado chega pelo webhook
  Pix da chave do pagador, por isso essa chave precisa ter um webhook cadastrado antes do
  primeiro envio. Para não disputar saldo, a Efí recomenda esperar o webhook de um envio antes
  de pedir o próximo.

  ## Falha no meio do envio

  Um erro 5xx ou um timeout não quer dizer que o Pix não saiu: a Efí pode ter processado o
  envio. Não peça de novo com outro `idEnvio`. Espere o webhook ou consulte com
  `get_by_send_id/3`; se precisar repetir, repita com o mesmo `idEnvio`. A biblioteca não
  repete sozinha um `PUT` que pode ter chegado à Efí (veja `Efi.Client`).

  ## Escopos e limites

  Cada rota exige o escopo dela liberado na aplicação. Aplicações criadas antes de 29/07/2024
  precisam desativar e ativar de novo o escopo `pix.send`. Quando um parceiro pede a conta de um
  cliente que já tem conta Efí (`Efi.Accounts.SimplifiedAccount`) e o cliente escolhe criar só
  uma aplicação na conta atual, essa aplicação nunca recebe `pix.send`, `gn.pix.send.read`,
  `gn.qrcodes.pay` e `gn.qrcodes.read`: o parceiro não envia Pix por ela.

  Em produção, cada conta tem um limite diário de envio pré-aprovado, e só conta Efí Empresas
  pode alterá-lo. Envio para chave também consome fichas do balde da conta. Com o balde vazio, o
  envio volta `%Efi.Error{kind: :rate_limited}` com `error.headers["retry-after"]`, os segundos
  que a Efí pede para esperar, e a biblioteca não repete o envio sozinha. A Efí informa as fichas
  restantes no header `Bucket-Size` das respostas do envio, mas a biblioteca só devolve headers
  no erro: para saber as fichas antes de enviar, use `Efi.Pix.Account.get_key_buckets/2`.

  ## Homologação

  O valor decide o resultado: de R$ 0,01 a R$ 10,00 o envio é confirmado pelo webhook, de
  R$ 10,01 a R$ 20,00 é rejeitado pelo webhook, e acima de R$ 20,00 é recusado já na resposta,
  sem webhook. Um envio de R$ 4,00 gera duas devoluções recebidas de R$ 2,00, e um de R$ 5,00
  gera uma devolução de R$ 5,00. Envio para chave só funciona com a chave de testes da Efí,
  `efipay@sejaefi.com.br`; outra chave volta como chave inválida. O envio para mesma
  titularidade e o pagamento de QR Code só existem em produção.
  """

  alias Efi.Client

  @doc """
  Envia um Pix para uma chave (`favorecido.chave`) ou para dados bancários
  (`favorecido.contaBanco`). Com `favorecido.cpf`, a Efí recusa o envio se a chave não for
  desse documento.

  `PUT /v3/gn/pix/:idEnvio` · escopo `pix.send`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/envio-pagamento-pix#requisitar-envio-de-pix)
  """
  @spec send(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def send(%Client{} = client, send_id, body, opts \\ []) do
    path = Client.path("/v3/gn/pix/:idEnvio", idEnvio: send_id)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Envia um Pix para outra conta do mesmo titular, na Efí ou em outra instituição. A Efí recusa
  o envio se a chave ou a conta do favorecido for de outro documento. Só existe em produção.

  `PUT /v2/gn/pix/:idEnvio/mesma-titularidade` · escopo `gn.pix.sameownership.send`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/envio-pagamento-pix#requisitar-envio-de-pix-para-contas-de-mesma-titularidade)
  """
  @spec send_to_same_owner(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def send_to_same_owner(%Client{} = client, send_id, body, opts \\ []) do
    path = Client.path("/v2/gn/pix/:idEnvio/mesma-titularidade", idEnvio: send_id)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Consulta um Pix enviado pelo `endToEndId` (o `e2eId` da resposta do envio).

  `GET /v2/gn/pix/enviados/:e2eId` · escopo `gn.pix.send.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/envio-pagamento-pix#consultar-pix-enviado-através-do-endtoendid)
  """
  @spec get(Client.t(), String.t(), keyword()) :: Efi.result()
  def get(%Client{} = client, e2e_id, opts \\ []) do
    path = Client.path("/v2/gn/pix/enviados/:e2eId", e2eId: e2e_id)
    Client.request(client, :pix, :get, path, opts)
  end

  @doc """
  Consulta um Pix enviado pelo `idEnvio`. É a consulta certa depois de uma falha no envio,
  quando ainda não se sabe o `e2eId`.

  `GET /v2/gn/pix/enviados/id-envio/:idEnvio` · escopo `gn.pix.send.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/envio-pagamento-pix#consultar-pix-enviado-através-do-identificador-da-transação)
  """
  @spec get_by_send_id(Client.t(), String.t(), keyword()) :: Efi.result()
  def get_by_send_id(%Client{} = client, send_id, opts \\ []) do
    path = Client.path("/v2/gn/pix/enviados/id-envio/:idEnvio", idEnvio: send_id)
    Client.request(client, :pix, :get, path, opts)
  end

  @doc """
  Lista os Pix enviados entre `inicio` e `fim` (RFC 3339, obrigatórios).

  `GET /v2/gn/pix/enviados` · escopo `gn.pix.send.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/envio-pagamento-pix#consultar-lista-de-pix-enviados)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    Client.request(client, :pix, :get, "/v2/gn/pix/enviados", Keyword.put(opts, :params, params))
  end

  @doc """
  Lê um QR Code pelo `pixCopiaECola` e devolve os dados da cobrança (recebedor, valor) sem
  pagar. É opcional: serve para conferir antes de chamar `pay_qr_code/4`.

  A Efí lista esta rota nos limites de consumo e cita o detalhamento na seção de pagamento de
  QR Code, mas não documenta o escopo nem a resposta.

  `POST /v2/gn/qrcodes/detalhar`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/envio-pagamento-pix#pagar-qr-code-pix)
  """
  @spec detail_qr_code(Client.t(), map(), keyword()) :: Efi.result()
  def detail_qr_code(%Client{} = client, body, opts \\ []) do
    Client.request(client, :pix, :post, "/v2/gn/qrcodes/detalhar", Keyword.put(opts, :json, body))
  end

  @doc """
  Paga a cobrança de um QR Code Pix a partir do `pixCopiaECola`, debitando da chave em
  `pagador.chave`. O resultado chega pelo webhook, como no envio. Só existe em produção.

  `PUT /v2/gn/pix/:idEnvio/qrcode` · escopo `gn.qrcodes.pay`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-pix/envio-pagamento-pix#pagar-qr-code-pix)
  """
  @spec pay_qr_code(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def pay_qr_code(%Client{} = client, send_id, body, opts \\ []) do
    path = Client.path("/v2/gn/pix/:idEnvio/qrcode", idEnvio: send_id)
    Client.request(client, :pix, :put, path, Keyword.put(opts, :json, body))
  end
end
