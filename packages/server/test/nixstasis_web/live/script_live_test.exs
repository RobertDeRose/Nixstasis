defmodule NixstasisWeb.ScriptLiveTest do
  use NixstasisWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Nixstasis.Devices
  alias Nixstasis.Domain

  @endpoint NixstasisWeb.Endpoint

  setup %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> put_session("script_permissions", %{"can_view" => true, "can_manage" => true})

    {:ok, draft} =
      Domain.create_script_draft(%{
        name: "test-script",
        front_matter: %{"name" => "test-script", "schema" => %{"type" => "object"}, "version" => "1.0"},
        body: "def main():\n    return {\"ok\": true}\n"
      })

    {:ok, conn: conn, draft: draft}
  end

  defp open_front_matter_section(view) do
    if not String.contains?(render(view), ~s(id="front-matter-section" open)) do
      render_click(element(view, "summary", "Front Matter"))
    end
  end

  defp open_schema_tab(view) do
    open_front_matter_section(view)
    render_click(element(view, "input[phx-value-tab='schema']"))
  end

  defp open_front_matter_preview(view) do
    open_front_matter_section(view)
    render_click(element(view, "input[phx-value-tab='preview']"))
  end

  describe "Script Index" do
    test "lists scripts", %{conn: conn, draft: draft} do
      {:ok, _view, html} = live(conn, ~p"/scripts")
      assert html =~ draft.name
    end

    test "redirects without script view permission", %{conn: conn} do
      conn = put_session(conn, "script_permissions", %{"can_view" => false, "can_manage" => false})

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/scripts")
    end

    test "shows empty state when no scripts", %{conn: conn} do
      # Delete all drafts
      Domain.list_script_drafts() |> elem(1) |> Enum.each(&Domain.destroy_script_draft/1)

      {:ok, _view, html} = live(conn, ~p"/scripts")
      assert html =~ "No scripts yet"
    end
  end

  describe "Script Show" do
    test "displays script detail", %{conn: conn, draft: draft} do
      {:ok, _view, html} = live(conn, ~p"/scripts/#{draft.id}")
      assert html =~ draft.name
      assert html =~ "Editor"
      assert html =~ "Validate"
      assert html =~ "Test"
      assert html =~ ~s(phx-value-tab="deploy")
      assert html =~ "Validate and pass a test before deploying"
      assert html =~ "disabled"
    end

    test "enables deploy tab after version validation and passed test", %{conn: conn, draft: draft} do
      {:ok, version} =
        Domain.create_script_version(%{
          script_draft_id: draft.id,
          version: "1.0",
          status: :validated,
          front_matter: draft.front_matter,
          body: draft.body,
          rendered_content: "---\nname: test-script\n---\ndef main():\n    return {}"
        })

      {:ok, _run} =
        Domain.create_script_test_run(%{
          script_draft_id: draft.id,
          script_version_id: version.id,
          status: :passed,
          started_at: DateTime.utc_now(),
          completed_at: DateTime.utc_now(),
          target_device_ids: [],
          command_payload: %{},
          notes: %{}
        })

      {:ok, _view, html} = live(conn, ~p"/scripts/#{draft.id}")
      assert html =~ ~s(phx-value-tab="deploy")
      refute html =~ "Validate and pass a test before deploying"
    end

    test "redirects script detail without script view permission", %{conn: conn, draft: draft} do
      conn = put_session(conn, "script_permissions", %{"can_view" => false, "can_manage" => false})

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/scripts/#{draft.id}")
    end

    test "escapes schema field names", %{conn: conn} do
      {:ok, draft} =
        Domain.create_script_draft(%{
          name: "unsafe-schema",
          front_matter: %{
            "name" => "unsafe-schema",
            "schema" => %{
              "type" => "object",
              "properties" => %{
                "\" autofocus onfocus=alert(1) x=\"" => %{"type" => "string"}
              }
            },
            "version" => "1.0"
          },
          body: "def main():\n    return {}\n"
        })

      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")
      html = open_front_matter_preview(view)

      assert html =~ "&quot; autofocus onfocus=alert(1) x=&quot;"
      refute html =~ "value=\"\" autofocus onfocus=alert(1)"
    end

    test "can switch tabs", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")

      render_click(element(view, "button[phx-value-tab='validate']"))
      assert render(view) =~ "Validate script"

      render_click(element(view, "button[phx-value-tab='test']"))
      assert render(view) =~ "Test on selected devices"

      render_click(element(view, "button[phx-value-tab='history']"))
      assert render(view) =~ "Versions"
    end

    test "keeps front matter expanded across schema edits", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")

      open_schema_tab(view)
      html = render_click(element(view, "#schema-add-field"))

      assert html =~ ~s(id="front-matter-section" open)
    end

    test "type enter requires a field name before adding a row", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")

      open_schema_tab(view)
      html = render_click(element(view, "#schema-add-field"))
      [root_id] = List.last(Regex.scan(~r/id="sf-name-([^"]+)"/, html, capture: :all_but_first))

      html =
        render_hook(view, "schema_field_type_keydown", %{
          "id" => root_id,
          "key" => "Enter",
          "level" => "0",
          "value" => "object"
        })

      assert html =~ "Required"
      refute html =~ ~s(data-field-level="1")
    end

    test "creates nested schema children from object type enter", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")

      open_schema_tab(view)
      html = render_click(element(view, "#schema-add-field"))
      [root_id] = List.last(Regex.scan(~r/id="sf-name-([^"]+)"/, html, capture: :all_but_first))

      render_hook(view, "update_schema_field", %{
        "_target" => ["schema_fields", root_id, "name"],
        "schema_fields" => %{root_id => %{"name" => "root"}}
      })

      html =
        render_hook(view, "schema_field_type_keydown", %{
          "id" => root_id,
          "key" => "Enter",
          "level" => "0",
          "value" => "object"
        })

      assert html =~ ~s(data-field-level="1")
      assert html =~ "+ Add Child Field"

      [child_id] =
        List.last(Regex.scan(~r/data-field-level="1".*?id="sf-name-([^"]+)"/s, html, capture: :all_but_first))

      render_hook(view, "update_schema_field", %{
        "_target" => ["schema_fields", "#{root_id},#{child_id}", "name"],
        "schema_fields" => %{"#{root_id},#{child_id}" => %{"name" => "child"}}
      })

      html =
        render_hook(view, "schema_field_type_keydown", %{
          "id" => child_id,
          "key" => "Enter",
          "level" => "1",
          "value" => "object"
        })

      assert html =~ ~s(data-field-level="2")
    end

    test "shows only devices in the trusted operator scope", %{conn: conn, draft: draft} do
      {:ok, visible} =
        Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:FA", product_name: "scoped-visible"})

      {:ok, visible} = Devices.approve_device(visible)

      {:ok, hidden} =
        Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:FB", product_name: "scoped-hidden"})

      {:ok, _hidden} = Devices.approve_device(hidden)

      conn =
        put_session(conn, "device_permissions", %{
          "can_manage" => true,
          "device_ids" => [visible.id]
        })

      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")
      html = render_click(element(view, "button[phx-value-tab='test']"))

      assert html =~ "scoped-visible"
      refute html =~ "scoped-hidden"
    end

    test "rejects the 251st picker selection visibly", %{conn: conn, draft: draft} do
      devices =
        for index <- 1..251 do
          group = div(index - 1, 50) + 1
          suffix = Integer.to_string(index, 16) |> String.pad_leading(4, "0")

          mac_suffix = suffix |> String.graphemes() |> Enum.chunk_every(2) |> Enum.map_join(":", &Enum.join/1)

          {:ok, device} =
            Devices.register_device(%{
              mac_address: "AA:BB:CC:DD:#{mac_suffix}",
              product_name: "cap-group-#{group}"
            })

          device
        end

      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")
      render_click(element(view, "button[phx-value-tab='test']"))

      for group <- 1..5 do
        ids = devices |> Enum.drop((group - 1) * 50) |> Enum.take(50) |> Enum.map(& &1.id)
        render_change(element(view, "#script-device-search"), %{"search" => "cap-group-#{group}"})

        for id <- ids do
          render_click(element(view, "input[phx-value-device_id='#{id}']"))
        end
      end

      render_change(element(view, "#script-device-search"), %{"search" => "cap-group-6"})
      html = render_click(element(view, "input[phx-value-device_id='#{Enum.at(devices, 250).id}']"))

      assert html =~ "You can select at most 250 devices"
      assert html =~ "Selected: 250 of 250"
    end

    test "rejects forged or malformed device selections", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")
      render_click(element(view, "button[phx-value-tab='test']"))

      assert render_click(view, "toggle_device", %{"device_id" => "not-a-uuid"}) =~
               "Invalid device selection"

      assert render_click(view, "toggle_device", %{"device_id" => Ecto.UUID.generate()}) =~
               "Device is not in the current search results"
    end

    test "limits the picker to 50 SQL results", %{conn: conn, draft: draft} do
      for index <- 1..51 do
        suffix = Integer.to_string(index, 16) |> String.pad_leading(2, "0")

        {:ok, device} =
          Devices.register_device(%{
            mac_address: "AA:BB:CC:DD:#{suffix}:#{suffix}",
            product_name: "picker-bound-#{index}"
          })

        {:ok, _device} = Devices.approve_device(device)
      end

      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")
      html = render_click(element(view, "button[phx-value-tab='test']"))

      assert length(Regex.scan(~r/phx-value-device_id=/, html)) == 50
    end

    test "searches devices in SQL and preserves selected labels across searches", %{conn: conn, draft: draft} do
      {:ok, visible} =
        Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:FC", product_name: "picker-visible"})

      {:ok, visible} = Devices.approve_device(visible)

      {:ok, hidden} =
        Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:FD", product_name: "picker-hidden"})

      {:ok, _hidden} = Devices.approve_device(hidden)

      conn = put_session(conn, "device_permissions", %{"can_manage" => true, "device_ids" => [visible.id]})
      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")
      render_click(element(view, "button[phx-value-tab='test']"))

      assert has_element?(view, "#script-device-search-input[phx-debounce='300']")
      assert has_element?(view, "input[phx-value-device_id='#{visible.id}']")
      refute has_element?(view, "input[phx-value-device_id='#{hidden.id}']")

      render_click(element(view, "input[phx-value-device_id='#{visible.id}']"))
      html = render_change(element(view, "#script-device-search"), %{"search" => "picker"})

      assert html =~ "picker-visible"
      assert has_element?(view, "input[phx-value-device_id='#{visible.id}']")
      assert html =~ "Selected: 1 of 250"

      html = render_change(element(view, "#script-device-search"), %{"search" => "does-not-exist"})
      assert html =~ "No matching devices found."
      refute has_element?(view, "input[phx-value-device_id='#{visible.id}']")
    end

    test "can validate then queue a test without reloading", %{conn: conn, draft: draft} do
      {:ok, device} = Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:FA", product_name: "live-target"})
      {:ok, device} = Devices.approve_device(device)

      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")

      render_click(element(view, "button[phx-value-tab='validate']"))
      render_click(element(view, "button", "Validate script"))
      render_click(element(view, "button[phx-value-tab='test']"))
      render_click(element(view, "input[phx-value-device_id='#{device.id}']"))
      html = render_click(element(view, "button", "Test on selected devices"))

      assert html =~ "Test queued for 1 device"
      refute html =~ "No script version available"
    end

    test "redirects for non-existent script", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/scripts"}}} = live(conn, ~p"/scripts/non-existent-id")
    end
  end
end
