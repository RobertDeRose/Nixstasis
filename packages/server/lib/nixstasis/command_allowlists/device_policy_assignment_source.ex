defmodule Nixstasis.CommandAllowlists.DevicePolicyAssignmentSource do
  @moduledoc """
  Version-pinned source selected for a device policy assignment.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "command_policy_assignment_sources"
    repo Nixstasis.Repo

    references do
      reference :assignment, on_delete: :delete
    end

    custom_indexes do
      index [:assignment_id]
      index [:source_kind]
      index [:source_id]
    end
  end

  json_api do
    type "command_policy_assignment_source"
  end

  actions do
    defaults [:read]

    create :create do
      accept [:assignment_id, :source_kind, :source_id, :source_version, :source_snapshot]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :source_kind, :string do
      allow_nil? false
      public? true
    end

    attribute :source_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :source_version, :integer do
      allow_nil? false
      public? true
    end

    attribute :source_snapshot, :map do
      allow_nil? false
      default %{}
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
  end
end
