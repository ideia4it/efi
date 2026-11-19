# O provider legacy do OpenSSL 3 vem num pacote à parte em várias distribuições. Sem ele, o
# teste do .p12 antigo fica de fora em vez de falhar.
legacy_provider? =
  match?(
    {_output, 0},
    System.cmd("openssl", ~w(list -providers -provider legacy), stderr_to_stdout: true)
  )

ExUnit.start(exclude: [:sandbox | if(legacy_provider?, do: [], else: [:openssl_legacy])])
