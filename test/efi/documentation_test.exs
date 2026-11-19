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
          arguments =
            module
            |> Documentation.parameter_names(name, arity)
            |> Enum.map(&argument(&1, client)),
          {:ok, called} = apply(module, name, arguments),
          called != "#{method} #{String.replace(path, ":param", @path_value)}",
          do: {module, name, called}

    assert mismatches == []
  end

  defp argument(:client, client), do: client
  defp argument(:opts, _client), do: []
  defp argument(:params, _client), do: %{}
  defp argument(_path_value_or_body, _client), do: @path_value
end
