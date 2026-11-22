defmodule Efi.Dev.Documentation do
  @moduledoc false

  # Lê a documentação compilada dos módulos de API para as conferências que garantem que cada
  # rota da Efí tem uma função, com o link para a seção certa da doc oficial.

  @api_namespaces ~w(Pix Charges OpenFinance Accounts BillPayments Statements)
  @docs_link ~r{https://dev\.efipay\.com\.br/(?:en/)?docs/[^\s)\]>"']+}
  @route_line ~r{`(GET|POST|PUT|PATCH|DELETE) (/[^`\s]+)`}

  def api_modules do
    {:ok, modules} = :application.get_key(:efi, :modules)

    modules
    |> Enum.filter(&api_module?/1)
    |> Enum.sort()
  end

  def function_docs(module) do
    {:docs_v1, _anno, :elixir, _format, _moduledoc, _metadata, docs} = Code.fetch_docs(module)

    for {{:function, name, arity}, _anno, _signature, doc, _metadata} <- docs,
        doc != :hidden,
        do: {{module, name, arity}, doc_text(doc)}
  end

  @doc "Nomes dos argumentos de uma função, lidos da assinatura guardada na documentação."
  def parameter_names(module, name, arity) do
    {:docs_v1, _anno, :elixir, _format, _moduledoc, _metadata, docs} = Code.fetch_docs(module)
    {_key, _anno, [signature], _doc, _metadata} = List.keyfind(docs, {:function, name, arity}, 0)
    {^name, _meta, arguments} = Code.string_to_quoted!(signature)

    Enum.map(arguments, fn
      {:\\, _meta, [{argument, _argument_meta, _context}, _default]} -> argument
      {argument, _meta, _context} -> argument
    end)
  end

  def all_docs do
    {:ok, modules} = :application.get_key(:efi, :modules)
    Enum.flat_map(modules, &module_docs/1)
  end

  def links(text), do: @docs_link |> Regex.scan(text) |> List.flatten()

  def routes(text) do
    for [_line, method, path] <- Regex.scan(@route_line, text), do: {method, normalize_path(path)}
  end

  # Os nomes dos parâmetros mudam entre a doc e o código (`:e2eId`, `:e2eid`), e o que importa
  # para saber se a rota está coberta é só a forma do caminho.
  def normalize_path(path) do
    path
    |> String.trim_trailing("/")
    |> String.replace(~r{:[A-Za-z_][A-Za-z0-9_]*}, ":param")
  end

  def inventory do
    "dev/endpoints.json"
    |> File.read!()
    |> Jason.decode!()
  end

  defp api_module?(module) do
    case Module.split(module) do
      ["Efi", namespace | _rest] -> namespace in @api_namespaces
      _other -> false
    end
  end

  defp module_docs(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _anno, :elixir, _format, moduledoc, _metadata, docs} ->
        function_entries =
          for {{_kind, name, arity}, _anno, _signature, doc, _metadata} <- docs,
              do: {{module, name, arity}, doc_text(doc)}

        [{module, doc_text(moduledoc)} | function_entries]

      _no_docs ->
        []
    end
  end

  defp doc_text(%{"en" => text}), do: text
  defp doc_text(_none_or_hidden), do: ""
end
