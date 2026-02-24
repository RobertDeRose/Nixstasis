defmodule NixstasisWeb.LiveViewTestHelpers do
  @moduledoc false

  def alert_new_path, do: "/alerts/new"
  def alert_edit_path(rule_id), do: "/alerts/#{rule_id}/edit"

  def device_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        mac_address: "AA:BB:CC:DD:EE:FF",
        account_number: "123456789",
        approval_status: :approved,
        product_name: "PROD-123",
        last_seen_at: DateTime.utc_now()
      },
      overrides
    )
  end
end
