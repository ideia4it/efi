defmodule Efi.Test.CertificateFixtures do
  @moduledoc false

  # Gera, com o openssl do sistema, os mesmos tipos de arquivo que a Efí entrega: uma CA, um
  # certificado de aplicação emitido por ela e o .p12 sem senha. Nada disso é commitado, para
  # que nenhuma chave privada viva no repositório.

  def generate!(directory) do
    File.mkdir_p!(directory)

    openssl!(directory, ~w(req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=ca-de-teste
      -keyout ca.key -out ca.pem))

    openssl!(directory, ~w(req -newkey rsa:2048 -nodes -subj /CN=studio-ana
      -keyout app.key -out app.csr))

    openssl!(directory, ~w(x509 -req -in app.csr -CA ca.pem -CAkey ca.key -CAcreateserial
      -days 30 -out app.pem))

    openssl!(directory, ~w(req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30
      -subj /CN=studio-ana-ec -keyout ec.key -out ec.pem))

    openssl!(directory, ~w(req -x509 -newkey rsa:2048 -nodes -days 30 -subj /CN=localhost
      -keyout server.key -out server.pem))

    export!(directory, "efi.p12", ["-passout", "pass:", "-certfile", "ca.pem"])
    export!(directory, "with_password.p12", ["-passout", "pass:senhação"])

    %{
      directory: directory,
      p12: read!(directory, "efi.p12"),
      p12_with_password: read!(directory, "with_password.p12"),
      app_pem: read!(directory, "app.pem"),
      app_key: read!(directory, "app.key"),
      ca_pem: read!(directory, "ca.pem"),
      ec_pem: read!(directory, "ec.key") <> read!(directory, "ec.pem")
    }
  end

  def legacy_p12!(directory) do
    export!(directory, "legacy.p12", ["-passout", "pass:", "-legacy"])
    read!(directory, "legacy.p12")
  end

  def der_certificate(pem) do
    [{:Certificate, der, :not_encrypted} | _rest] = :public_key.pem_decode(pem)
    der
  end

  defp export!(directory, name, extra) do
    openssl!(directory, ~w(pkcs12 -export -inkey app.key -in app.pem -out #{name}) ++ extra)
  end

  defp read!(directory, name), do: File.read!(Path.join(directory, name))

  defp openssl!(directory, args) do
    {output, status} = System.cmd("openssl", args, cd: directory, stderr_to_stdout: true)
    if status != 0, do: raise("openssl #{Enum.join(args, " ")} failed: #{output}")
  end
end
