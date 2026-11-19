defmodule Efi.Certificate do
  @moduledoc """
  Certificado da aplicação Efí, nas peças em DER que o `:ssl` usa no mTLS.

  As APIs Pix, Open Finance, Abertura de Contas, Pagamento de Contas e Extratos exigem o
  certificado em toda requisição, inclusive no pedido do token. A Efí entrega o certificado
  como `.p12` sem senha, tanto no painel quanto em `Efi.Accounts.SimplifiedAccount.create_certificate/3`,
  que devolve o arquivo em Base64.

  Duas formas de abrir:

    * `from_p12/3`, para o arquivo da Efí;
    * `from_pem/1`, para quem já converteu o `.p12` com
      `openssl pkcs12 -in certificado.p12 -out certificado.pem -nodes -password pass:`.

  ## Por que o openssl

  O OTP não tem leitor de PKCS#12 (`:public_key` não exporta um), então `from_p12/3` chama
  `openssl pkcs12`. Duas regras tornam isso seguro:

    * o arquivo entra pelo stdin do processo filho, nunca por arquivo temporário, porque o
      arquivo guardaria a chave privada sem cifra;
    * a senha, quando existe, entra por variável de ambiente do filho, nunca por `argv`, que é
      legível por qualquer usuário no `ps`.

  Bundles antigos usam `PBE-SHA1-RC2-40`, que o OpenSSL 3 moveu para o provider legacy. A
  primeira tentativa vai sem `-legacy` e só então repete com ele: o openssl se recusa a rodar
  quando não consegue carregar um provider pedido, então começar por `-legacy` perderia os
  arquivos modernos em todo host sem o pacote do provider.

  ## Erros

  `%Efi.Error{kind: :certificate}` com `reason`:

  | `reason` | Quando |
  |---|---|
  | `:invalid_password` | a senha não abre o arquivo |
  | `:invalid_file` | não é um PKCS#12 ou PEM completo, ou falta a chave ou o certificado |
  | `:legacy_provider_missing` | o arquivo usa cifra legada e o openssl não tem o provider |
  | `:openssl_missing` | o executável `openssl` não está no `PATH` |
  | `:timeout` | o openssl não respondeu dentro do prazo |
  """

  alias Efi.Error

  require Record

  Record.defrecordp(
    :otp_certificate,
    :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :otp_tbs_certificate,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :otp_subject_public_key_info,
    :OTPSubjectPublicKeyInfo,
    Record.extract(:OTPSubjectPublicKeyInfo, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :rsa_private_key,
    :RSAPrivateKey,
    Record.extract(:RSAPrivateKey, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :ec_private_key,
    :ECPrivateKey,
    Record.extract(:ECPrivateKey, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :validity,
    :Validity,
    Record.extract(:Validity, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  @default_timeout :timer.seconds(15)
  @private_key_types [:PrivateKeyInfo, :RSAPrivateKey, :ECPrivateKey]

  @derive {Inspect, only: [:not_before, :not_after]}
  @enforce_keys [:certificate, :key, :chain, :not_before, :not_after]
  defstruct [:certificate, :key, :chain, :not_before, :not_after]

  @type private_key :: {:PrivateKeyInfo | :RSAPrivateKey | :ECPrivateKey, binary()}

  @type t :: %__MODULE__{
          certificate: binary(),
          key: private_key(),
          chain: [binary()],
          not_before: DateTime.t(),
          not_after: DateTime.t()
        }

  @doc """
  Abre um `.p12`. A senha padrão é vazia, que é como a Efí gera os certificados.

  ## Opções

    * `:timeout` - prazo em milissegundos para a chamada inteira, incluindo a repetição com
      `-legacy`. Padrão: `15_000`.

  ## Exemplo

      {:ok, certificate} = Efi.Certificate.from_p12(File.read!("producao.p12"))
  """
  @spec from_p12(binary(), String.t(), timeout: pos_integer()) ::
          {:ok, t()} | {:error, Error.t()}
  def from_p12(bundle, password \\ "", opts \\ [])
      when is_binary(bundle) and is_binary(password) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    with :ok <- validate_der(bundle),
         {:ok, pem} <- openssl(bundle, password, deadline(timeout)) do
      from_pem(pem)
    else
      {:error, reason} -> certificate_error(reason)
    end
  end

  @doc """
  Abre um PEM com o certificado e a chave privada sem cifra, no mesmo texto.

  Aceita o que o `openssl pkcs12 -nodes` escreve: a chave em PKCS#8 (`PRIVATE KEY`), RSA ou EC,
  e um ou mais certificados. O certificado da aplicação é o que tem a chave pública da chave
  privada do arquivo; os demais vão para `chain`.
  """
  @spec from_pem(binary()) :: {:ok, t()} | {:error, Error.t()}
  def from_pem(pem) when is_binary(pem) do
    entries = :public_key.pem_decode(pem)
    certificates = for {:Certificate, der, :not_encrypted} <- entries, do: der

    with {:ok, key} <- find_private_key(entries),
         {:ok, decoded} <- decode_certificates(certificates),
         {:ok, {leaf, leaf_tbs}, chain} <- split_leaf(decoded, key),
         {:ok, not_before, not_after} <- validity_period(leaf_tbs) do
      {:ok,
       %__MODULE__{
         certificate: leaf,
         key: key,
         chain: Enum.map(chain, &elem(&1, 0)),
         not_before: not_before,
         not_after: not_after
       }}
    else
      {:error, reason} -> certificate_error(reason)
    end
  end

  @doc "Diz se `now` já passou do fim da validade."
  @spec expired?(t(), DateTime.t()) :: boolean()
  def expired?(%__MODULE__{not_after: not_after}, %DateTime{} = now),
    do: DateTime.compare(now, not_after) == :gt

  @doc false
  @spec transport_options(t()) :: keyword()
  def transport_options(%__MODULE__{} = certificate),
    do: [cert: certificate.certificate, key: certificate.key]

  defp certificate_error(reason), do: {:error, %Error{kind: :certificate, reason: reason}}

  defp find_private_key(entries) do
    case Enum.find(entries, fn {type, _der, encryption} ->
           type in @private_key_types and encryption == :not_encrypted
         end) do
      {type, der, :not_encrypted} -> {:ok, {type, der}}
      nil -> {:error, :invalid_file}
    end
  end

  defp decode_certificates(certificates) do
    {:ok, Enum.map(certificates, &{&1, tbs(&1)})}
  rescue
    _malformed -> {:error, :invalid_file}
  end

  # A ordem dos certificados dentro de um .p12 não é especificada: o da aplicação é o que casa
  # com a chave privada, e os outros são a cadeia.
  defp split_leaf(certificates, key) do
    public_key = key |> decode_private_key() |> public_key_of_private()

    case Enum.split_with(certificates, &(public_key_of_certificate(&1) == public_key)) do
      {[leaf], chain} -> {:ok, leaf, chain}
      _none_or_many -> {:error, :invalid_file}
    end
  end

  defp decode_private_key({type, der}),
    do: :public_key.pem_entry_decode({type, der, :not_encrypted})

  defp public_key_of_private(rsa_private_key(modulus: modulus, publicExponent: exponent)),
    do: {:RSAPublicKey, modulus, exponent}

  defp public_key_of_private(ec_private_key(publicKey: point)), do: {:ECPoint, point}

  defp public_key_of_certificate({_der, tbs}) do
    tbs
    |> otp_tbs_certificate(:subjectPublicKeyInfo)
    |> otp_subject_public_key_info(:subjectPublicKey)
  end

  defp tbs(der), do: der |> :public_key.pkix_decode_cert(:otp) |> otp_certificate(:tbsCertificate)

  defp validity_period(tbs) do
    validity(notBefore: not_before, notAfter: not_after) = otp_tbs_certificate(tbs, :validity)

    with {:ok, not_before} <- to_datetime(not_before),
         {:ok, not_after} <- to_datetime(not_after) do
      {:ok, not_before, not_after}
    end
  end

  # Um prazo para a chamada inteira e não um por invocação do openssl: a repetição com -legacy
  # dobraria o que o chamador foi avisado para esperar.
  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp time_left(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  # Um PKCS#12 é uma única SEQUENCE em DER, com o tamanho no cabeçalho. Conferir aqui transforma
  # um upload truncado em erro imediato, em vez de esperar o openssl desistir de uma sequência
  # que nunca termina.
  defp validate_der(
         <<0x30, header, length::big-size(header - 0x80)-unit(8), _content::binary-size(length)>>
       )
       when header > 0x80,
       do: :ok

  defp validate_der(_bundle), do: {:error, :invalid_file}

  defp openssl(bundle, password, deadline) do
    case run(bundle, password, deadline, false) do
      {:error, :unsupported_cipher} -> retry_with_legacy(bundle, password, deadline)
      result -> result
    end
  end

  # Um openssl sem a opção -legacy (LibreSSL, OpenSSL 1.1) ainda não abre a cifra: para quem
  # chama, é um arquivo que este host não lê.
  defp retry_with_legacy(bundle, password, deadline) do
    case run(bundle, password, deadline, true) do
      {:error, :unsupported_cipher} -> {:error, :invalid_file}
      result -> result
    end
  end

  defp run(bundle, password, deadline, legacy?) do
    case System.find_executable("openssl") do
      nil -> {:error, :openssl_missing}
      executable -> run(executable, bundle, password, deadline, legacy?)
    end
  end

  defp run(executable, bundle, password, deadline, legacy?) do
    {passin, env} = password_argument(password)
    args = ["pkcs12", "-in", "/dev/stdin", "-passin", passin, "-nodes"]

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: if(legacy?, do: args ++ ["-legacy"], else: args),
        env: env
      ])

    # Sem EOF: o openssl para de ler quando o tamanho do cabeçalho DER é atingido, e uma porta
    # Erlang não consegue fechar só o stdin do filho.
    Port.command(port, bundle)

    collect(port, [], deadline)
  end

  # Port.open descarta variável de ambiente com valor vazio, então a senha vazia viaja como
  # `pass:`. String.to_charlist/1 e não :binary.bin_to_list/1: o Erlang recodifica o ambiente
  # e bytes que já são UTF-8 virariam mojibake, e o openssl responderia "Mac verify error".
  defp password_argument(""), do: {"pass:", []}

  defp password_argument(password),
    do: {"env:P12_PASSWORD", [{~c"P12_PASSWORD", String.to_charlist(password)}]}

  defp collect(port, acc, deadline) do
    receive do
      {^port, {:data, data}} ->
        collect(port, [data | acc], deadline)

      {^port, {:exit_status, 0}} ->
        {:ok, IO.iodata_to_binary(Enum.reverse(acc))}

      {^port, {:exit_status, _status}} ->
        {:error, classify(IO.iodata_to_binary(Enum.reverse(acc)))}
    after
      time_left(deadline) -> abandon(port)
    end
  end

  # A porta pode morrer entre o prazo estourar e esta linha, e fechar uma porta que já foi
  # embora levanta. O que ela mandou antes fica na caixa de mensagens do chamador e precisa sair.
  defp abandon(port) do
    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    drain(port)

    {:error, :timeout}
  end

  defp drain(port) do
    receive do
      {^port, _message} -> drain(port)
    after
      0 -> :ok
    end
  end

  defp classify(output) do
    downcased = String.downcase(output)

    cond do
      downcased =~ "mac verify" -> :invalid_password
      downcased =~ "invalid password" -> :invalid_password
      downcased =~ "unable to load provider" -> :legacy_provider_missing
      downcased =~ "rc2" or downcased =~ "rc4" -> :unsupported_cipher
      downcased =~ "unsupported" -> :unsupported_cipher
      true -> :invalid_file
    end
  end

  # UTCTime (YYMMDDHHMMSSZ) até 2049 e GeneralizedTime (YYYYMMDDHHMMSSZ) depois.
  defp to_datetime({:utcTime, value}),
    do: value |> IO.chardata_to_string() |> with_century() |> parse_datetime()

  defp to_datetime({:generalTime, value}),
    do: value |> IO.chardata_to_string() |> parse_datetime()

  # RFC 5280: ano de dois dígitos de 50 em diante é 19xx, abaixo disso 20xx.
  defp with_century(<<year::binary-2, _rest::binary>> = value) when year >= "50",
    do: "19" <> value

  defp with_century(value), do: "20" <> value

  defp parse_datetime(
         <<year::binary-4, month::binary-2, day::binary-2, hour::binary-2, minute::binary-2,
           second::binary-2, "Z">>
       ) do
    with {:ok, date} <- Date.from_iso8601("#{year}-#{month}-#{day}"),
         {:ok, time} <- Time.from_iso8601("#{hour}:#{minute}:#{second}"),
         {:ok, datetime} <- DateTime.new(date, time, "Etc/UTC") do
      {:ok, datetime}
    else
      _invalid -> {:error, :invalid_file}
    end
  end

  defp parse_datetime(_value), do: {:error, :invalid_file}
end
