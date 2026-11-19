defmodule Efi.CertificateTest do
  use ExUnit.Case, async: true

  alias Efi.Certificate
  alias Efi.Error
  alias Efi.Test.CertificateFixtures

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, fixtures: CertificateFixtures.generate!(tmp_dir)}
  end

  test "opens Efí's passwordless .p12 and authenticates with it in a real mTLS handshake", %{
    fixtures: fixtures
  } do
    assert {:ok, %Certificate{} = certificate} = Certificate.from_p12(fixtures.p12)

    assert certificate.certificate == CertificateFixtures.der_certificate(fixtures.app_pem)
    assert certificate.chain == [CertificateFixtures.der_certificate(fixtures.ca_pem)]
    assert DateTime.compare(certificate.not_before, certificate.not_after) == :lt
    refute Certificate.expired?(certificate, DateTime.utc_now())
    assert Certificate.expired?(certificate, DateTime.add(certificate.not_after, 1, :second))

    assert handshake_peer_certificate(fixtures.directory, certificate) == certificate.certificate
    refute inspect(certificate) =~ "PrivateKeyInfo"
  end

  test "opens a .p12 whose password has accents and refuses the wrong password", %{
    fixtures: fixtures
  } do
    assert {:ok, %Certificate{}} = Certificate.from_p12(fixtures.p12_with_password, "senhação")

    assert {:error, %Error{kind: :certificate, reason: :invalid_password}} =
             Certificate.from_p12(fixtures.p12_with_password, "errada")
  end

  @tag :openssl_legacy
  test "opens an old RC2 export through the legacy provider", %{fixtures: fixtures} do
    legacy = CertificateFixtures.legacy_p12!(fixtures.directory)
    assert {:ok, %Certificate{}} = Certificate.from_p12(legacy)
  end

  test "opens a PEM with an EC key, as converted by openssl pkcs12 -nodes", %{fixtures: fixtures} do
    assert {:ok, %Certificate{key: {:PrivateKeyInfo, _der}, chain: []}} =
             Certificate.from_pem(fixtures.ec_pem)

    assert {:ok, %Certificate{}} = Certificate.from_pem(fixtures.app_key <> fixtures.app_pem)
  end

  test "reads validity dates before 2000 and after 2049, each in its own ASN.1 time format" do
    %{cert: der, key: key} =
      :public_key.pkix_test_root_cert(~c"Studio Ana",
        validity: {{1999, 1, 1}, {2051, 1, 1}},
        key: {:rsa, 2048, 65_537}
      )

    pem =
      :public_key.pem_encode([
        {:RSAPrivateKey, :public_key.der_encode(:RSAPrivateKey, key), :not_encrypted},
        {:Certificate, der, :not_encrypted}
      ])

    assert {:ok, %Certificate{not_before: not_before, not_after: not_after}} =
             Certificate.from_pem(pem)

    assert not_before.year == 1999
    assert not_after.year == 2051
  end

  test "refuses what is not a complete certificate with its key", %{fixtures: fixtures} do
    der_sequence_of_junk = <<0x30, 0x81, 0x80>> <> :binary.copy(<<0x01>>, 0x80)

    for bundle <- [
          "não é um p12",
          binary_part(fixtures.p12, 0, 200),
          <<0x30, 0x82, 0x01>>,
          der_sequence_of_junk
        ] do
      assert {:error, %Error{kind: :certificate, reason: :invalid_file}} =
               Certificate.from_p12(bundle)
    end

    key_without_its_certificate = fixtures.app_key <> fixtures.ca_pem

    corrupted_certificate =
      fixtures.app_key <>
        :public_key.pem_encode([{:Certificate, "não é DER", :not_encrypted}])

    for pem <- [
          fixtures.app_pem,
          fixtures.app_key,
          key_without_its_certificate,
          corrupted_certificate,
          "texto qualquer"
        ] do
      assert {:error, %Error{kind: :certificate, reason: :invalid_file}} =
               Certificate.from_pem(pem)
    end
  end

  test "gives up on an openssl that does not answer in time", %{fixtures: fixtures} do
    assert {:error, %Error{kind: :certificate, reason: :timeout}} =
             Certificate.from_p12(fixtures.p12, "", timeout: 0)
  end

  defp handshake_peer_certificate(directory, certificate) do
    {:ok, listen_socket} =
      :ssl.listen(0,
        certfile: Path.join(directory, "server.pem") |> String.to_charlist(),
        keyfile: Path.join(directory, "server.key") |> String.to_charlist(),
        cacertfile: Path.join(directory, "ca.pem") |> String.to_charlist(),
        verify: :verify_peer,
        fail_if_no_peer_cert: true,
        active: false
      )

    {:ok, {_address, port}} = :ssl.sockname(listen_socket)

    server =
      Task.async(fn ->
        {:ok, socket} = :ssl.transport_accept(listen_socket, 5_000)
        {:ok, socket} = :ssl.handshake(socket, 5_000)
        {:ok, peer_certificate} = :ssl.peercert(socket)
        peer_certificate
      end)

    {:ok, client_socket} =
      :ssl.connect(
        ~c"localhost",
        port,
        Certificate.transport_options(certificate) ++ [verify: :verify_none, active: false],
        5_000
      )

    peer_certificate = Task.await(server)
    :ssl.close(client_socket)
    :ssl.close(listen_socket)
    peer_certificate
  end
end
