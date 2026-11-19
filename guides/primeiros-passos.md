# Primeiros passos

## Instalação

```elixir
def deps do
  [
    {:efi, "~> 0.1"}
  ]
end
```

As APIs com mTLS precisam do executável `openssl` no servidor para abrir o `.p12`. Em imagens
Debian ou Ubuntu ele já vem; em Alpine, `apk add openssl`. Certificados antigos usam uma cifra
que o OpenSSL 3 moveu para o provider legacy: se `Efi.Certificate.from_p12/3` voltar com
`:legacy_provider_missing`, instale o pacote do provider (`openssl-provider-legacy` no Debian 13)
ou converta o arquivo para PEM uma vez e use `Efi.Certificate.from_pem/1`.

## Credenciais e certificado

Na conta Efí, em **API > Aplicações**, crie uma aplicação e habilite as APIs e os escopos que vai
usar. Cada aplicação tem um par `Client_Id`/`Client_Secret` de produção e outro de homologação, e
cada ambiente tem o próprio certificado `.p12`, gerado em **API > Meus certificados**.

Guarde o certificado como segredo do ambiente, em Base64, e abra na subida do app:

```elixir
{:ok, certificate} =
  "EFI_CERTIFICATE"
  |> System.fetch_env!()
  |> Base.decode64!()
  |> Efi.Certificate.from_p12()
```

A API Cobranças não exige certificado; todas as outras exigem, inclusive no pedido do token.

## O cliente

```elixir
{:ok, client} =
  Efi.Client.new(
    client_id: System.fetch_env!("EFI_CLIENT_ID"),
    client_secret: System.fetch_env!("EFI_CLIENT_SECRET"),
    environment: :production,
    certificate: certificate,
    token_store: MyApp.EfiTokenStore
  )
```

`environment: :sandbox` aponta para a homologação. O cliente é só um valor: monte um por conta
Efí. Num app parceiro, isso quer dizer o seu e um para cada cliente com conta aberta pela
`Efi.Accounts.SimplifiedAccount` (veja o guia "Parceiros Efí").

## Guardar o token

Cada API da Efí emite um token OAuth2, que vale uma hora (10 minutos na Cobranças). Sem
`token_store`, a biblioteca pede um token antes de cada chamada, o que dobra as requisições.
Com um, o token é reaproveitado até faltar um minuto para vencer. Uma implementação em ETS:

```elixir
defmodule MyApp.EfiTokenStore do
  @behaviour Efi.TokenStore
  use GenServer

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl GenServer
  def init(nil) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, nil}
  end

  @impl Efi.TokenStore
  def fetch(key) do
    case :ets.lookup(@table, key) do
      [{^key, token}] -> {:ok, token}
      [] -> :error
    end
  end

  @impl Efi.TokenStore
  def put(key, token) do
    :ets.insert(@table, {key, token})
    :ok
  end
end
```

Coloque `MyApp.EfiTokenStore` na árvore de supervisão do app, antes de quem chama a Efí. Com
vários nós, cada nó tem a própria tabela e pede o próprio token.

## Chamando uma API

Os parâmetros são os da documentação da Efí, com os mesmos nomes:

```elixir
{:ok, charge} =
  Efi.Pix.ImmediateCharge.create(client, %{
    "calendario" => %{"expiracao" => 3600},
    "valor" => %{"original" => "50.00"},
    "chave" => "chave-pix-do-studio-ana",
    "solicitacaoPagador" => "Corte e escova"
  })

charge["pixCopiaECola"]
```

O `@doc` de cada função tem o link para a seção da documentação oficial com todos os campos.

## Erros

Toda função devolve `{:ok, corpo}` ou `{:error, %Efi.Error{}}`:

```elixir
case Efi.Pix.ImmediateCharge.get(client, txid) do
  {:ok, charge} -> charge["status"]
  {:error, %Efi.Error{kind: :not_found}} -> :desconhecida
  {:error, %Efi.Error{kind: :transport}} -> :tentar_depois
  {:error, %Efi.Error{} = error} -> raise error
end
```

`kind` vem do status HTTP e é o mesmo em todas as APIs. `name` e `message` vêm do corpo, que a
Efí escreve em formatos diferentes por API; o corpo original fica em `body`.

Uma escrita que volta com `:transport` (timeout, conexão caída) ou `:server` (5xx) pode ter
chegado à Efí. A biblioteca não repete escritas por isso: confira antes de tentar de novo, por
exemplo criando cobranças com `txid` próprio, que torna a repetição segura.

## Homologação

Em `environment: :sandbox`, a Efí simula os pagamentos. Na API Pix, cobranças de R$ 0,01 a
R$ 10,00 são pagas sozinhas e disparam o webhook; acima disso ficam ativas sem pagamento.
Pagamento de Contas e Extratos não têm homologação: com um cliente `:sandbox`, as chamadas
delas voltam `%Efi.Error{kind: :configuration, reason: {:environment, :unsupported}}`.

## Testes no seu app

A biblioteca fala HTTP só pelo `Req`, então os testes do app usam `Req.Test` passando
`req_options: [plug: {Req.Test, MyApp.EfiStub}]` no cliente. Com um `token_store` que devolve um
token fixo, o stub nem precisa simular o pedido do token.
