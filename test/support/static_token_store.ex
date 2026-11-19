defmodule Efi.Test.StaticTokenStore do
  @moduledoc false
  @behaviour Efi.TokenStore

  @impl Efi.TokenStore
  def fetch(_key) do
    {:ok,
     %Efi.Token{
       access_token: "token-de-teste",
       token_type: "Bearer",
       expires_at: ~U[2099-01-01 00:00:00Z]
     }}
  end

  @impl Efi.TokenStore
  def put(_key, _token), do: :ok
end
