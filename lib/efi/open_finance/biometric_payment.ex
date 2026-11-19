defmodule Efi.OpenFinance.BiometricPayment do
  @moduledoc """
  Pix por biometria, a jornada sem redirecionamento do Open Finance: o pagador vincula a conta
  do banco dele uma vez, e os pagamentos seguintes saem desse vínculo, confirmados com
  biometria.

  Exige Conta Digital Efí Empresas.

  ## Vínculo

  `create_enrollment/4` recebe o pagador (`"cpf"`, `"cnpj"` opcional e o `"idParticipante"`
  do banco dele) e devolve `identificadorVinculo` e um `redirectURI`. O pagador abre o
  `redirectURI`, autoriza no banco, e o webhook chega com `"tipo" => "vinculo"` e
  `"status" => "autorizado"` ou `"rejeitado"`. Guarde o `identificadorVinculo` no cadastro do
  cliente: os pagamentos seguintes usam só ele.

      {:ok, %{"identificadorVinculo" => enrollment_id, "redirectURI" => bank_url}} =
        Efi.OpenFinance.BiometricPayment.create_enrollment(
          client,
          "2d7c9b1a-8e6f-4a3b-9c2d-5e4f3a2b1c0d",
          %{
            "pagador" => %{
              "idParticipante" => "9f4cd202-8f2b-11ec-b909-0242ac120002",
              "cpf" => "12345678909"
            }
          }
        )

  `list_enrollments/3` mostra os vínculos de um CPF, com conta, banco, limites e validade, para
  o cliente escolher de qual conta pagar. `revoke_enrollment/4` encerra um vínculo.

  ## Pagamento

      {:ok, %{"identificadorPagamento" => payment_id}} =
        Efi.OpenFinance.BiometricPayment.create(
          client,
          "7e8f9a0b-1c2d-4e3f-8a9b-0c1d2e3f4a5b",
          %{
            "identificadorVinculo" => enrollment_id,
            "favorecido" => %{"chave" => "chave-pix-do-studio-ana"},
            "pagamento" => %{"valor" => "50.00", "infoPagador" => "Corte e escova"}
          }
        )

  A resposta traz `identificadorPagamento` e `redirectURI`, e o resultado chega pelo webhook
  com `"tipo" => "pagamento"`, como no `Efi.OpenFinance.ImmediatePayment`. Todas as escritas
  deste módulo exigem a chave de idempotência, que vai no header `x-idempotency-key` (de 36 a
  72 caracteres).
  """

  alias Efi.Client

  @doc """
  Começa o vínculo da conta do pagador e devolve o `redirectURI` onde ele autoriza.
  `idempotency_key` vai no header `x-idempotency-key`.

  `POST /v1/pagamentos-biometria/vinculos` · escopo `gn.opb.jwr.enrollment.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-por-biometria#criar-vínculo)
  """
  @spec create_enrollment(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create_enrollment(%Client{} = client, idempotency_key, enrollment, opts \\ [])
      when is_binary(idempotency_key) do
    opts = Keyword.merge(opts, json: enrollment, idempotency_key: idempotency_key)
    Client.request(client, :open_finance, :post, "/v1/pagamentos-biometria/vinculos", opts)
  end

  @doc """
  Lista os vínculos de um pagador pelo `cpf` (obrigatório), com `cnpj` opcional para filtrar
  os da empresa.

  `GET /v1/pagamentos-biometria/vinculos` · escopo `gn.opb.jwr.enrollment.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-por-biometria#consultar-vínculos-de-um-usuário)
  """
  @spec list_enrollments(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list_enrollments(%Client{} = client, params, opts \\ []) do
    opts = Keyword.put(opts, :params, params)
    Client.request(client, :open_finance, :get, "/v1/pagamentos-biometria/vinculos", opts)
  end

  @doc """
  Revoga um vínculo com `%{"identificadorVinculo" => ..., "motivo" => ...}` (os dois
  obrigatórios). `idempotency_key` vai no header `x-idempotency-key`.

  `PATCH /v1/pagamentos-biometria/vinculos` · escopo `gn.opb.jwr.enrollment.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-por-biometria#revogar-vínculo)
  """
  @spec revoke_enrollment(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def revoke_enrollment(%Client{} = client, idempotency_key, revocation, opts \\ [])
      when is_binary(idempotency_key) do
    opts = Keyword.merge(opts, json: revocation, idempotency_key: idempotency_key)
    Client.request(client, :open_finance, :patch, "/v1/pagamentos-biometria/vinculos", opts)
  end

  @doc """
  Cria um Pix a partir de um vínculo autorizado. O destino vai em `"favorecido"`, por
  `"chave"` ou `"contaBanco"`. `idempotency_key` vai no header `x-idempotency-key`.

  `POST /v1/pagamentos-biometria/pix` · escopo `gn.opb.jwr.payment.write`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-por-biometria#criar-pagamento-via-jornada-sem-redirecionamento)
  """
  @spec create(Client.t(), String.t(), map(), keyword()) :: Efi.result()
  def create(%Client{} = client, idempotency_key, payment, opts \\ [])
      when is_binary(idempotency_key) do
    opts = Keyword.merge(opts, json: payment, idempotency_key: idempotency_key)
    Client.request(client, :open_finance, :post, "/v1/pagamentos-biometria/pix", opts)
  end

  @doc """
  Lista os pagamentos por biometria criados entre `inicio` e `fim` (datas `AAAA-MM-DD`,
  obrigatórios). Filtros opcionais: `status` (`pendente`, `rejeitado`, `aceito`, `expirado`,
  `cancelado`) e `identificador`. A lista volta na chave `"vinculos"`, como a Efí escreve.

  `GET /v1/pagamentos-biometria/pix` · escopo `gn.opb.jwr.payment.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/pagamentos-por-biometria#consultar-pagamentos-feitos-via-jornada-sem-redirecionamento)
  """
  @spec list(Client.t(), map() | keyword(), keyword()) :: Efi.result()
  def list(%Client{} = client, params, opts \\ []) do
    opts = Keyword.put(opts, :params, params)
    Client.request(client, :open_finance, :get, "/v1/pagamentos-biometria/pix", opts)
  end
end
