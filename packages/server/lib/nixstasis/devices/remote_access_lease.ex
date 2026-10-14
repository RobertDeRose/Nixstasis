defmodule Nixstasis.Devices.RemoteAccessLease do
  @moduledoc "Durable identity, ownership, and lifetime of one remote-access authorization."

  use Ash.Resource, data_layer: AshPostgres.DataLayer, domain: Nixstasis.Domain

  postgres do
    table "remote_access_leases"
    repo Nixstasis.Repo

    references do
      reference :device, on_delete: :delete
    end

    custom_indexes do
      index [:device_id, :inserted_at]
      index [:owner_kind, :owner_id], unique: true
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :owner_kind, :string do
      allow_nil? false
      constraints match: ~r/^(session|direct|provisioning)$/
    end

    attribute :owner_id, :uuid, allow_nil?: false
    attribute :audit_owner, :string

    attribute :profile, :string do
      allow_nil? false
      constraints match: ~r/^[a-z][a-z0-9._-]{0,63}$/
    end

    attribute :expires_at, :utc_datetime_usec, allow_nil?: false
    attribute :revoked_at, :utc_datetime_usec
    timestamps()
  end

  relationships do
    belongs_to :device, Nixstasis.Devices.Device, allow_nil?: false
  end
end
