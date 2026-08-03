defmodule NixstasisWeb.DeviceRuntimeJSONAPITest do
  use NixstasisWeb.ConnCase

  require Ash.Query

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.Telemetry
  alias Nixstasis.Scripts
  alias NixstasisWeb.Plugs.JsonApiPermissions

  setup do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    {:ok, pending} =
      Devices.create_device(%{
        mac_address: "AA:BB:CC:DD:EE:01",
        product_name: "runtime-pending",
        approval_status: :pending,
        ipv4_address: "192.0.2.10"
      })

    {:ok, approved} =
      Devices.create_device(%{
        mac_address: "AA:BB:CC:DD:EE:02",
        product_name: "runtime-approved",
        account_number: "12345",
        approval_status: :approved,
        ipv4_address: "192.0.2.11",
        last_seen_at: DateTime.utc_now()
      })

    {:ok, approved, token} = Devices.issue_device_token(approved)

    %{pending: pending, approved: approved, token: token}
  end

  test "generated list uses the device filters and active-filter metadata", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("x-token-user-roles", "nixstasis/viewer")
      |> get(
        "/api/json/device_runtime/devices?product=runtime-approved&account_number=12345&approval_status=approved&connectivity_status=online&ipv4_address=192.0.2.11"
      )

    assert %{
             "data" => [%{"mac_address" => "AA:BB:CC:DD:EE:02"}],
             "meta" => %{
               "active_filters" => %{
                 "product" => "runtime-approved",
                 "account_number" => "12345",
                 "approval_status" => "approved",
                 "connectivity_status" => "online",
                 "ipv4_address" => "192.0.2.11"
               }
             }
           } = json_response(conn, 200)
  end

  test "generated list omits blank and invalid active filters", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("x-token-user-roles", "nixstasis/viewer")
      |> get("/api/json/device_runtime/devices?product=%20&approval_status=unknown&ipv4_address=%20")

    assert %{"data" => data, "meta" => %{"active_filters" => %{}}} = json_response(conn, 200)
    assert length(data) == 2
  end

  test "generated list uses the operator permission boundary", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> get("/api/json/device_runtime/devices")

    assert %{"errors" => [%{"code" => "forbidden"}]} = json_response(conn, 403)
  end

  test "generated registration is public and returns pending devices without a token", %{conn: conn} do
    params = %{
      "data" => %{
        "mac_address" => "AA:BB:CC:DD:EE:03",
        "product_name" => "runtime-new",
        "schema_definition" => %{"product" => "runtime-new", "type" => "object", "properties" => %{}},
        "ipv4_address" => "192.0.2.12"
      }
    }

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/json/device_runtime/devices/register", params)

    body = json_response(conn, 201)

    assert %{
             "data" => %{
               "approval_status" => "pending",
               "mac_address" => "AA:BB:CC:DD:EE:03"
             }
           } = body

    refute body["data"]["api_token"]
  end

  test "generated registration rotates an approved device token", %{conn: conn, approved: approved, token: old_token} do
    params = %{
      "data" => %{
        "mac_address" => approved.mac_address,
        "product_name" => approved.product_name,
        "schema" => %{"product" => approved.product_name, "type" => "object", "properties" => %{}}
      }
    }

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/json/device_runtime/devices/register", params)

    body = json_response(conn, 201)
    new_token = body["data"]["api_token"]

    assert body["data"]["id"] == approved.id
    assert body["data"]["approval_status"] == "approved"
    assert is_binary(new_token) and new_token != ""
    assert new_token != old_token

    {:ok, updated} = Devices.get_device(approved.id)
    assert {:error, :invalid_token} = Devices.authenticate_device(updated, old_token)
    assert :ok = Devices.authenticate_device(updated, new_token)
  end

  test "generated heartbeat preserves telemetry, inventory, commands, probe, and remote access", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    {:ok, _} = Devices.queue_command(approved, %{"cmd" => "update"})

    {:ok, command} =
      Domain.create_command_catalog_command(%{
        name: "df",
        display_name: "Disk free",
        category_slugs: ["diagnostics"],
        active: true
      })

    {:ok, _mapping} =
      Domain.create_command_catalog_mapping(%{
        catalog_command_id: command.id,
        os_family: "debian",
        package_manager: "apt",
        package_name: "coreutils",
        command_path: "/usr/bin/df"
      })

    {:ok, approved} = Devices.set_remote_access(approved, true)
    future_observed_at = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

    payload = %{
      "data" => %{
        "telemetry" => %{"scripts" => %{"disk" => %{"usage_pct" => 73.2}}},
        "connection_status" => %{"connected" => true},
        "command_inventory" => %{
          "schema_version" => 1,
          "probe_catalog_version" => "catalog-v1",
          "observed_at" => future_observed_at,
          "architecture" => "x86_64",
          "package_manager" => "apt",
          "os_release" => %{"ID" => "ubuntu"},
          "packages" => %{"coreutils" => %{"installed" => true}},
          "commands" => %{"df" => %{"path" => "/usr/bin/df"}}
        }
      }
    }

    with_env("FRPS_AUTH_TOKEN", "shared-secret", fn ->
      conn =
        conn
        |> put_req_header("accept", "application/vnd.api+json")
        |> put_req_header("content-type", "application/vnd.api+json")
        |> post("/api/json/device_runtime/devices/#{approved.id}/heartbeat?api_key=#{token}", payload)

      assert %{
               "data" => %{
                 "commands" => [%{"command_id" => command_id, "payload" => %{"cmd" => "update"}}],
                 "command_inventory_probe" => probe,
                 "remote_access_token" => "shared-secret"
               }
             } = json_response(conn, 200)

      assert command_id
      assert probe["catalog_version"] == "catalog-v1"
      assert "coreutils" in probe["package_names"]
      assert Enum.any?(probe["command_probes"], &(&1["name"] == "df"))
    end)

    updated = Devices.get_device!(approved.id)
    refute is_nil(updated.last_seen_at)

    telemetry =
      Telemetry
      |> Ash.Query.filter(device_id == ^approved.id)
      |> Ash.read!(domain: Domain)

    assert [%{payload: telemetry_payload}] = telemetry
    assert telemetry_payload["scripts"]["disk"]["usage_pct"] == 73.2
    assert telemetry_payload["connection_status"]["connected"]
    refute Map.has_key?(telemetry_payload, "command_inventory")

    snapshots = Domain.list_device_command_inventory_snapshots() |> elem(1)
    assert [%{device_id: device_id}] = Enum.filter(snapshots, &(&1.device_id == approved.id))
    assert device_id == approved.id
  end

  test "generated heartbeat ignores malformed inventory while delivering commands", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    {:ok, _} = Devices.queue_command(approved, %{"cmd" => "update"})

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post(
        "/api/json/device_runtime/devices/#{approved.id}/heartbeat?api_key=#{token}",
        %{"data" => %{"command_inventory" => %{"schema_version" => "bad"}}}
      )

    assert %{"data" => %{"commands" => [%{"payload" => %{"cmd" => "update"}}]}} =
             json_response(conn, 200)

    snapshots = Domain.list_device_command_inventory_snapshots() |> elem(1)
    refute Enum.any?(snapshots, &(&1.device_id == approved.id))
  end

  test "generated heartbeat is limited at the heartbeat rate", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    previous = Application.get_env(:nixstasis, :rate_limit)
    Application.put_env(:nixstasis, :rate_limit, heartbeat_limit: 1)
    :ets.delete_all_objects(:nixstasis_rate_limiter)

    on_exit(fn ->
      if previous do
        Application.put_env(:nixstasis, :rate_limit, previous)
      else
        Application.delete_env(:nixstasis, :rate_limit)
      end
    end)

    request = fn conn ->
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/json/device_runtime/devices/#{approved.id}/heartbeat?api_key=#{token}", %{
        "data" => %{}
      })
    end

    assert response = request.(conn)
    assert response.status == 200
    assert %{"error" => %{"code" => "rate_limited"}} = json_response(request.(conn), 429)
  end

  test "generated command results preserves acknowledgement and replay behavior", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    {:ok, command} = Devices.queue_command(approved, %{"type" => "update"})

    payload = %{
      "data" => %{
        "results" => [
          %{
            "command_id" => command.id,
            "status" => "OK",
            "output" => %{"updated" => true}
          }
        ]
      }
    }

    request = fn conn ->
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/json/device_runtime/devices/#{approved.id}/command_results?api_key=#{token}", payload)
    end

    assert %{"data" => %{"acknowledged_count" => 1}} = json_response(request.(conn), 202)
    assert %{"data" => %{"acknowledged_count" => 1}} = json_response(request.(conn), 202)
  end

  test "generated command results preserves command policy delivery side effects", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    Phoenix.PubSub.subscribe(Nixstasis.PubSub, "command_policy_audit")

    {:ok, assignment} =
      Domain.create_command_policy_assignment(%{
        device_id: approved.id,
        revision: 1,
        version: "policy-generated",
        resolved_policy: %{"commands" => %{"df" => "/usr/bin/df"}}
      })

    {:ok, command} = Devices.queue_command_policy_assignment(assignment)

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post(
        "/api/json/device_runtime/devices/#{approved.id}/command_results?api_key=#{token}",
        %{
          "data" => %{
            "results" => [
              %{
                "command_id" => command.id,
                "status" => "OK",
                "output" => %{"commands_applied" => 1}
              }
            ]
          }
        }
      )

    assert %{"data" => %{"acknowledged_count" => 1}} = json_response(conn, 202)
    assert {:ok, assignment} = Domain.get_command_policy_assignment(assignment.id)
    assert assignment.status == :acknowledged
    assert_receive {:command_policy_audit, %{action: :assignment_acknowledged}}
  end

  test "generated command results rejects non-list bodies as JSON:API errors", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post(
        "/api/json/device_runtime/devices/#{approved.id}/command_results?api_key=#{token}",
        %{"data" => %{"results" => "not-a-list"}}
      )

    assert is_list(json_response(conn, 400)["errors"])
  end

  test "generated command results uses the device API-key boundary", %{
    conn: conn,
    pending: pending,
    approved: approved,
    token: token
  } do
    path = "/api/json/device_runtime/devices/#{approved.id}/command_results"

    conn = post(conn, path, %{"data" => %{"results" => []}})
    assert %{"errors" => [%{"code" => "missing_api_key"}]} = json_response(conn, 401)

    conn = post(build_conn(), "#{path}?api_key=wrong", %{"data" => %{"results" => []}})
    assert %{"errors" => [%{"code" => "invalid_api_key"}]} = json_response(conn, 401)

    conn =
      build_conn()
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("#{path}?api_key=#{token}", %{"data" => %{"results" => []}})

    assert json_response(conn, 202)["data"]["acknowledged_count"] == 0

    {:ok, other} =
      Devices.create_device(%{
        mac_address: "AA:BB:CC:DD:EE:04",
        product_name: "other-runtime",
        approval_status: :approved
      })

    {:ok, _other, other_token} = Devices.issue_device_token(other)

    conn =
      post(
        build_conn(),
        "#{path}?api_key=#{other_token}",
        %{"data" => %{"results" => []}}
      )

    assert %{"errors" => [%{"code" => "invalid_api_key"}]} = json_response(conn, 401)

    conn =
      post(
        build_conn(),
        "/api/json/device_runtime/devices/#{Ecto.UUID.generate()}/command_results?api_key=wrong",
        %{"data" => %{"results" => []}}
      )

    assert %{"errors" => [%{"code" => "device_not_found"}]} = json_response(conn, 404)

    conn =
      post(
        build_conn(),
        "/api/json/device_runtime/devices/#{pending.id}/command_results?api_key=anything",
        %{"data" => %{"results" => []}}
      )

    assert %{"errors" => [%{"code" => "device_not_approved"}]} = json_response(conn, 403)
  end

  test "generated command results preserves script ingestion side effects", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    {:ok, draft} =
      Scripts.create_draft(
        %{
          "operator_context" => %{"subject" => "test-operator"},
          "script_permissions" => %{"can_manage" => true}
        },
        %{
          name: "generated-result-script",
          front_matter: %{"name" => "generated-result-script", "schema" => %{"type" => "object"}},
          body: "def main():\\n    return {}\\n"
        }
      )

    {:ok, version} =
      Domain.create_script_version(%{
        script_draft_id: draft.id,
        version: "1",
        status: :validated,
        front_matter: draft.front_matter,
        body: draft.body,
        rendered_content: Scripts.render_draft(draft)
      })

    {:ok, run} =
      Scripts.queue_test_run(
        %{
          "operator_context" => %{"subject" => "test-operator"},
          "script_permissions" => %{"can_manage" => true}
        },
        draft,
        version,
        [approved]
      )

    %{id: command_id} =
      approved
      |> Devices.pop_pending_commands()
      |> Enum.find(&(&1.command_payload["type"] == "run_script"))

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post(
        "/api/json/device_runtime/devices/#{approved.id}/command_results?api_key=#{token}",
        %{
          "data" => %{
            "results" => [
              %{
                "command_id" => command_id,
                "status" => "OK",
                "output" => %{"status" => "passed", "validation" => "valid"}
              }
            ]
          }
        }
      )

    assert %{"data" => %{"acknowledged_count" => 1}} = json_response(conn, 202)
    completed = Domain.list_script_test_runs() |> elem(1) |> Enum.find(&(&1.id == run.id))
    assert completed.status == :passed
  end

  test "generated deferred payload returns the raw payload shape", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    {:ok, _command} =
      Devices.queue_command(approved, %{
        "type" => "install_script",
        "payload_ref" => "generated-payload",
        "payload" => %{
          "content_type" => "text/plain",
          "name" => "generated",
          "data" => "echo generated"
        }
      })

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> get("/api/json/device_runtime/devices/#{approved.id}/command_payloads/generated-payload?api_key=#{token}")

    assert %{
             "content_type" => "text/plain",
             "name" => "generated",
             "data" => "echo generated"
           } = json_response(conn, 200)
  end

  test "generated deferred payload returns 404 when the payload is missing", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> get("/api/json/device_runtime/devices/#{approved.id}/command_payloads/missing-payload?api_key=#{token}")

    assert is_list(json_response(conn, 404)["errors"])
  end

  test "generated deferred payload uses the device API-key boundary", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    path = "/api/json/device_runtime/devices/#{approved.id}/command_payloads/missing-payload"

    conn = get(conn, path)
    assert %{"errors" => [%{"code" => "missing_api_key"}]} = json_response(conn, 401)

    conn = get(build_conn(), "#{path}?api_key=wrong")
    assert %{"errors" => [%{"code" => "invalid_api_key"}]} = json_response(conn, 401)

    conn =
      build_conn()
      |> put_req_header("accept", "application/vnd.api+json")
      |> get("#{path}?api_key=#{token}")

    assert is_list(json_response(conn, 404)["errors"])
  end

  test "generated registration returns a JSON:API validation error for a missing schema", %{conn: conn} do
    params = %{"data" => %{"mac_address" => "AA:BB:CC:DD:EE:04"}}

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/json/device_runtime/devices/register", params)

    assert is_list(json_response(conn, 400)["errors"])
  end

  test "device runtime HTTP permission returns 404 before authentication for an unknown device", %{conn: conn} do
    conn = get(conn, "/api/json/device_runtime/devices/#{Ecto.UUID.generate()}/heartbeat?api_key=wrong")

    assert %{"errors" => [%{"code" => "device_not_found"}]} = json_response(conn, 404)
  end

  test "device runtime HTTP permission rejects missing keys", %{conn: conn, approved: approved} do
    conn = get(conn, "/api/json/device_runtime/devices/#{approved.id}/heartbeat")

    assert %{"errors" => [%{"code" => "missing_api_key"}]} = json_response(conn, 401)
  end

  test "device runtime HTTP permission rejects unapproved devices", %{conn: conn, pending: pending} do
    conn = get(conn, "/api/json/device_runtime/devices/#{pending.id}/heartbeat?api_key=anything")

    assert %{"errors" => [%{"code" => "device_not_approved"}]} = json_response(conn, 403)
  end

  test "device runtime permission sets the approved device as the Ash actor", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    conn = runtime_permission_conn(conn, approved.id, %{"api_key" => token})
    conn = JsonApiPermissions.call(conn, [])

    refute conn.halted
    assert Ash.PlugHelpers.get_actor(conn).id == approved.id
  end

  defp with_env(name, value, fun) do
    previous = System.get_env(name)
    System.put_env(name, value)

    try do
      fun.()
    after
      restore_env(name, previous)
    end
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp runtime_permission_conn(conn, device_id, query_params) do
    conn
    |> Map.put(:method, "POST")
    |> Map.put(:path_info, ["api", "json", "device_runtime", "devices", device_id, "heartbeat"])
    |> Map.put(:path_params, %{"device_id" => device_id})
    |> Map.put(:query_params, query_params)
  end
end
