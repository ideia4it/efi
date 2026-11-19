defmodule Efi.Accounts.SimplifiedAccount do
  @moduledoc """
  Conta simplificada: o parceiro abre uma conta Efí para o cliente dele (ou uma aplicação na
  conta que o cliente já tem) e recebe as credenciais e o certificado para operar Pix e Open
  Finance em nome desse cliente.

  É a peça central de um app parceiro da Efí: ao fim do fluxo abaixo, cada cliente vira um
  `%Efi.Client{}` próprio, e o dinheiro das cobranças cai direto na conta dele.

  ## Antes de começar

    * A API está em beta e pode mudar enquanto a Efí a desenvolve.
    * O parceiro precisa de uma conta Efí Empresas e de uma aplicação ativa com escopos da API
      Pix ou Open Finance em produção e em homologação.
    * Os escopos `gn.registration.*` só são liberados depois de uma avaliação do comercial da
      Efí. Peça ao representante responsável pela sua conta.
    * Cadastre o webhook com `Efi.Accounts.Webhook.configure/3` antes da primeira abertura. Sem
      ele, `create/3` volta com status 412 e `name: "webhook_nao_cadastrado"`.

  ## O fluxo

    1. `create/3` envia os dados do cliente final (`clienteFinal`), por onde ele será avisado
       (`meioDeNotificacao`: `"sms"`, `"whatsapp"` ou os dois) e os escopos que o parceiro quer
       na conta dele (`escoposIntegrados`). Só valem escopos que a aplicação do parceiro já
       tem. A resposta traz o identificador da conta, que as outras funções usam.
    2. O cliente recebe um link por SMS ou WhatsApp e autoriza. Se já tem conta na Efí, ele
       escolhe entre criar uma aplicação na conta atual ou abrir uma conta secundária com o que
       o parceiro pediu. Na aplicação em conta existente, a Efí não libera os escopos de envio
       de Pix e de pagamento de boleto: `pix.send`, `gn.pix.send.read`, `gn.qrcodes.pay`,
       `gn.qrcodes.read`, `gn.barcode.read`, `gn.barcode.pay.write` e `gn.barcode.pay.read`.
    3. A Efí chama o webhook com o identificador e o `evento`: `"conta_aberta"` ou
       `"conta_recusada_pelo_cliente_final"`. Depois de uma recusa, um novo pedido para o mesmo
       cliente só é aceito 2 dias corridos depois.
    4. `get_credentials/3` devolve `clientId`, `clientSecret`, os dados da `conta` e os
       `escopos` liberados.
    5. `create_certificate/3` devolve o certificado `.p12` em Base64. Cada conta tem um limite
       de certificados (erro `quantidade_limite_de_certificados`): guarde o arquivo, cifrado
       porque contém a chave privada, em vez de gerar outro a cada uso.

  Enquanto o cliente não aprova, as duas leituras voltam com status 412 e `name`
  `"conta_em_processamento"` ou `"conta_nao_aprovada_ou_recusada"`.

      {:ok, %{"contaSimplificada" => %{"identificador" => account_id}}} =
        Efi.Accounts.SimplifiedAccount.create(partner_client, %{
          "clienteFinal" => %{
            "cpf" => "12345678909",
            "nomeCompleto" => "Ana Exemplo",
            "dataNascimento" => "13/08/1990",
            "celular" => "31900000000",
            "email" => "ana@example.com",
            "cnpj" => "11222333000181",
            "razaoSocial" => "Studio Ana LTDA",
            "endereco" => %{
              "cep" => "35400000",
              "estado" => "MG",
              "cidade" => "Ouro Preto",
              "bairro" => "Centro",
              "logradouro" => "Rua Exemplo",
              "numero" => "100"
            }
          },
          "meioDeNotificacao" => ["whatsapp"],
          "escoposIntegrados" => ["cob.write", "cob.read", "pix.read", "webhook.write"]
        })

  Depois que o webhook avisa `"conta_aberta"`, o cliente vira um `%Efi.Client{}`:

      {:ok, %{"clientId" => client_id, "clientSecret" => client_secret}} =
        Efi.Accounts.SimplifiedAccount.get_credentials(partner_client, account_id)

      {:ok, p12_base64} =
        Efi.Accounts.SimplifiedAccount.create_certificate(partner_client, account_id)

      {:ok, certificate} = p12_base64 |> Base.decode64!() |> Efi.Certificate.from_p12()

      {:ok, studio_ana_client} =
        Efi.Client.new(
          client_id: client_id,
          client_secret: client_secret,
          environment: partner_client.environment,
          certificate: certificate
        )

  Uma pessoa física sem CNPJ ganha uma conta Efí Pro; com CNPJ, a conta é Efí Empresas.
  """

  alias Efi.Client

  @doc """
  Pede a abertura de uma conta simplificada para o cliente final. A Efí manda o link de
  autorização ao cliente e devolve o identificador da conta em
  `contaSimplificada.identificador`.

  `POST /v1/conta-simplificada` · escopo `gn.registration.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-abertura-de-contas/cadastro-simplificado#solicitar-abertura-de-conta-simplificada)
  """
  @spec create(Client.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, body, opts \\ []) do
    Client.request(
      client,
      :accounts,
      :post,
      "/v1/conta-simplificada",
      Keyword.put(opts, :json, body)
    )
  end

  @doc """
  Busca o `clientId` e o `clientSecret` da aplicação criada para o cliente, com os dados da
  `conta` e os `escopos` liberados.

  `GET /v1/conta-simplificada/:idContaSimplificada/credenciais` · escopo `gn.registration.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-abertura-de-contas/cadastro-simplificado#recuperar-credenciais-de-uma-conta-simplificada)
  """
  @spec get_credentials(Client.t(), String.t(), keyword()) :: Efi.result()
  def get_credentials(%Client{} = client, account_id, opts \\ []) do
    path =
      Client.path("/v1/conta-simplificada/:idContaSimplificada/credenciais",
        idContaSimplificada: account_id
      )

    Client.request(client, :accounts, :get, path, opts)
  end

  @doc """
  Cria um certificado para a conta do cliente e o devolve em Base64: decodificado, é um `.p12`
  sem senha, pronto para `Efi.Certificate.from_p12/1`.

  `POST /v1/conta-simplificada/:idContaSimplificada/certificado` · escopo `gn.registration.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-abertura-de-contas/cadastro-simplificado#criar-certificado-de-uma-conta-simplificada)
  """
  @spec create_certificate(Client.t(), String.t(), keyword()) :: Efi.result()
  def create_certificate(%Client{} = client, account_id, opts \\ []) do
    path =
      Client.path("/v1/conta-simplificada/:idContaSimplificada/certificado",
        idContaSimplificada: account_id
      )

    Client.request(client, :accounts, :post, path, opts)
  end
end
