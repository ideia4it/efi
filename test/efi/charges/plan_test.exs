defmodule Efi.Charges.PlanTest do
  use ExUnit.Case, async: true

  alias Efi.Charges.Plan

  setup {Req.Test, :verify_on_exit!}

  @host "cobrancas-h.api.efipay.com.br"

  test "creates a monthly plan, renames it, finds it among all plans and by name, then cancels it" do
    client = Efi.Test.client(certificate: nil)

    Efi.Test.expect(:post, "#{@host}/v1/plan", fn conn, body ->
      assert body == %{"name" => "Clube de escova mensal", "interval" => 1, "repeats" => 12}

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => %{"plan_id" => 7007, "name" => "Clube de escova mensal", "interval" => 1}
      })
    end)

    Efi.Test.expect(:put, "#{@host}/v1/plan/7007", fn conn, body ->
      assert body == %{"name" => "Clube de escova"}
      Req.Test.json(conn, %{"code" => 200})
    end)

    Efi.Test.expect(:get, "#{@host}/v1/plans", fn conn, _body ->
      assert conn.query_params == %{}

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => [
          %{"plan_id" => 7001, "name" => "Clube de manicure"},
          %{"plan_id" => 7007, "name" => "Clube de escova"}
        ]
      })
    end)

    Efi.Test.expect(:get, "#{@host}/v1/plans", fn conn, _body ->
      assert conn.query_params == %{"name" => "Clube de escova", "limit" => "10"}

      Req.Test.json(conn, %{
        "code" => 200,
        "data" => [%{"plan_id" => 7007, "name" => "Clube de escova"}]
      })
    end)

    Efi.Test.expect(:delete, "#{@host}/v1/plan/7007", fn conn, _body ->
      Req.Test.json(conn, %{"code" => 200})
    end)

    assert {:ok, %{"data" => %{"plan_id" => 7007}}} =
             Plan.create(client, %{
               "name" => "Clube de escova mensal",
               "interval" => 1,
               "repeats" => 12
             })

    assert {:ok, %{"code" => 200}} = Plan.update(client, 7007, %{"name" => "Clube de escova"})

    assert {:ok, %{"data" => [_manicure, %{"plan_id" => 7007}]}} = Plan.list(client)

    assert {:ok, %{"data" => [%{"plan_id" => 7007}]}} =
             Plan.list(client, params: %{"name" => "Clube de escova", "limit" => 10})

    assert {:ok, %{"code" => 200}} = Plan.delete(client, 7007)
  end
end
