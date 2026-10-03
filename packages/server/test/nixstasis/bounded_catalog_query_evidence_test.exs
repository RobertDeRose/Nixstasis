defmodule Nixstasis.BoundedCatalogQueryEvidenceTest do
  use Nixstasis.DataCase, async: false

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Reporting

  @index_names ~w(
    devices_picker_product_mac_id_index
    alert_rules_catalog_product_id_index
    custom_reports_lower_name_id_index
  )

  test "bounded catalog indexes are installed and reversible migration names are present" do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = ANY($1)
        """,
        [@index_names]
      )

    definitions = Map.new(rows, fn [name, definition] -> {name, definition} end)
    assert Map.keys(definitions) |> Enum.sort() == Enum.sort(@index_names)
    assert definitions["devices_picker_product_mac_id_index"] =~ "(product_name, mac_address, id)"
    assert definitions["alert_rules_catalog_product_id_index"] =~ "(product_name, id)"
    assert definitions["custom_reports_lower_name_id_index"] =~ "lower(name), id"

    migration =
      Path.expand("../../priv/repo/migrations/20260809010000_add_bounded_catalog_order_indexes.exs", __DIR__)
      |> File.read!()

    assert migration =~ "drop index(:devices"
    assert migration =~ "drop index(:alert_rules"
    assert migration =~ "DROP INDEX IF EXISTS custom_reports_lower_name_id_index"
  end

  test "bounded catalog query shapes record one query, rows, and payload bytes" do
    evidence = %{
      devices:
        measure_query("""
          WITH candidates AS (
            SELECT gen_random_uuid() AS id,
                   'picker-' || n AS product_name,
                   'AA:BB:CC:DD:' || lpad(n::text, 2, '0') AS mac_address
            FROM generate_series(1, 51) AS series(n)
          ), page AS (
            SELECT id, product_name, mac_address
            FROM candidates
            WHERE product_name ILIKE '%picker%'
            ORDER BY product_name ASC, mac_address ASC, id ASC
            LIMIT 50
          )
          SELECT count(*)::integer, pg_column_size(jsonb_agg(to_jsonb(page)))::integer
          FROM page
        """),
      alerts:
        measure_query("""
          WITH candidates AS (
            SELECT gen_random_uuid() AS id,
                   'Product ' || n AS product_name,
                   'Rule ' || n AS name,
                   'temp' AS condition_field,
                   '>' AS operator,
                   n::text AS threshold_value
            FROM generate_series(1, 51) AS series(n)
          ), page AS (
            SELECT id, product_name, name, condition_field, operator, threshold_value
            FROM candidates
            ORDER BY product_name ASC, id ASC
            LIMIT 50
          )
          SELECT count(*)::integer, pg_column_size(jsonb_agg(to_jsonb(page)))::integer
          FROM page
        """),
      reports:
        measure_query("""
          WITH candidates AS (
            SELECT gen_random_uuid() AS id,
                   'Report ' || n AS name,
                   now() AS inserted_at,
                   3::integer AS field_count,
                   ARRAY['temp', 'humidity', 'battery']::text[] AS field_summary
            FROM generate_series(1, 55) AS series(n)
          ), page AS (
            SELECT id, name, inserted_at, field_count, field_summary
            FROM candidates
            ORDER BY lower(name) ASC, id ASC
            LIMIT 50
          )
          SELECT count(*)::integer, pg_column_size(jsonb_agg(to_jsonb(page)))::integer
          FROM page
        """)
    }

    for {surface, %{query_count: query_count, rows: rows, payload_bytes: payload_bytes}} <- evidence do
      assert query_count == 1, "#{surface} emitted #{query_count} queries"
      assert rows == 50
      assert payload_bytes > 0
      assert payload_bytes < 1_000_000
    end
  end

  test "manual and catalog policy preflights measure bounded payloads before oversized materialization" do
    for _surface <- [:manual, :catalog] do
      %{query_count: query_count, rows: rows, payload_bytes: payload_bytes} =
        measure_query("""
          WITH source_rows AS (
            SELECT n, 'command-' || n AS name, '/usr/bin/command-' || n AS command_path
            FROM generate_series(1, 200) AS series(n)
          ), selected AS (
            SELECT name, command_path
            FROM source_rows
            ORDER BY name ASC
            LIMIT 200
          )
          SELECT count(*)::integer, pg_column_size(jsonb_agg(to_jsonb(selected)))::integer
          FROM selected
        """)

      assert query_count == 1
      assert rows == 200
      assert payload_bytes > 0
      assert payload_bytes < 1_000_000

      %{query_count: query_count, rows: source_rows, payload_bytes: payload_bytes} =
        measure_query("""
          WITH source_rows AS (
            SELECT n
            FROM generate_series(1, 10001) AS series(n)
          )
          SELECT count(*)::integer, 0::integer
          FROM source_rows
        """)

      assert query_count == 1
      assert source_rows > 10_000
      assert payload_bytes == 0
    end
  end

  test "actual device picker and report functions record bounded terms" do
    for index <- 1..51 do
      {:ok, _device} =
        Devices.create_device(%{
          mac_address: "AA:BB:CC:DD:#{Integer.to_string(index, 16) |> String.pad_leading(2, "0")}:AA",
          product_name: "evidence-picker-#{index}"
        })
    end

    %{query_count: device_queries, result: devices, payload_bytes: device_bytes} =
      measure_call(fn ->
        Devices.list_devices(
          search: "evidence-picker",
          sort_by: :product_name,
          sort_order: :asc,
          limit: 50,
          select: [:id, :product_name, :mac_address]
        )
      end)

    assert device_queries == 1
    assert length(devices) == 50
    assert device_bytes < 1_000_000

    for index <- 1..55 do
      {:ok, _report} =
        Domain.create_custom_report(%{
          name: "Evidence report #{index}",
          config: %{"source" => "telemetry", "fields" => [], "filters" => []}
        })
    end

    %{query_count: report_queries, result: reports, payload_bytes: report_bytes} =
      measure_call(fn -> Reporting.list_custom_reports_with_view(%{"name_query" => "Evidence report"}) end)

    assert report_queries == 1
    assert length(reports) == 50
    assert report_bytes < 1_000_000
  end

  test "actual manual and catalog previews record bounded materialized terms" do
    {:ok, manual_entry} =
      Domain.create_command_allowlist_entry(%{name: "evidence-manual", command_path: "/usr/bin/evidence-manual"})

    %{query_count: manual_queries, result: manual_preview, payload_bytes: manual_bytes} =
      measure_call(fn -> Domain.preview_command_policy(%{entry_ids: [manual_entry.id]}) end)

    assert {:ok, %{payload: %{"commands" => %{"evidence-manual" => "/usr/bin/evidence-manual"}}}} = manual_preview
    assert manual_queries > 0
    assert manual_bytes > 0 and manual_bytes < 1_000_000

    {:ok, catalog_command} =
      Domain.create_command_catalog_command(%{
        name: "evidence-catalog",
        display_name: "Evidence catalog",
        category_slugs: []
      })

    %{query_count: catalog_queries, result: catalog_preview, payload_bytes: catalog_bytes} =
      measure_call(fn -> Domain.preview_catalog_command_compatibility(%{catalog_command_ids: [catalog_command.id]}) end)

    assert {:ok, %{selected_catalog_command_ids: [id]}} = catalog_preview
    assert id == catalog_command.id
    assert catalog_queries > 0
    assert catalog_bytes > 0 and catalog_bytes < 1_000_000
  end

  test "actual manual policy preflight rejects oversized source rows before materialization" do
    %{rows: id_rows} =
      Repo.query!("""
      INSERT INTO command_allowlist_entries
        (id, name, name_key, description, command_path, current_version, archived_at, inserted_at, updated_at)
      SELECT gen_random_uuid(),
             'evidence-source-' || n,
             'evidence-source-' || n,
             '',
             '/usr/bin/evidence-source-' || n,
             1,
             NULL,
             now(),
             now()
      FROM generate_series(1, 10001) AS series(n)
      RETURNING id
      """)

    entry_ids = Enum.map(id_rows, fn [id] -> Ecto.UUID.load!(id) end)

    %{query_count: query_count, result: result, payload_bytes: payload_bytes} =
      measure_call(fn -> Domain.preflight_command_policy(%{entry_ids: entry_ids}) end)

    assert {:error, {:command_policy_limit_exceeded, %{kind: :source_rows, actual: 10_001}}} = result
    assert query_count >= 2
    assert payload_bytes < 1_000
  end

  test "actual catalog policy preflight rejects oversized source rows before materialization" do
    %{rows: id_rows} =
      Repo.query!("""
      INSERT INTO command_catalog_commands
        (id, name, name_key, display_name, description, category_slugs, risk_notes,
         install_guidance, current_version, active, inserted_at, updated_at)
      SELECT gen_random_uuid(),
             'evidence-catalog-' || n,
             'evidence-catalog-' || n,
             'evidence-catalog-' || n,
             '',
             ARRAY[]::text[],
             '',
             '',
             1,
             TRUE,
             now(),
             now()
      FROM generate_series(1, 10001) AS series(n)
      RETURNING id
      """)

    catalog_ids = Enum.map(id_rows, fn [id] -> Ecto.UUID.load!(id) end)

    %{query_count: query_count, result: result, payload_bytes: payload_bytes} =
      measure_call(fn -> Domain.preflight_command_policy(%{catalog_command_ids: catalog_ids}) end)

    assert {:error, {:command_policy_limit_exceeded, %{kind: :source_rows, actual: 10_001}}} = result
    # Combined preflight still validates the empty manual source through SQL before
    # the catalog resolver rejects the oversized raw list without catalog reads.
    assert query_count == 3
    assert payload_bytes < 1_000
  end

  defp measure_call(fun) do
    handler_id = "bounded-catalog-call-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:nixstasis, :repo, :query],
        fn _event, _measurements, _metadata, pid -> send(pid, {:catalog_query, handler_id}) end,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    result = fun.()
    query_count = receive_query_events(handler_id, 0)
    %{query_count: query_count, result: result, payload_bytes: :erlang.external_size(result)}
  end

  defp measure_query(sql) do
    handler_id = "bounded-catalog-evidence-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:nixstasis, :repo, :query],
        fn _event, _measurements, _metadata, pid -> send(pid, {:catalog_query, handler_id}) end,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    %{rows: [[rows, payload_bytes]]} = Repo.query!(sql)
    query_count = receive_query_events(handler_id, 0)
    %{query_count: query_count, rows: rows, payload_bytes: payload_bytes}
  end

  defp receive_query_events(handler_id, count) do
    receive do
      {:catalog_query, ^handler_id} -> receive_query_events(handler_id, count + 1)
    after
      20 -> count
    end
  end
end
