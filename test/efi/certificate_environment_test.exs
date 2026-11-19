defmodule Efi.CertificateEnvironmentTest do
  # Mexe no PATH do sistema operacional, que é global: não pode rodar junto com os outros.
  use ExUnit.Case, async: false

  alias Efi.Certificate
  alias Efi.Error
  alias Efi.Test.CertificateFixtures

  @moduletag :tmp_dir

  test "says openssl is missing instead of blaming the file", %{tmp_dir: tmp_dir} do
    %{p12: p12} = CertificateFixtures.generate!(tmp_dir)
    path = System.get_env("PATH")

    try do
      System.put_env("PATH", tmp_dir)

      assert {:error, %Error{kind: :certificate, reason: :openssl_missing}} =
               Certificate.from_p12(p12)
    after
      System.put_env("PATH", path)
    end
  end
end
