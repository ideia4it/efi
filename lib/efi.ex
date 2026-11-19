defmodule Efi do
  @moduledoc """
  Cliente Elixir para as APIs da Efí.

  Cada rota da Efí é uma função num módulo do recurso, com o `@doc` apontando para a seção
  exata da documentação oficial. Os parâmetros e as respostas são mapas com os nomes que a Efí
  usa (`"calendario"`, `"valor"`, `"txid"`), sem tradução: o que a documentação mostra é o que
  se envia e o que volta.

      {:ok, charge} =
        Efi.Pix.ImmediateCharge.create(client, %{
          "calendario" => %{"expiracao" => 3600},
          "valor" => %{"original" => "50.00"},
          "chave" => "chave-pix-da-conta"
        })

  Toda função devolve `{:ok, corpo}` ou `{:error, %Efi.Error{}}`. Comece pelo guia
  "Primeiros passos" e pelo `Efi.Client`.
  """

  @typedoc "Resultado de toda chamada a uma API da Efí."
  @type result :: {:ok, term()} | {:error, Efi.Error.t()}
end
