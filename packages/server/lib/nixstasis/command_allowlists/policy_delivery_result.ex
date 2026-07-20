defmodule Nixstasis.CommandAllowlists.PolicyDeliveryResult do
  @moduledoc """
  Immutable record of command policy delivery/client response history.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "command_policy_delivery_results"
    repo Nixstasis.Repo

    references do
      reference :assignment, on_delete: :delete
      reference :pending_command, on_delete: :nilify
    end

    custom_indexes do
      index [:assignment_id]
      index [:pending_command_id]
      index [:status]
      index [:reported_at]
    end
  end

  json_api do
    type "command_policy_delivery_result"
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :assignment_id,
        :pending_command_id,
        :status,
        :command_ref,
        :client_payload,
        :failure_reason,
        :reported_at
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, Nixstasis.Types.CommandPolicyDeliveryStatus do
      allow_nil? false
      public? true
    end

    attribute :command_ref, :string do
      public? true
    end

    attribute :client_payload, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :failure_reason, :string do
      public? true
    end

    attribute :reported_at, :utc_datetime do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :assignment, Nixstasis.CommandAllowlists.DevicePolicyAssignment do
      allow_nil? false
      public? true
      attribute_public? true
      attribute_writable? true
    end

    belongs_to :pending_command, Nixstasis.Devices.PendingCommand do
      public? true
      attribute_public? true
      attribute_writable? true
    end
  end
end
