defmodule Nixstasis.Repo.Migrations.AddFieldsToDevices do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:ipv4_address, :string)
      add(:account_number, :string)
      add(:remote_access_requested, :boolean, default: false, null: false)
    end

    create(index(:devices, [:ipv4_address]))
    create(index(:devices, [:account_number]))
  end
end
