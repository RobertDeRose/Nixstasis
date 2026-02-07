defmodule Nixstasis.Monitoring.Alert do
  @moduledoc """
  Resource for alerts triggered by monitoring rules or offline checks.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "alerts"
    repo Nixstasis.Repo

    references do
      reference :device, on_delete: :delete
    end

    custom_indexes do
      index [:device_id]
      index [:status]
      index [:type]
      index [:triggered_at]
    end
  end

  json_api do
    type "alert"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:device_id, :rule_id, :type, :status, :message, :triggered_at]
    end

    update :update do
      accept [:status, :message]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :type, Nixstasis.Types.AlertType do
      allow_nil? false
    end

    attribute :status, Nixstasis.Types.AlertStatus do
      allow_nil? false
      default :active
    end

    attribute :message, :string do
      allow_nil? false
    end

    attribute :triggered_at, :utc_datetime do
      allow_nil? false
      default &DateTime.utc_now/0
    end

    attribute :rule_id, :integer

    timestamps()
  end

  relationships do
    belongs_to :device, Nixstasis.Devices.Device do
      allow_nil? false
    end
  end
end
