defmodule Nixstasis.Monitoring.Telemetry do
  @moduledoc """
  Resource for telemetry events reported by devices.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    authorizers: [Ash.Policy.Authorizer],
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

  policies do
    bypass actor_absent() do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(
                     ^actor(:can_view_device_data) == true and
                       (^actor(:unscoped_device_access) == true or device_id in ^actor(:authorized_device_ids))
                   )
    end

    policy always() do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :timestamp, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :payload, :map do
      allow_nil? false
      public? true
      default %{}
    end

    timestamps()
  end

  relationships do
    belongs_to :device, Nixstasis.Devices.Device do
      allow_nil? false
      public? true
    end
  end
end
