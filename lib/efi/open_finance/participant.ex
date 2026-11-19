defmodule Efi.OpenFinance.Participant do
  @moduledoc """
  Instituições participantes do Open Finance: os bancos onde o pagador pode ter conta.

  Toda iniciação de pagamento pede o `idParticipante` do banco do pagador. O caminho comum é
  listar os participantes, mostrar nome e logo para o pagador escolher o banco dele e guardar o
  `identificador` escolhido para mandar em `"pagador" => %{"idParticipante" => ...}`.

      {:ok, %{"participantes" => participants}} =
        Efi.OpenFinance.Participant.list(client, params: %{"modalidade" => "pagamentos"})

      Enum.map(participants, &{&1["nome"], &1["identificador"], &1["logo"]})

  Filtros opcionais em `opts[:params]`:

    * `"nome"` - parte do nome da instituição;
    * `"organizacao"` - com `false`, volta só a marca pesquisada, sem as outras marcas do mesmo
      conglomerado;
    * `"modalidade"` - `"pagamentos"` (imediato, agendado e recorrente), `"biometria"` ou
      `"automatico"`. Nem todo banco oferece todas as modalidades, então filtre pela que a sua
      tela vai iniciar;
    * `"tipoPessoa"` - `"PF"` ou `"PJ"`, para mostrar só os bancos com conta para aquele público.

  Uma busca sem resultado volta como erro, não como lista vazia:
  `%Efi.Error{kind: :not_found, name: "participante_nao_encontrado"}`.
  """

  alias Efi.Client

  @doc """
  Lista as instituições ativas no Open Finance. Sem filtros, traz todas.

  `GET /v1/participantes` · escopo `gn.opb.participants.read`

  [Documentação da Efí](https://dev.efipay.com.br/docs/api-open-finance/participantes#recuperar-as-instituições-participantes-do-open-finance)
  """
  @spec list(Client.t(), keyword()) :: Efi.result()
  def list(%Client{} = client, opts \\ []) do
    Client.request(client, :open_finance, :get, "/v1/participantes", opts)
  end
end
