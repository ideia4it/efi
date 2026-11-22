defmodule Efi.DocumentationTest do
  use ExUnit.Case, async: true

  alias Efi.Dev.Documentation

  @path_value "valor-do-caminho"

  @hosts %{
    "Pix" => "pix.api.efipay.com.br",
    "Charges" => "cobrancas.api.efipay.com.br",
    "OpenFinance" => "openfinance.api.efipay.com.br",
    "Accounts" => "abrircontas.api.efipay.com.br",
    "BillPayments" => "pagarcontas.api.efipay.com.br",
    "Statements" => "extratos.api.efipay.com.br"
  }

  test "every API function names its route and links to its section of Efí's documentation" do
    undocumented =
      for module <- Documentation.api_modules(),
          {function, text} <- Documentation.function_docs(module),
          Documentation.links(text) == [] or Documentation.routes(text) == [],
          do: function

    assert undocumented == []
  end

  test "every route in the inventory has a function, unless the inventory says why not" do
    documented_routes =
      for module <- Documentation.api_modules(),
          {_function, text} <- Documentation.function_docs(module),
          route <- Documentation.routes(text),
          into: MapSet.new(),
          do: route

    missing =
      for endpoint <- Documentation.inventory(),
          is_nil(endpoint["skip"]),
          route = {endpoint["method"], Documentation.normalize_path(endpoint["path"])},
          not MapSet.member?(documented_routes, route),
          uniq: true,
          do: route

    assert missing == []
  end

  test "every API function names the scope and the documentation page the inventory has for its route" do
    inventory =
      Documentation.inventory()
      |> Enum.reject(& &1["skip"])
      |> Enum.group_by(&{&1["method"], Documentation.normalize_path(&1["path"])})

    mismatches =
      for module <- Documentation.api_modules(),
          {function, text} <- Documentation.function_docs(module),
          [route] = Documentation.routes(text),
          entries = Map.get(inventory, route, []),
          problem <- [scope_problem(text, entries), page_problem(text, entries)],
          problem != nil,
          do: {function, problem}

    assert mismatches == []
  end

  test "every API function calls its API's host with the method and path its documentation names" do
    client = Efi.Test.client(environment: :production)

    Req.Test.stub(Efi.Test.stub(), fn conn ->
      Req.Test.json(conn, "#{conn.method} #{conn.host}#{conn.request_path}")
    end)

    mismatches =
      for module <- Documentation.api_modules(),
          {{^module, name, arity}, text} <- Documentation.function_docs(module),
          [{method, path}] = Documentation.routes(text),
          arguments =
            module
            |> Documentation.parameter_names(name, arity)
            |> Enum.map(&argument(&1, client)),
          {:ok, called} = apply(module, name, arguments),
          called != "#{method} #{host(module)}#{String.replace(path, ":param", @path_value)}",
          do: {module, name, called}

    assert mismatches == []
  end

  defp scope_problem(text, entries) do
    documented = with [_line, scope] <- Regex.run(~r/· escopo `([^`]+)`/, text), do: scope

    case entries |> Enum.map(& &1["scope"]) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] -> nil
      scopes -> if documented not in scopes, do: {:scope, documented, scopes}
    end
  end

  # A âncora ainda não é comparada: Efi.Charges.Carnet.settle/3 e Efi.Charges.Notification.get/3
  # apontam para a seção pai da que o inventário registra.
  defp page_problem(text, entries) do
    documented = text |> Documentation.links() |> Enum.map(&page/1)

    case entries |> Enum.map(& &1["doc"]) |> Enum.reject(&is_nil/1) |> Enum.map(&page/1) do
      [] -> nil
      pages -> if Enum.all?(documented, &(&1 not in pages)), do: {:page, documented, pages}
    end
  end

  defp page(url), do: url |> URI.parse() |> Map.put(:fragment, nil) |> URI.to_string()

  defp host(module) do
    ["Efi", namespace | _rest] = Module.split(module)
    Map.fetch!(@hosts, namespace)
  end

  defp argument(:client, client), do: client
  defp argument(:opts, _client), do: []
  defp argument(:params, _client), do: %{}
  defp argument(_path_value_or_body, _client), do: @path_value
end
