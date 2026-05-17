defmodule Nixstasis.Repo.Migrations.AddDeviceApiTokenHash do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :api_token_hash, :text
    end
  end
end
