defmodule Nixstasis.Devices.PendingCommand do
  @moduledoc """
  Resource for queued device commands awaiting delivery.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "pending_commands"
    repo Nixstasis.Repo

    references do
      reference :device, on_delete: :delete
    end

    custom_indexes do
      index [:device_id]
      index [:status]
    end
  end

  json_api do
    type "pending_command"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:command_payload, :status, :queued_at, :delivered_at, :device_id]
    end

    update :update do
      accept [:status, :delivered_at, :command_payload]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :command_payload, :map do
      allow_nil? false
      default %{}
    end

    attribute :status, Nixstasis.Types.PendingCommandStatus do
      allow_nil? false
      default :queued
    end

    attribute :queued_at, :utc_datetime do
      allow_nil? false
      default &DateTime.utc_now/0
    end

    attribute :delivered_at, :utc_datetime

    timestamps()
  end

  relationships do
    belongs_to :device, Nixstasis.Devices.Device do
      allow_nil? false
    end
  end
end
