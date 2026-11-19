defmodule Efi.Token do
  @moduledoc """
  Token de acesso OAuth2 de uma API da Efí.

  A Efí entrega o token com `expires_in` em segundos: uma hora na maioria das APIs, 10 minutos
  na Cobranças. `expires_at` é calculado na chegada, e `usable?/2` considera o token vencido um
  minuto antes, para que uma requisição lenta não chegue à Efí com um token que expirou no
  caminho. O `inspect` esconde o `access_token`.
  """

  @safety_margin_seconds 60

  @derive {Inspect, except: [:access_token]}
  @enforce_keys [:access_token, :token_type, :expires_at]
  defstruct [:access_token, :token_type, :expires_at, :scope]

  @type t :: %__MODULE__{
          access_token: String.t(),
          token_type: String.t(),
          expires_at: DateTime.t(),
          scope: String.t() | nil
        }

  @doc false
  @spec from_response(map(), DateTime.t()) :: t()
  def from_response(%{"access_token" => access_token} = body, %DateTime{} = received_at) do
    %__MODULE__{
      access_token: access_token,
      token_type: Map.get(body, "token_type", "Bearer"),
      expires_at: DateTime.add(received_at, Map.get(body, "expires_in", 3600), :second),
      scope: body["scope"]
    }
  end

  @doc "Diz se o token ainda serve em `now`, com a margem de um minuto."
  @spec usable?(t(), DateTime.t()) :: boolean()
  def usable?(%__MODULE__{expires_at: expires_at}, %DateTime{} = now) do
    DateTime.diff(expires_at, now, :second) > @safety_margin_seconds
  end

  @doc false
  @spec authorization_header(t()) :: String.t()
  def authorization_header(%__MODULE__{token_type: token_type, access_token: access_token}),
    do: "#{token_type} #{access_token}"
end
