# Efi

Cliente Elixir para as APIs da [Efí](https://dev.efipay.com.br): Pix (com Pix Automático e
split), Cobranças (boleto, carnê, cartão, link de pagamento e assinaturas), Open Finance,
Abertura de Contas, Pagamento de Contas e Extratos.

- **Uma função por rota.** São 172 rotas, cada uma com `@doc` que aponta para a seção exata da
  documentação oficial, com o método, o caminho e o escopo exigido.
- **Os dados da Efí, sem tradução.** Parâmetros e respostas são mapas com os nomes que a Efí usa
  (`"calendario"`, `"valor"`, `"txid"`). O que a documentação mostra é o que se envia.
- **Várias contas ao mesmo tempo.** Sem configuração global nem processo: cada chamada recebe um
  `%Efi.Client{}`, o que permite a uma plataforma parceira cobrar em nome de cada cliente.
- **Erros num formato só.** Toda função devolve `{:ok, corpo}` ou `{:error, %Efi.Error{}}`, com o
  mesmo `kind` em todas as APIs.

```elixir
{:ok, certificate} = Efi.Certificate.from_p12(File.read!("producao.p12"))

{:ok, client} =
  Efi.Client.new(
    client_id: "Client_Id_...",
    client_secret: "Client_Secret_...",
    environment: :production,
    certificate: certificate
  )

{:ok, charge} =
  Efi.Pix.ImmediateCharge.create(client, %{
    "calendario" => %{"expiracao" => 3600},
    "valor" => %{"original" => "50.00"},
    "chave" => "chave-pix-do-studio-ana"
  })

charge["pixCopiaECola"]
```

## Instalação

```elixir
def deps do
  [
    {:efi, "~> 0.1"}
  ]
end
```

Requer Elixir 1.15 ou mais novo e o executável `openssl` no servidor, para abrir o certificado
`.p12` das APIs com mTLS.

## Guias

- [Primeiros passos](guides/primeiros-passos.md): credenciais, certificado, cliente, token e erros.
- [Parceiros Efí](guides/parceiros.md): abrir a conta de cada cliente, cobrar em nome dele e
  ficar com uma parte pelo split.
- [Integração com Phoenix](guides/phoenix.md): cobrança Pix numa LiveView, webhook e testes.

## Cobertura

| API | Módulos | Homologação |
|---|---|---|
| Pix | `Efi.Pix.*` | suíte pronta, ainda não rodada |
| Pix Automático | `Efi.Pix.Automatic.*` | ainda não conferida |
| Cobranças | `Efi.Charges.*` | suíte pronta, ainda não rodada |
| Open Finance | `Efi.OpenFinance.*` | ainda não conferida |
| Abertura de Contas (beta na Efí) | `Efi.Accounts.*` | ainda não conferida |
| Pagamento de Contas | `Efi.BillPayments.*` | ainda não conferida |
| Extratos | `Efi.Statements.*` | ainda não conferida |

"Conferida" quer dizer que a suíte `mix test --only sandbox` rodou contra a homologação da Efí.
As demais APIs têm cada rota testada contra o formato da documentação, mas ainda não falaram com
a Efí de verdade. O Pix Indireto, produto para instituições financeiras, não está incluído.

## Desenvolvimento

```bash
mix deps.get
mix precommit             # compila sem warnings, formata, credo e testes com cobertura mínima de 99%
mix test --only sandbox   # jornadas na homologação; exige EFI_SANDBOX_CLIENT_ID,
                          # EFI_SANDBOX_CLIENT_SECRET, EFI_SANDBOX_CERTIFICATE e EFI_SANDBOX_PIX_KEY
mix efi.check_links       # confere se cada link da documentação aponta para uma seção que existe
```

`dev/endpoints.json` é o inventário das rotas, extraído da documentação da Efí e do SDK oficial
em Node. Um teste falha se alguma rota do inventário ficar sem função.

## Licença

MIT.
