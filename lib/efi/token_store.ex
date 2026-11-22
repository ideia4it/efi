defmodule Efi.TokenStore do
  @moduledoc """
  Onde o app guarda os tokens de acesso entre uma chamada e outra.

  A biblioteca não tem processo nem estado. Sem um `token_store` no `%Efi.Client{}`, cada chamada
  pede um token novo antes da requisição, o que dobra o número de chamadas à Efí. Com um, o token
  é reaproveitado até faltar um minuto para vencer.

  A chave identifica a aplicação, o ambiente e a API, porque cada API da Efí emite o próprio
  token: `{api, environment, client_id}`.

  O guia "Primeiros passos" tem uma implementação em ETS com poucas linhas. Qualquer cache
  serve (Cachex, Nebulex, Redis), desde que `fetch/1` nunca levante: um erro do cache deve virar
  `:error`, e a chamada segue pedindo um token novo.
  """

  @type key :: {Efi.Client.api(), Efi.Client.environment(), String.t()}

  @doc "Devolve o token guardado para `key`, vencido ou não, ou `:error` se não houver."
  @callback fetch(key()) :: {:ok, Efi.Token.t()} | :error

  @doc "Guarda `token` para `key`, substituindo o anterior."
  @callback put(key(), Efi.Token.t()) :: :ok
end
