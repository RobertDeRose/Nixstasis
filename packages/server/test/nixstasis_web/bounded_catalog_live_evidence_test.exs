defmodule NixstasisWeb.BoundedCatalogLiveEvidenceTest do
  use NixstasisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Nixstasis.Domain

  test "actual alert-rule LiveView records bounded rows and payload bytes", %{conn: conn} do
    for index <- 1..51 do
      {:ok, _rule} =
        Domain.create_rule(%{
          name: "Evidence live rule #{index}",
          product_name: "evidence-live-product",
          condition_field: "temp",
          operator: ">",
          threshold_value: Integer.to_string(index)
        })
    end

    handler_id = "bounded-alert-live-evidence-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:nixstasis, :repo, :query],
        fn _event, _measurements, _metadata, pid -> send(pid, {:alert_query, handler_id}) end,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    {:ok, _view, html} = live(conn, ~p"/alerts/rules")
    query_count = receive_query_events(handler_id, 0)

    assert query_count > 0
    assert query_count < 20
    assert length(Regex.scan(~r/Evidence live rule/, html)) == 50
    assert :erlang.external_size(html) < 1_000_000
  end

  defp receive_query_events(handler_id, count) do
    receive do
      {:alert_query, ^handler_id} -> receive_query_events(handler_id, count + 1)
    after
      20 -> count
    end
  end
end
