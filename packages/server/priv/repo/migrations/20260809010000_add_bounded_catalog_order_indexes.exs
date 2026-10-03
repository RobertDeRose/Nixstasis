defmodule Nixstasis.Repo.Migrations.AddBoundedCatalogOrderIndexes do
  @moduledoc """
  Aligns indexes with bounded LiveView catalog picker and alert/report ordering.
  """

  use Ecto.Migration

  def up do
    create index(:devices, [:product_name, :mac_address, :id], name: :devices_picker_product_mac_id_index)

    create index(:alert_rules, [:product_name, :id], name: :alert_rules_catalog_product_id_index)

    execute(
      "CREATE INDEX custom_reports_lower_name_id_index ON custom_reports (lower(name), id)",
      "DROP INDEX IF EXISTS custom_reports_lower_name_id_index"
    )
  end

  def down do
    drop index(:alert_rules, [:product_name, :id], name: :alert_rules_catalog_product_id_index)

    drop index(:devices, [:product_name, :mac_address, :id], name: :devices_picker_product_mac_id_index)

    execute("DROP INDEX IF EXISTS custom_reports_lower_name_id_index")
  end
end
