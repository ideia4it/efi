defmodule Efi.Error do
  @moduledoc """
  Falha de uma chamada à Efí.

  `kind` diz o que aconteceu, independente da API:

  | `kind` | Quando |
  |---|---|
  | `:validation` | 400 ou 422: a Efí recusou os dados enviados |
  | `:unauthorized` | 401: credencial, token ou certificado recusado |
  | `:forbidden` | 403: a aplicação não tem o escopo da rota |
  | `:not_found` | 404 |
  | `:conflict` | 409: o recurso já existe (por exemplo, `txid` repetido) |
  | `:precondition_failed` | 412: falta um passo antes (na Abertura de Contas, a conta ainda em análise ou o webhook não cadastrado) |
  | `:rate_limited` | 429 |
  | `:server` | 5xx |
  | `:http` | outro status fora de 2xx |
  | `:authentication` | o pedido do token de acesso falhou |
  | `:transport` | a requisição não teve resposta: timeout, conexão recusada, DNS |
  | `:certificate` | o certificado não abriu (veja `Efi.Certificate`) |
  | `:configuration` | falta algo no `%Efi.Client{}` para chamar aquela API |

  `name` e `message` vêm do corpo da resposta. Cada API da Efí devolve erro num formato, e todos
  são lidos aqui: `nome`/`mensagem` (Pix, Open Finance, Abertura de Contas), o padrão do Banco
  Central `type`/`title`/`detail` com `violacoes`, e `error`/`error_description` (Cobranças e
  OAuth), além de `descricao` (Pagamento de Contas). O corpo inteiro fica em `body`, para quem
  precisa de um campo que não foi normalizado, e os headers da resposta em `headers`: num 429, o
  `retry-after` diz quantos segundos esperar.
  """

  @type kind ::
          :validation
          | :unauthorized
          | :forbidden
          | :not_found
          | :conflict
          | :precondition_failed
          | :rate_limited
          | :server
          | :http
          | :authentication
          | :transport
          | :certificate
          | :configuration

  @type t :: %__MODULE__{
          kind: kind(),
          status: pos_integer() | nil,
          name: String.t() | nil,
          message: String.t() | nil,
          body: term(),
          headers: %{optional(String.t()) => [String.t()]},
          reason: term()
        }

  defexception [:kind, :status, :name, :message, :body, :reason, headers: %{}]

  @impl Exception
  def message(%__MODULE__{} = error) do
    [inspect(error.kind), error.status, error.name, error.message, reason_text(error.reason)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  @doc false
  @spec from_response(pos_integer(), term(), map()) :: t()
  def from_response(status, body, headers) do
    %__MODULE__{
      kind: kind_for_status(status),
      status: status,
      name: error_name(body),
      message: error_message(body),
      body: body,
      headers: headers
    }
  end

  defp reason_text(nil), do: nil
  defp reason_text(reason), do: inspect(reason)

  defp kind_for_status(status) when status in [400, 422], do: :validation
  defp kind_for_status(401), do: :unauthorized
  defp kind_for_status(403), do: :forbidden
  defp kind_for_status(404), do: :not_found
  defp kind_for_status(409), do: :conflict
  defp kind_for_status(412), do: :precondition_failed
  defp kind_for_status(429), do: :rate_limited
  defp kind_for_status(status) when status >= 500, do: :server
  defp kind_for_status(_status), do: :http

  defp error_name(%{"nome" => name}) when is_binary(name), do: name
  defp error_name(%{"error" => name}) when is_binary(name), do: name

  defp error_name(%{"type" => type}) when is_binary(type),
    do: type |> String.split("/") |> List.last()

  defp error_name(_body), do: nil

  defp error_message(%{"mensagem" => message}) when is_binary(message), do: message
  defp error_message(%{"detail" => detail}) when is_binary(detail), do: detail

  defp error_message(%{"error_description" => description}) when is_binary(description),
    do: description

  defp error_message(%{"error_description" => %{"message" => message}}) when is_binary(message),
    do: message

  defp error_message(%{"title" => title}) when is_binary(title), do: title
  defp error_message(%{"descricao" => description}) when is_binary(description), do: description
  defp error_message(_body), do: nil
end
