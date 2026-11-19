defmodule Efi.Test.UnexpectedFailureAdapter do
  @moduledoc false

  # Um adaptador que falha com uma exceção que não é Req.TransportError, como um erro de
  # protocolo HTTP/2, para provar que o cliente não a confunde com uma falha transitória.
  def run(request), do: {request, %RuntimeError{message: "protocolo inesperado"}}
end
