defmodule Nixstasis.CommandAllowlists.DevicePolicyAssignment do
  @moduledoc """
  Per-device command policy assignment with a resolved policy snapshot.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "command_policy_assignments"
    repo Nixstasis.Repo

    references do
      reference :device, on_delete: :delete
    end

    custom_indexes do
      index [:device_id]
      index [:status]
      index [:revision]
    end
  end

  json_api do
    type "command_policy_assignment"
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :device_id,
        :status,
        :revision,
        :version,
        :resolved_policy,
        :source_snapshot,
        :drift_warning,
        :queued_at,
        :acknowledged_at,
        :failed_at,
        :revoked_at
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, Nixstasis.Types.CommandPolicyAssignmentStatus do
      allow_nil? false
      default :pending
      public? true
    end

    attribute :revision, :integer do
      allow_nil? false
      public? true
    end

    attribute :version, :string do
      allow_nil? false
      public? true
    end

    attribute :resolved_policy, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :source_snapshot, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :drift_warning, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :queued_at, :utc_datetime do
      public? true
    end

    attribute :acknowledged_at, :utc_datetime do
      public? true
    end

    attribute :failed_at, :utc_datetime do
      public? true
    end

    attribute :revoked_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :device, Nixstasis.Devices.Device do
      allow_nil? false
      public? true
      attribute_public? true
      attribute_writable? true
    end

    has_many :sources, Nixstasis.CommandAllowlists.DevicePolicyAssignmentSource do
      destination_attribute :assignment_id
    end

    has_many :delivery_results, Nixstasis.CommandAllowlists.PolicyDeliveryResult do
      destination_attribute :assignment_id
    end
  end
end
