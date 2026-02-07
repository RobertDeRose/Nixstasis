defmodule Nixstasis.Monitoring.Telemetry do
  @moduledoc """
  Resource for telemetry events reported by devices.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "telemetry_events"
    repo Nixstasis.Repo

    references do
      reference :device, on_delete: :delete
    end

    custom_indexes do
      index [:device_id]
      index [:timestamp]
      index [:payload], using: "gin"
    end
  end

  json_api do
    type "telemetry_event"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:device_id, :payload, :timestamp]
    end

    update :update do
      accept [:payload, :timestamp]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :timestamp, :utc_datetime do
      allow_nil? false
    end

    attribute :payload, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :device, Nixstasis.Devices.Device do
      allow_nil? false
    end
  end
end
