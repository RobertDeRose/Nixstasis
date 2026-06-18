defmodule NixstasisWeb.BuilderConfigValidationControllerTest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices

  setup do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:22",
        "product_name" => "sensor-v2",
        "schema" => %{
          "product" => "sensor-v2",
          "version" => "v2",
          "properties" => %{
            "pressure" => %{"type" => "number"}
          }
        }
      })

    :ok
  end

  test "POST /api/v1/builder-configurations/validate returns validation details", %{conn: conn} do
    payload = %{
      "builder" => "report",
      "schema_id" => "sensor-v2",
      "schema_version" => "v2",
      "selections" => [
        %{"slot_id" => "a", "selected_key" => "pressure"},
        %{"slot_id" => "b", "selected_key" => "missing"}
      ]
    }

    conn = post(conn, ~p"/api/v1/builder-configurations/validate", payload)
    body = json_response(conn, 200)

    assert body["valid"] == false
    assert body["cleared_slot_ids"] == ["b"]
  end

  test "POST /api/v1/builder-configurations/validate rejects malformed selections", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/builder-configurations/validate", %{
        "builder" => "report",
        "schema_id" => "sensor-v2",
        "schema_version" => "v2",
        "selections" => %{"slot_id" => "a", "selected_key" => "pressure"}
      })

    assert %{"error" => %{"code" => "invalid_validation_payload"}} = json_response(conn, 422)
  end

  test "POST /api/v1/builder-configurations/validate rejects missing selections", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/builder-configurations/validate", %{
        "builder" => "report",
        "schema_id" => "sensor-v2",
        "schema_version" => "v2"
      })

    assert %{"error" => %{"code" => "invalid_validation_payload"}} = json_response(conn, 422)
  end

  test "POST /api/v1/builder-configurations/validate rejects invalid builders", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/builder-configurations/validate", %{
        "builder" => "unknown",
        "schema_id" => "sensor-v2",
        "schema_version" => "v2",
        "selections" => [%{"slot_id" => "a", "selected_key" => "pressure"}]
      })

    assert %{"error" => %{"code" => "invalid_validation_payload"}} = json_response(conn, 422)
  end

  test "POST /api/v1/builder-configurations/validate rejects incomplete selection items", %{conn: conn} do
    conn =
      post(conn, ~p"/api/v1/builder-configurations/validate", %{
        "builder" => "report",
        "schema_id" => "sensor-v2",
        "schema_version" => "v2",
        "selections" => [%{"slot_id" => "a"}]
      })

    assert %{"error" => %{"code" => "invalid_validation_payload"}} = json_response(conn, 422)
  end

  test "POST /api/v1/builder-configurations/validate handles missing request fields", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/builder-configurations/validate", %{"selections" => []})

    assert %{"error" => %{"code" => "invalid_validation_payload"}} = json_response(conn, 422)
  end
end
