# Parceiros Efí

Este guia é para a plataforma que intermedeia pagamentos dos próprios clientes: abre uma conta
Efí para cada cliente, cobra em nome dele e, se quiser, fica com uma parte de cada pagamento.
O dinheiro cai na conta do cliente, não na da plataforma.

O caminho tem três peças:

1. a **Abertura de Contas**, que cria a conta do cliente e entrega as credenciais e o
   certificado dela;
2. um **`%Efi.Client{}` por cliente**, montado com essas credenciais;
3. o **split de pagamento**, que repassa a parte da plataforma a cada Pix recebido.

## Antes de começar

- A plataforma precisa de uma conta **Efí Empresas** e de uma aplicação com escopos da API Pix
  ou de Open Finance, em produção e em homologação.
- Os escopos da Abertura de Contas (`gn.registration.write`, `gn.registration.read`,
  `gn.registration.webhook.write`, `gn.registration.webhook.read`) são restritos: a Efí só os
  libera depois de uma avaliação, pedida ao representante comercial.
- A API de Abertura de Contas está em **beta** e pode mudar.

## 1. O cliente da plataforma

```elixir
{:ok, platform} =
  Efi.Client.new(
    client_id: System.fetch_env!("EFI_CLIENT_ID"),
    client_secret: System.fetch_env!("EFI_CLIENT_SECRET"),
    environment: :production,
    certificate: platform_certificate,
    token_store: MyApp.EfiTokenStore
  )
```

## 2. Avisar quando uma conta abrir

A Efí avisa por webhook quando o cliente autoriza (`"evento" => "conta_aberta"`) ou recusa
(`"conta_recusada_pelo_cliente_final"`), e tenta de novo até 10 vezes se o servidor não
responder 2xx. Cadastre a URL uma vez:

```elixir
Efi.Accounts.Webhook.configure(
  platform,
  %{"webhookUrl" => "https://app.example.com/webhooks/efi/contas?hmac=" <> secret},
  skip_mtls_checking: true
)
```

No cadastro, a Efí testa se o servidor exige o certificado dela (mTLS) e recusa com
`mtls_nao_configurado` se não exigir. Atrás de um proxy que encerra o TLS (Fly.io, Heroku,
Render), o certificado nunca chega ao app: o header `x-skip-mtls-checking`, que
`skip_mtls_checking: true` envia, pula esse teste no webhook Pix, e a URL passa a ser protegida
por um segredo próprio (o guia "Integração com Phoenix" mostra como conferir).

O webhook não é opcional: sem ele, o pedido de abertura volta com 412
`webhook_nao_cadastrado`. E a doc da Abertura de Contas não cita o header de pular o mTLS, só a
do Pix o aceita com certeza. **Confirme na homologação antes de planejar o resto.** Se a Efí
recusar o header aqui, o servidor do webhook precisa fazer o mTLS de verdade: encerrar o TLS no
próprio app (no Fly.io, um serviço TCP sem o handler de TLS) ou pôr na frente um proxy que exija
o certificado da Efí, como o Nginx do repositório `efipay/mtls-webhook`.

## 3. Pedir a abertura da conta

```elixir
{:ok, %{"contaSimplificada" => %{"identificador" => account_id}}} =
  Efi.Accounts.SimplifiedAccount.create(platform, %{
    "clienteFinal" => %{
      "cpf" => "12345678909",
      "nomeCompleto" => "Ana da Silva",
      "dataNascimento" => "13/08/1990",
      "nomeMae" => "Maria da Silva",
      "celular" => "71987654321",
      "email" => "ana@example.com",
      "cnpj" => "11222333000181",
      "razaoSocial" => "Studio Ana LTDA",
      "endereco" => %{
        "cep" => "40000000",
        "estado" => "BA",
        "cidade" => "Salvador",
        "bairro" => "Centro",
        "logradouro" => "Rua Exemplo",
        "numero" => "100"
      }
    },
    "meioDeNotificacao" => ["whatsapp", "sms"],
    "escoposIntegrados" => [
      "cob.write", "cob.read", "pix.read", "webhook.write", "webhook.read",
      "payloadlocation.write", "payloadlocation.read", "gn.split.write", "gn.split.read"
    ]
  })
```

Guarde o `account_id`. A Efí confere os dados com a Receita: nome, data de nascimento e nome da
mãe precisam bater com o CPF, ou a resposta é `%Efi.Error{kind: :validation}` com o `name` do
campo (`nome_completo_invalido`, `data_nascimento_invalida`, `nome_mae_invalido`). Sem CNPJ, a
conta nasce Efí Pro, de pessoa física; com CNPJ, Efí Empresas.

O cliente recebe um link pelo meio escolhido e autoriza. Se ele já tem conta Efí, escolhe entre
criar uma aplicação na conta atual ou uma conta secundária. Se recusar, um novo pedido para o
mesmo cliente só pode ser feito depois de 2 dias corridos.

Os escopos de envio de Pix e pagamento de boleto (`pix.send`, `gn.pix.send.read`,
`gn.qrcodes.pay` e os de código de barras) não são liberados quando o cliente já tem conta:
a plataforma recebe em nome dele, mas não movimenta o saldo.

## 4. Quando a conta abrir: credenciais e certificado

```elixir
{:ok, %{"clientId" => client_id, "clientSecret" => client_secret, "conta" => conta}} =
  Efi.Accounts.SimplifiedAccount.get_credentials(platform, account_id)

{:ok, p12_base64} = Efi.Accounts.SimplifiedAccount.create_certificate(platform, account_id)
{:ok, certificate} = p12_base64 |> Base.decode64!() |> Efi.Certificate.from_p12()
```

Cada conta tem um limite de certificados (`quantidade_limite_de_certificados`): crie o
certificado uma vez e guarde o `.p12` cifrado no banco, junto com as credenciais e o
`conta["numero"]`. Com isso, o cliente da conta é:

```elixir
{:ok, business} =
  Efi.Client.new(
    client_id: client_id,
    client_secret: client_secret,
    environment: :production,
    certificate: certificate,
    token_store: MyApp.EfiTokenStore
  )
```

O `token_store` separa os tokens pelo `client_id`, então um store serve para todas as contas.

## 5. Cobrar e repassar a parte da plataforma

O split da API Pix só funciona entre contas Efí e não repassa para a própria conta. A
configuração é criada na conta de quem recebe (o cliente) e pode ser reaproveitada em todas as
cobranças dele:

```elixir
{:ok, %{"id" => split_config_id}} =
  Efi.Pix.Split.create_config(business, %{
    "descricao" => "Comissão da plataforma",
    "lancamento" => %{"imediato" => true},
    "split" => %{
      "divisaoTarifa" => "assumir_total",
      "minhaParte" => %{"tipo" => "porcentagem", "valor" => "95.00"},
      "repasses" => [
        %{
          "tipo" => "porcentagem",
          "valor" => "5.00",
          "favorecido" => %{"cnpj" => "CNPJ_DA_PLATAFORMA", "conta" => "CONTA_EFI_DA_PLATAFORMA"}
        }
      ]
    }
  })

{:ok, _charge} =
  Efi.Pix.ImmediateCharge.create_with_txid(business, txid, %{
    "calendario" => %{"expiracao" => 3600},
    "valor" => %{"original" => "120.00"},
    "chave" => chave_pix_do_cliente
  })

{:ok, _linked} = Efi.Pix.Split.link_charge(business, txid, split_config_id)
```

Em homologação, o favorecido precisa ser outra conta Efí válida: crie uma subconta para testar.

## Comissão de parceiro na API Cobranças

Se a Efí te deu um identificador de parceiro, passe-o como `partner_token:` no
`Efi.Client.new/1`: ele vai no header `partner-token` de cada chamada, como fazem os SDKs
oficiais.
