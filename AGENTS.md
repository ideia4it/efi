# Efi

Biblioteca Elixir para as APIs da Efí (Pix, Cobranças, Open Finance, Abertura de Contas, Pagamento de Contas e Extratos), pública no GitHub e no Hex: nada de credencial, certificado, chave Pix, CPF ou CNPJ real em código, teste, fixture ou doc. Só cliente: nenhum schema de banco, worker ou rota. Quem liga a biblioteca a uma funcionalidade é o app que a consome.

## Comandos

```bash
mix deps.get
mix precommit      # compile --warnings-as-errors + format + credo --strict + test --cover (falha abaixo de 99%)
mix test --only sandbox   # jornadas na homologação da Efí, exige as variáveis EFI_SANDBOX_*
mix efi.check_links       # confere se cada link de @doc aponta para uma âncora que existe na doc da Efí
```

## Regras

- Uma função pública por rota da Efí, no módulo do recurso. `dev/endpoints.json` é o inventário das rotas
- Toda função de API devolve `Efi.result()`: `{:ok, corpo}` ou `{:error, %Efi.Error{}}`, e passa por `Efi.Client.request/5`. Nenhum módulo de API fala HTTP sozinho
- Parâmetros e respostas são mapas com chaves em texto e os nomes da Efí (`"calendario"`, `"valor"`), sem tradução e sem struct por rota
- Assinatura: `funcao(client, ids_do_caminho..., corpo_ou_params_obrigatorios, opts \\ [])`. Query string opcional vai em `opts[:params]` e corpo opcional em `opts[:json]`; obrigatórios são argumento. Header que a Efí exige, como a chave de idempotência do Open Finance, também é argumento
- Nomes de função: `create`, `get`, `list`, `update`, `delete`, `get_<coisa>` para leitura de um recurso derivado (`get_qr_code`) e verbo próprio só quando a rota faz outra coisa (`pay`, `refund`, `cancel`)
- Caminho sempre por `Efi.Client.path/2` com o modelo exato da doc (`"/v2/pix/:e2eId/devolucao/:id"`), nunca interpolado à mão
- O `@doc` de toda função de API tem: uma frase do que faz, a linha `` `MÉTODO /caminho` · escopo `x.y` `` (sem escopo, só o método e o caminho) e o link `[Documentação da Efí](https://dev.efipay.com.br/docs/...#ancora)` para a âncora exata da seção
- Sem `Application`, sem processo e sem `Application.get_env`: tudo passa por `%Efi.Client{}`
- Dependências de runtime: só `req` e `jason`
- HTTP nos testes só por `Req.Test` (`Efi.Test.client/1` e `Efi.Test.expect/3`), nunca Mimic
- Teste é jornada, um por fluxo, com nome em inglês no estilo BDD; testes de um módulo ficam no arquivo de teste dele. A jornada confere método, host, caminho, corpo e query que saem, e o que volta
- Exemplos e fixtures usam a empresa fictícia "Studio Ana", o CPF de teste `12345678909` e o CNPJ de teste `11222333000181`
- `@moduledoc`, `@doc`, comentários, README e guias em pt-BR com acentuação; identificadores em inglês. Comentário só para o porquê. Nunca use travessão. Comentário que começa com "Todo" dispara o `TagTODO` do Credo
- Commits no estilo conventional, em pt-BR
- Push, PR e `mix hex.publish` só por ordem explícita
