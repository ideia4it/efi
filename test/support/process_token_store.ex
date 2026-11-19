defmodule Efi.Test.ProcessTokenStore do
  @moduledoc false
  @behaviour Efi.TokenStore

  # O stub do Req.Test roda no processo do teste, então o dicionário do processo basta para
  # observar o que o cliente guardou sem nenhum processo extra.

  def seed(key, token), do: Process.put({__MODULE__, key}, token)

  def stored(key), do: Process.get({__MODULE__, key})

  @impl Efi.TokenStore
  def fetch(key) do
    case Process.get({__MODULE__, key}) do
      nil -> :error
      token -> {:ok, token}
    end
  end

  @impl Efi.TokenStore
  def put(key, token) do
    Process.put({__MODULE__, key}, token)
    :ok
  end
end
