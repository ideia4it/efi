# Integração com Phoenix

Um app Phoenix que cobra por Pix, mostra o QR Code numa LiveView e confirma o pagamento pelo
webhook. Os nomes `MyApp` e `MyAppWeb` são do seu app.

## 1. Configuração

Credenciais e certificado vêm do ambiente. Em `config/runtime.exs`:

```elixir
if config_env() != :test do
  config :my_app, :efi,
    client_id: System.fetch_env!("EFI_CLIENT_ID"),
    client_secret: System.fetch_env!("EFI_CLIENT_SECRET"),
    certificate: System.fetch_env!("EFI_CERTIFICATE"),
    pix_key: System.fetch_env!("EFI_PIX_KEY"),
    webhook_secret: System.fetch_env!("EFI_WEBHOOK_SECRET"),
    environment: if(config_env() == :prod, do: :production, else: :sandbox)
end
```

E em `config/test.exs`, sem credenciais nem certificado (a seção 8 mostra o cliente dos testes):

```elixir
config :my_app, :efi, pix_key: "chave-pix-de-teste", webhook_secret: "segredo-de-teste"
```

`EFI_CERTIFICATE` é o `.p12` em Base64 (`base64 < producao.p12`). O `base64` do Linux quebra a
linha a cada 76 caracteres, por isso o `Base.decode64!/2` do `MyApp.Efi` ignora espaços e
quebras de linha. O segredo do webhook vai na query string da URL cadastrada; tire-o dos logs em
`config/config.exs`:

```elixir
config :phoenix, :filter_parameters, ["password", "hmac"]
```

## 2. O cliente

Abrir o certificado chama o `openssl`, então faça isso uma vez, na subida, e guarde o cliente em
`:persistent_term`. O `token_store` do guia "Primeiros passos" entra na árvore de supervisão
antes:

```elixir
defmodule MyApp.Efi do
  @moduledoc "O cliente Efí do app."

  def child_spec(_opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}

  # Sem certificado na configuração, como nos testes, quem guarda o cliente é o test_helper.
  def start_link do
    config = Application.fetch_env!(:my_app, :efi)
    if config[:certificate], do: :persistent_term.put(__MODULE__, build_client(config))
    :ignore
  end

  def client, do: :persistent_term.get(__MODULE__)

  defp build_client(config) do
    {:ok, certificate} =
      config[:certificate]
      |> Base.decode64!(ignore: :whitespace)
      |> Efi.Certificate.from_p12()

    {:ok, client} =
      Efi.Client.new(
        client_id: config[:client_id],
        client_secret: config[:client_secret],
        environment: config[:environment],
        certificate: certificate,
        token_store: MyApp.EfiTokenStore
      )

    client
  end
end
```

```elixir
# lib/my_app/application.ex
children = [
  # ...
  MyApp.EfiTokenStore,
  MyApp.Efi,
  MyAppWeb.Endpoint
]
```

Um app parceiro, com uma conta Efí por cliente, monta o cliente de cada conta a partir das
credenciais guardadas no banco (veja o guia "Parceiros Efí") e pode guardá-lo do mesmo jeito,
com a chave `{MyApp.Efi, account_id}`.

## 3. Cobrar

O `txid` é seu: gere um por pedido e guarde antes de chamar a Efí. Assim, um timeout ou uma
página recarregada reaproveitam a mesma cobrança em vez de criar outra: o segundo `PUT` com o
mesmo `txid` volta como `:conflict`, e aí basta consultar.

```elixir
defmodule MyApp.Payments do
  alias MyApp.Payments.Order

  def charge_pix(%Order{} = order) do
    client = MyApp.Efi.client()

    with {:ok, charge} <- create_or_fetch_charge(client, order),
         {:ok, qr_code} <- Efi.Pix.Location.get_qr_code(client, charge["loc"]["id"]) do
      {:ok, %{copy_paste: charge["pixCopiaECola"], image: qr_code["imagemQrcode"]}}
    end
  end

  defp create_or_fetch_charge(client, order) do
    body = %{
      "calendario" => %{"expiracao" => 3600},
      "valor" => %{"original" => format_cents(order.total_cents)},
      "chave" => Application.fetch_env!(:my_app, :efi)[:pix_key],
      "solicitacaoPagador" => "Pedido #{order.number}"
    }

    case Efi.Pix.ImmediateCharge.create_with_txid(client, order.txid, body) do
      {:error, %Efi.Error{kind: :conflict}} -> Efi.Pix.ImmediateCharge.get(client, order.txid)
      result -> result
    end
  end

  # A Efí recebe o valor em reais, como texto com duas casas: 5000 centavos viram "50.00".
  defp format_cents(cents) do
    reais = div(cents, 100)
    centavos = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{reais}.#{centavos}"
  end
end
```

`order.txid` precisa ter de 26 a 35 letras e números, por exemplo
`Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)`.

## 4. Mostrar o QR Code e esperar o pagamento

A LiveView assina um tópico do pedido; o webhook publica nele quando o Pix cai.

```elixir
defmodule MyAppWeb.CheckoutLive do
  use MyAppWeb, :live_view

  def mount(%{"id" => id}, _session, socket) do
    order = MyApp.Orders.get_order!(id)
    if connected?(socket), do: Phoenix.PubSub.subscribe(MyApp.PubSub, "order:#{order.id}")

    socket =
      socket
      |> assign(order: order, paid?: order.paid_at != nil)
      |> assign_async(:pix, fn ->
        with {:ok, pix} <- MyApp.Payments.charge_pix(order), do: {:ok, %{pix: pix}}
      end)

    {:ok, socket}
  end

  def handle_info({:order_paid, _order_id}, socket), do: {:noreply, assign(socket, paid?: true)}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <p :if={@paid?} id="order-paid">Pagamento confirmado.</p>
      <.async_result :let={pix} :if={!@paid?} assign={@pix}>
        <:loading>Gerando o Pix...</:loading>
        <:failed>Não foi possível gerar o Pix agora. Tente de novo em instantes.</:failed>
        <img id="pix-qr-code" src={pix.image} alt="QR Code do Pix" />
        <input id="pix-copy-paste" type="text" value={pix.copy_paste} readonly />
      </.async_result>
    </Layouts.app>
    """
  end
end
```

`imagemQrcode` já vem como data URI (no exemplo da Efí, `data:image/svg+xml;base64,...`) e vai
direto no `src`.

## 5. Receber o webhook

A Efí faz `POST` na URL cadastrada com `{"pix": [...]}`, um item por Pix recebido. Trate o
webhook como gatilho: confira o `txid` relendo a cobrança na Efí antes de dar o pedido como
pago, porque quem conhece a URL consegue mandar qualquer corpo.

```elixir
# lib/my_app_web/router.ex
pipeline :webhook do
  plug :accepts, ["json"]
end

scope "/webhooks", MyAppWeb do
  pipe_through :webhook
  post "/efi", EfiWebhookController, :pix
end
```

```elixir
defmodule MyAppWeb.EfiWebhookController do
  use MyAppWeb, :controller

  def pix(conn, %{"hmac" => hmac} = params) do
    if Plug.Crypto.secure_compare(hmac, webhook_secret()) do
      params
      |> Map.get("pix", [])
      |> Enum.each(&confirm_payment/1)

      send_resp(conn, 200, "")
    else
      send_resp(conn, 401, "")
    end
  end

  def pix(conn, _params), do: send_resp(conn, 401, "")

  defp confirm_payment(%{"txid" => txid}) when is_binary(txid) do
    with {:ok, %{"status" => "CONCLUIDA"} = charge} <-
           Efi.Pix.ImmediateCharge.get(MyApp.Efi.client(), txid),
         {:ok, order} <- MyApp.Orders.mark_paid(txid, charge["pix"]) do
      Phoenix.PubSub.broadcast(MyApp.PubSub, "order:#{order.id}", {:order_paid, order.id})
    end
  end

  defp confirm_payment(_pix_without_txid), do: :ignored

  defp webhook_secret, do: Application.fetch_env!(:my_app, :efi)[:webhook_secret]
end
```

`MyApp.Orders.mark_paid/2` deve ser idempotente: a Efí repete a notificação quando não recebe
2xx, e a mesma cobrança pode chegar duas vezes. Com muito volume, troque o `Enum.each/2` por um
job (Oban) por item e responda 200 na hora.

## 6. Cadastrar a URL do webhook

Uma vez por chave Pix e por ambiente, num `iex -S mix` ou numa tarefa de deploy:

```elixir
config = Application.fetch_env!(:my_app, :efi)
url = "https://app.example.com/webhooks/efi?hmac=#{config[:webhook_secret]}&ignorar="

Efi.Pix.Webhook.configure(MyApp.Efi.client(), config[:pix_key], %{"webhookUrl" => url},
  skip_mtls_checking: true
)
```

- `&ignorar=` no fim impede que a Efí acrescente `/pix` ao caminho, então a mesma rota recebe a
  notificação de teste do cadastro e as de verdade.
- `skip_mtls_checking: true` é para quem está atrás de um proxy que encerra o TLS (Fly.io,
  Heroku, Render): a Efí testa o mTLS do servidor no cadastro, e o certificado dela nunca chega
  ao app. O header que essa opção manda não está na documentação da Efí; vem dos SDKs oficiais.
  Quem termina o TLS no próprio servidor pode exigir o certificado da Efí e dispensar o header.
- A Efí envia de um IP fixo (está na documentação do webhook); filtrar por ele é uma camada a
  mais.

## 7. Boleto, carnê e cartão: notificações da API Cobranças

A API Cobranças não manda o conteúdo da mudança: ela faz `POST` com `notification=<token>` na
`notification_url` da cobrança, e o app consulta o token. A rota vai no mesmo escopo
`/webhooks` da seção 5:

```elixir
post "/efi/cobrancas", EfiWebhookController, :charges
```

```elixir
def charges(conn, %{"notification" => token}) do
  {:ok, %{"data" => events}} = Efi.Charges.Notification.get(MyApp.Efi.client(), token)
  Enum.each(events, &MyApp.Billing.apply_charge_event/1)
  send_resp(conn, 200, "")
end
```

## 8. Testes

O cliente aceita `req_options`, então os testes do app trocam a rede por `Req.Test`. O
`MyApp.Efi` não guarda cliente quando a configuração de teste não tem certificado; o
`test/test_helper.exs` guarda um cliente que fala com o stub, com um token fixo para o stub nem
precisar simular o pedido do token:

```elixir
defmodule MyApp.EfiTestTokenStore do
  @behaviour Efi.TokenStore

  @impl Efi.TokenStore
  def fetch(_key) do
    {:ok, %Efi.Token{access_token: "test", token_type: "Bearer", expires_at: ~U[2099-01-01 00:00:00Z]}}
  end

  @impl Efi.TokenStore
  def put(_key, _token), do: :ok
end
```

```elixir
# test/test_helper.exs
# O stub não abre conexão TLS, então o certificado só precisa existir.
fake_certificate = %Efi.Certificate{
  certificate: "",
  key: {:PrivateKeyInfo, ""},
  chain: [],
  not_before: ~U[2026-01-01 00:00:00Z],
  not_after: ~U[2099-01-01 00:00:00Z]
}

{:ok, efi_client} =
  Efi.Client.new(
    client_id: "test",
    client_secret: "test",
    environment: :sandbox,
    certificate: fake_certificate,
    token_store: MyApp.EfiTestTokenStore,
    req_options: [plug: {Req.Test, MyApp.EfiStub}, retry: false]
  )

:persistent_term.put(MyApp.Efi, efi_client)
ExUnit.start()
```

A LiveView chama a Efí num processo próprio (`assign_async`), então o stub fica em modo
compartilhado e o teste não roda em paralelo:

```elixir
defmodule MyAppWeb.CheckoutLiveTest do
  use MyAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup {Req.Test, :set_req_test_to_shared}

  test "shows the Pix QR Code for the order", %{conn: conn} do
    order = order_fixture(total_cents: 5000)

    Req.Test.stub(MyApp.EfiStub, fn
      %{method: "PUT"} = conn ->
        Req.Test.json(conn, %{"loc" => %{"id" => 7}, "pixCopiaECola" => "000201-pedido"})

      %{method: "GET"} = conn ->
        Req.Test.json(conn, %{"imagemQrcode" => "data:image/png;base64,AAA"})
    end)

    {:ok, view, _html} = live(conn, ~p"/checkout/#{order.id}")
    render_async(view)

    assert has_element?(view, "#pix-copy-paste[value='000201-pedido']")
  end
end
```
