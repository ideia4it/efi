defmodule Efi.Client do
  @moduledoc """
  Credenciais de uma aplicação Efí e o único ponto que fala HTTP com a Efí.

  Todo o estado vive no `%Efi.Client{}`. Não há processo nem configuração global, então um app
  parceiro monta um cliente por conta: a dele e a de cada cliente aberta pela
  `Efi.Accounts.SimplifiedAccount`.

      {:ok, certificate} = Efi.Certificate.from_p12(File.read!("producao.p12"))

      {:ok, client} =
        Efi.Client.new(
          client_id: "Client_Id_...",
          client_secret: "Client_Secret_...",
          environment: :production,
          certificate: certificate,
          token_store: MyApp.EfiTokenStore
        )

  ## APIs e ambientes

  | API | átomo | Produção | Homologação | mTLS |
  |---|---|---|---|---|
  | Pix | `:pix` | `pix.api.efipay.com.br` | `pix-h.api.efipay.com.br` | sim |
  | Cobranças | `:charges` | `cobrancas.api.efipay.com.br` | `cobrancas-h.api.efipay.com.br` | não |
  | Open Finance | `:open_finance` | `openfinance.api.efipay.com.br` | `openfinance-h.api.efipay.com.br` | sim |
  | Abertura de Contas | `:accounts` | `abrircontas.api.efipay.com.br` | `abrircontas-h.api.efipay.com.br` | sim |
  | Pagamento de Contas | `:bill_payments` | `pagarcontas.api.efipay.com.br` | não existe | sim |
  | Extratos | `:statements` | `extratos.api.efipay.com.br` | não existe | sim |

  Uma aplicação Efí tem um par de credenciais para produção e outro para homologação, e cada
  ambiente tem o próprio certificado. Pagamento de Contas e Extratos só rodam em produção: com
  um cliente `:sandbox`, as chamadas delas voltam
  `%Efi.Error{kind: :configuration, reason: {:environment, :unsupported}}` sem sair da máquina.

  ## Token de acesso

  Cada API emite o próprio token OAuth2, pedido com HTTP Basic (`client_id:client_secret`) e,
  nas APIs com mTLS, com o certificado. Um certificado vencido volta como
  `%Efi.Error{kind: :certificate, reason: :expired}` antes de qualquer pedido. Sem
  `token_store`, cada chamada pede um token novo antes da requisição. Com um `Efi.TokenStore`,
  o token é reaproveitado até faltar um minuto para vencer. Se a Efí recusar com 401 um token
  que veio do store (revogado antes da hora), a chamada pede um token novo e repete uma única
  vez.

  ## Reenvio

  Leituras (`GET`) são repetidas em falhas transitórias: 408, 429, 500, 502, 503, 504, timeout
  e conexão recusada ou fechada. Escritas só são repetidas quando o pedido nunca saiu da
  máquina (DNS que não resolve, conexão recusada, rede inalcançável): qualquer outra falha é
  ambígua, porque a Efí pode já ter criado a cobrança ou enviado o Pix, e repetir duplicaria a
  operação. Nesses casos o erro volta para o chamador conferir antes de tentar de novo.

  São até 3 repetições, com espera crescente de 1, 2 e 4 segundos. Num 429 ou 503 com
  `retry-after`, a espera é a que a Efí pede, até 5 segundos; acima disso o erro volta na hora,
  com o header em `error.headers`, para o app decidir quando tentar. No pior caso, um `GET` que
  sempre estoura o tempo leva 4 vezes o `receive_timeout` mais uns 7 segundos. Para encurtar,
  passe `req_options: [max_retries: 1]`, ou `retry: false` para não repetir nada.

  ## Conexões

  O `Req` mantém um pool de conexões para cada certificado, nomeado por um átomo. O pool fecha
  depois de 5 minutos parado, mas a estrutura dele continua viva: um parceiro com milhares de
  contas ativas fica com um átomo e alguns processos parados por certificado.

  ## Opções de cada chamada

  Toda função das APIs aceita, no último argumento, as opções de requisição:

    * `:idempotency_key` - enviada no header `x-idempotency-key`. As rotas do Open Finance que
      exigem a chave a recebem como argumento, então esta opção só serve para outra rota;
    * `:skip_mtls_checking` - com `true`, envia `x-skip-mtls-checking: true` ao cadastrar um
      webhook. Use quando o servidor do webhook não valida o certificado da Efí, como atrás de
      um proxy que encerra o TLS (Fly.io, Heroku, Render), e proteja a URL de outra forma. A
      documentação da Efí não descreve esse header: ele vem dos SDKs oficiais, e o de Node
      (`validateMtls: false`) o manda no cadastro dos webhooks do Pix, do Pix Automático, do
      Pagamento de Contas e da Abertura de Contas. No webhook Pix ele funciona em produção;
      nos outros, confirme na homologação;
    * `:headers` - headers extras;
    * `:receive_timeout` - sobrescreve o do cliente só nesta chamada.
  """

  alias Efi.Certificate
  alias Efi.Error
  alias Efi.Token

  @derive {Inspect, except: [:client_secret, :partner_token]}
  @enforce_keys [:client_id, :client_secret, :environment]
  defstruct [
    :client_id,
    :client_secret,
    :environment,
    :certificate,
    :token_store,
    :partner_token,
    receive_timeout: 30_000,
    req_options: []
  ]

  @typedoc "Uma API da Efí. Cada uma tem host, rota de token e escopos próprios (veja a tabela acima)."
  @type api :: :pix | :charges | :open_finance | :accounts | :bill_payments | :statements

  @typedoc "`:production` ou `:sandbox` (homologação)."
  @type environment :: :production | :sandbox

  @typedoc "Cliente montado por `new/1`, com as opções descritas lá."

  @type t :: %__MODULE__{
          client_id: String.t(),
          client_secret: String.t(),
          environment: environment(),
          certificate: Certificate.t() | nil,
          token_store: module() | nil,
          partner_token: String.t() | nil,
          receive_timeout: pos_integer(),
          req_options: keyword()
        }

  # O SDK oficial em Node lista `pagarcontas-h` e `extratos-h`, mas esses nomes não resolvem
  # no DNS e a doc da Efí só cita produção para as duas APIs.
  @hosts %{
    pix: %{
      production: "https://pix.api.efipay.com.br",
      sandbox: "https://pix-h.api.efipay.com.br"
    },
    charges: %{
      production: "https://cobrancas.api.efipay.com.br",
      sandbox: "https://cobrancas-h.api.efipay.com.br"
    },
    open_finance: %{
      production: "https://openfinance.api.efipay.com.br",
      sandbox: "https://openfinance-h.api.efipay.com.br"
    },
    accounts: %{
      production: "https://abrircontas.api.efipay.com.br",
      sandbox: "https://abrircontas-h.api.efipay.com.br"
    },
    bill_payments: %{production: "https://pagarcontas.api.efipay.com.br"},
    statements: %{production: "https://extratos.api.efipay.com.br"}
  }

  @token_paths %{
    pix: "/oauth/token",
    charges: "/v1/authorize",
    open_finance: "/v1/oauth/token",
    accounts: "/v1/oauth/token",
    bill_payments: "/v1/oauth/token",
    statements: "/v1/oauth/token"
  }

  @apis_without_mtls [:charges]
  @environments [:production, :sandbox]
  @request_options [
    :json,
    :params,
    :headers,
    :idempotency_key,
    :skip_mtls_checking,
    :receive_timeout
  ]
  @pool_max_idle_time :timer.minutes(5)
  @transient_statuses [408, 429, 500, 502, 503, 504]
  @never_sent_reasons [:nxdomain, :econnrefused, :ehostunreach, :enetunreach]
  @transient_reasons [:timeout, :closed | @never_sent_reasons]
  @max_retry_after_seconds 5

  @doc """
  Monta o cliente.

  Opções:

    * `:client_id` e `:client_secret` - obrigatórias, da aplicação na conta Efí;
    * `:environment` - obrigatória, `:production` ou `:sandbox` (homologação);
    * `:certificate` - um `Efi.Certificate`, obrigatório para todas as APIs menos Cobranças;
    * `:token_store` - um módulo que implementa `Efi.TokenStore`;
    * `:partner_token` - o identificador de parceiro Efí, enviado no header `partner-token` das
      chamadas às APIs. A documentação da Efí não descreve o header; ele vem dos SDKs oficiais
      de PHP, Python e Node, que o mandam nas chamadas às APIs;
    * `:receive_timeout` - em milissegundos, padrão `30_000`;
    * `:req_options` - mesclado por último nas opções do `Req`, vence os padrões. Headers e
      `params` daqui se somam aos da biblioteca em vez de trocá-los.

  A falta de uma opção obrigatória ou um valor inválido volta como
  `%Efi.Error{kind: :configuration, reason: {opção, :required | :invalid}}`.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    with :ok <- check_required(opts),
         :ok <- check_environment(opts[:environment]),
         :ok <- check_certificate(opts[:certificate]) do
      {:ok, struct!(__MODULE__, opts)}
    end
  end

  @doc """
  Pede um token novo para `api` e o guarda no `token_store`, se houver.

  As funções das APIs já fazem isso sozinhas quando precisam. Chamar direto serve para
  conferir credenciais e certificado, por exemplo logo depois de abrir a conta de um cliente.
  """
  @spec authorize(t(), api()) :: {:ok, Token.t()} | {:error, Error.t()}
  def authorize(%__MODULE__{} = client, api) do
    with :ok <- check_access(client, api),
         {:ok, token} <- request_token(client, api) do
      store_token(client, api, token)
      {:ok, token}
    end
  end

  @doc """
  Faz uma requisição autenticada e devolve o corpo da resposta.

  O corpo JSON volta decodificado com chaves em texto, como a Efí escreve. Um corpo vazio volta
  como `nil`, e um corpo que não é JSON (PDF, CNAB) volta como binário. Usado pelos módulos das
  APIs; um app só chama direto para uma rota que a biblioteca ainda não cobre.
  """
  @spec request(t(), api(), :get | :post | :put | :patch | :delete, String.t(), keyword()) ::
          Efi.result()
  def request(%__MODULE__{} = client, api, method, path, opts \\ []) do
    opts = Keyword.validate!(opts, @request_options)

    with :ok <- check_access(client, api),
         {:ok, token, source} <- current_token(client, api) do
      client
      |> send_request(api, method, path, token, opts)
      |> retry_with_fresh_token(client, api, method, path, opts, source)
    end
  end

  @doc """
  Monta o caminho de uma rota a partir do modelo da documentação, codificando cada valor.

  Um valor ausente, `nil`, vazio, `"."` ou `".."` levanta `ArgumentError`: com ele, o caminho
  apontaria para outra rota (`GET /v2/cob/` é a lista de cobranças, não uma cobrança).

      iex> Efi.Client.path("/v2/pix/:e2eId/devolucao/:id", e2eId: "E123", id: "dev 1")
      "/v2/pix/E123/devolucao/dev%201"

      iex> Efi.Client.path("/v1/pagamentos/pix/:id/devolver", id: "urn:efi:a/b")
      "/v1/pagamentos/pix/urn:efi:a%2Fb/devolver"
  """
  @spec path(String.t(), keyword()) :: String.t()
  def path(template, values) do
    values = Map.new(values, fn {name, value} -> {Atom.to_string(name), value} end)

    Regex.replace(~r/:([A-Za-z_][A-Za-z0-9_]*)/, template, fn _match, name ->
      case Map.fetch(values, name) do
        {:ok, value} when value in [nil, "", ".", ".."] ->
          raise ArgumentError, "invalid value #{inspect(value)} for :#{name} in #{template}"

        {:ok, value} ->
          URI.encode(to_string(value), &path_character?/1)

        :error ->
          raise ArgumentError, "missing value for :#{name} in #{template}"
      end
    end)
  end

  # Dois-pontos e arroba valem num segmento de caminho (RFC 3986) e ficam como estão: os
  # identificadores de pagamento do Open Finance são URNs (`urn:efi:...`). A barra é codificada,
  # para um valor nunca virar outro segmento.
  defp path_character?(character), do: URI.char_unreserved?(character) or character in ~c":@"

  defp check_required(opts) do
    case Enum.find([:client_id, :client_secret, :environment], &blank?(opts[&1])) do
      nil -> :ok
      key -> configuration_error({key, :required})
    end
  end

  defp blank?(value), do: value in [nil, ""]

  defp check_environment(environment) when environment in @environments, do: :ok
  defp check_environment(_environment), do: configuration_error({:environment, :invalid})

  defp check_certificate(nil), do: :ok
  defp check_certificate(%Certificate{}), do: :ok
  defp check_certificate(_certificate), do: configuration_error({:certificate, :invalid})

  defp check_access(client, api) do
    with :ok <- require_environment(client, api), do: require_certificate(client, api)
  end

  defp require_environment(%__MODULE__{environment: environment}, api) do
    if Map.has_key?(Map.fetch!(@hosts, api), environment),
      do: :ok,
      else: configuration_error({:environment, :unsupported})
  end

  defp require_certificate(_client, api) when api in @apis_without_mtls, do: :ok

  defp require_certificate(%__MODULE__{certificate: %Certificate{} = certificate}, _api) do
    if Certificate.expired?(certificate, DateTime.utc_now()),
      do: {:error, %Error{kind: :certificate, reason: :expired}},
      else: :ok
  end

  defp require_certificate(_client, _api), do: configuration_error({:certificate, :required})

  defp configuration_error(reason), do: {:error, %Error{kind: :configuration, reason: reason}}

  defp current_token(%__MODULE__{token_store: nil} = client, api), do: fresh_token(client, api)

  defp current_token(%__MODULE__{token_store: store} = client, api) do
    with {:ok, token} <- store.fetch(token_key(client, api)),
         true <- Token.usable?(token, DateTime.utc_now()) do
      {:ok, token, :store}
    else
      _missing_or_expired -> fresh_token(client, api)
    end
  end

  defp fresh_token(client, api) do
    with {:ok, token} <- authorize(client, api), do: {:ok, token, :fresh}
  end

  defp store_token(%__MODULE__{token_store: nil}, _api, _token), do: :ok

  defp store_token(%__MODULE__{token_store: store} = client, api, token),
    do: store.put(token_key(client, api), token)

  defp token_key(client, api), do: {api, client.environment, client.client_id}

  defp retry_with_fresh_token(
         {:error, %Error{kind: :unauthorized}},
         client,
         api,
         method,
         path,
         opts,
         :store
       ) do
    with {:ok, token} <- authorize(client, api) do
      send_request(client, api, method, path, token, opts)
    end
  end

  defp retry_with_fresh_token(result, _client, _api, _method, _path, _opts, _source), do: result

  defp request_token(client, api) do
    [
      method: :post,
      url: Map.fetch!(@token_paths, api),
      auth: {:basic, "#{client.client_id}:#{client.client_secret}"},
      json: %{grant_type: "client_credentials"}
    ]
    |> build_request(client, api, client.receive_timeout)
    |> Req.request()
    |> case do
      {:ok, %Req.Response{} = response} -> token_from_response(response)
      {:error, exception} -> {:error, %Error{kind: :transport, reason: exception}}
    end
  end

  # Um 2xx sem `access_token`, como a página HTML de um proxy, também é falha do pedido do token.
  defp token_from_response(%Req.Response{status: status} = response) do
    case decode(response) do
      %{"access_token" => access_token} = body
      when status in 200..299 and is_binary(access_token) ->
        {:ok, Token.from_response(body, DateTime.utc_now())}

      body ->
        error = Error.from_response(status, body, response.headers)
        {:error, %{error | kind: :authentication}}
    end
  end

  defp send_request(client, api, method, path, token, opts) do
    [
      method: method,
      url: path,
      headers: request_headers(client, token, opts),
      json: opts[:json],
      params: opts[:params]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> build_request(client, api, Keyword.get(opts, :receive_timeout, client.receive_timeout))
    |> Req.request()
    |> classify()
  end

  defp request_headers(client, token, opts) do
    [{"authorization", Token.authorization_header(token)}]
    |> add_header("partner-token", client.partner_token)
    |> add_header("x-idempotency-key", opts[:idempotency_key])
    |> add_header("x-skip-mtls-checking", if(opts[:skip_mtls_checking], do: "true"))
    |> Enum.concat(Keyword.get(opts, :headers, []))
  end

  defp add_header(headers, _name, nil), do: headers
  defp add_header(headers, name, value), do: headers ++ [{name, value}]

  defp build_request(request_options, client, api, receive_timeout) do
    [
      base_url: @hosts |> Map.fetch!(api) |> Map.fetch!(client.environment),
      receive_timeout: receive_timeout,
      decode_body: false,
      redirect: false,
      retry: &retry?/2
    ]
    |> Keyword.merge(connection_options(client))
    |> Keyword.merge(request_options)
    |> Req.new()
    |> Req.merge(client.req_options)
  end

  defp connection_options(%__MODULE__{certificate: nil}), do: []

  defp connection_options(%__MODULE__{certificate: certificate}) do
    [
      finch: [
        pool_max_idle_time: @pool_max_idle_time,
        conn_opts: [transport_opts: Certificate.transport_options(certificate)]
      ]
    ]
  end

  defp classify({:ok, %Req.Response{status: status} = response}) when status in 200..299,
    do: {:ok, decode(response)}

  defp classify({:ok, %Req.Response{status: status} = response}),
    do: {:error, Error.from_response(status, decode(response), response.headers)}

  defp classify({:error, exception}), do: {:error, %Error{kind: :transport, reason: exception}}

  # O corpo é decodificado aqui e não pelo Req: um JSON quebrado numa resposta que chegou não é
  # falha de transporte, e um PDF de comprovante precisa voltar intacto.
  defp decode(%Req.Response{body: ""}), do: nil

  defp decode(%Req.Response{body: body} = response) do
    with true <- json?(response),
         {:ok, decoded} <- Jason.decode(body) do
      decoded
    else
      _not_json -> body
    end
  end

  defp json?(response) do
    response
    |> Req.Response.get_header("content-type")
    |> Enum.any?(&String.contains?(&1, "json"))
  end

  defp retry?(%Req.Request{method: :get}, outcome),
    do: transient?(outcome) and short_wait?(outcome)

  defp retry?(%Req.Request{}, outcome), do: never_sent?(outcome)

  defp transient?(%Req.Response{status: status}), do: status in @transient_statuses
  defp transient?(%Req.TransportError{reason: reason}), do: reason in @transient_reasons
  defp transient?(_outcome), do: false

  # O Req dorme o `retry-after` inteiro antes de repetir, sem teto, e quebra com um valor
  # decimal. Uma espera longa ou ilegível volta para o chamador decidir.
  defp short_wait?(%Req.Response{} = response) do
    case Req.Response.get_header(response, "retry-after") do
      [] ->
        true

      values ->
        match?(
          [{wait, ""}] when wait <= @max_retry_after_seconds,
          Enum.map(values, &Integer.parse/1)
        )
    end
  end

  defp short_wait?(_exception), do: true

  defp never_sent?(%Req.TransportError{reason: reason}), do: reason in @never_sent_reasons
  defp never_sent?(_outcome), do: false
end
