defmodule Efi.DocumentationTest do
  use ExUnit.Case, async: true

  alias Efi.Dev.Documentation

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
end
