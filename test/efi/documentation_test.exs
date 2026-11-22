defmodule Efi.DocumentationTest do
  use ExUnit.Case, async: true

  alias Efi.Dev.Documentation

  @path_value "valor-do-caminho"

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

  test "every API function sends the method and path its documentation names" do
    client = Efi.Test.client(environment: :production)

    Req.Test.stub(Efi.Test.stub(), fn conn ->
      Req.Test.json(conn, "#{conn.method} #{conn.request_path}")
    end)

    mismatches =
      for module <- Documentation.api_modules(),
          {{^module, name, arity}, text} <- Documentation.function_docs(module),
          [{method, path}] = Documentation.routes(text),
          {:ok, called} = call(module, name, arity, client, []),
          called != "#{method} #{String.replace(path, ":param", @path_value)}",
          do: {module, name, called}

    assert mismatches == []
  end

  test "every API function keeps the optional query parameters passed in opts" do
    client = Efi.Test.client(environment: :production)

    Req.Test.stub(Efi.Test.stub(), fn conn ->
      Req.Test.json(conn, conn.query_string)
    end)

    dropped =
      for module <- Documentation.api_modules(),
          {{^module, name, arity}, _text} <- Documentation.function_docs(module),
          {:ok, query} = call(module, name, arity, client, params: %{"filtro" => "opcional"}),
          not String.contains?(query, "filtro=opcional"),
          do: {module, name}

    assert dropped == []
  end

  defp call(module, name, arity, client, opts) do
    arguments =
      module
      |> Documentation.parameter_names(name, arity)
      |> Enum.map(&argument(&1, client, opts))

    apply(module, name, arguments)
  end

  defp argument(:client, client, _opts), do: client
  defp argument(:opts, _client, opts), do: opts
  defp argument(:params, _client, _opts), do: %{}
  defp argument(_path_value_or_body, _client, _opts), do: @path_value
end
