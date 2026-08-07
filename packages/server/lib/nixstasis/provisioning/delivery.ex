defmodule Nixstasis.Provisioning.Delivery do
  @moduledoc """
  Durable record of one AtomixOS bootstrap artifact delivery attempt.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain

  postgres do
    table "provisioning_deliveries"
    repo Nixstasis.Repo

    references do
      reference :device, on_delete: :delete
    end

    custom_indexes do
      index [:device_id]
      index [:artifact_sha256]
      index [:state]
      index [:device_id, :artifact_sha256]
      index :attempt_id, unique: true, name: "provisioning_deliveries_unique_attempt_id_index"
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :device_id,
        :attempt_id,
        :artifact_sha256,
        :artifact_filename,
        :artifact_size,
        :state,
        :actor_id,
        :started_at
      ]
    end

    update :update do
      accept [
        :state,
        :job_id,
        :job_url,
        :job_state,
        :current_step,
        :job_payload,
        :result,
        :error,
        :rollback_status,
        :completed_at,
        :lease_withdrawn_at
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :attempt_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :artifact_sha256, :string do
      allow_nil? false
      public? true
    end

    attribute :artifact_filename, :string do
      allow_nil? false
      public? true
    end

    attribute :artifact_size, :integer do
      allow_nil? false
      public? true
    end

    attribute :state, Nixstasis.Types.ProvisioningDeliveryState do
      allow_nil? false
      default :submitting
      public? true
    end

    attribute :actor_id, :string do
      allow_nil? false
      public? true
    end

    attribute :job_id, :string do
      public? true
    end

    attribute :job_url, :string do
      public? true
    end

    attribute :job_state, :string do
      public? true
    end

    attribute :current_step, :string do
      public? true
    end

    attribute :job_payload, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :result, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :error, :string do
      public? true
    end

    attribute :rollback_status, :string do
      public? true
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    attribute :lease_withdrawn_at, :utc_datetime do
      public? true
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
