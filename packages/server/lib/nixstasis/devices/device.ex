defmodule Nixstasis.Devices.Device do
  @moduledoc """
  The Device resource.

  This resource represents a device in the Nixstasis system, capturing essential
  attributes such as MAC address, product name, approval status, and metadata.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "devices"
    repo Nixstasis.Repo

    custom_indexes do
      index [:account_number]
      index [:ipv4_address]
      index [:product_name]
      index [:approval_status]
      index [:schema], using: "gin"
      index [:metadata], using: "gin"
    end
  end

  json_api do
    type "device"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :mac_address,
        :product_name,
        :account_number,
        :ipv4_address,
        :approval_status,
        :last_seen_at,
        :schema,
        :metadata,
        :remote_access_requested
      ]

      change {Nixstasis.Devices.Changes.FormatMacAddress, []}
      validate {Nixstasis.Devices.Validations.SchemaDefinition, []}
    end

    create :register do
      accept [
        :mac_address,
        :product_name,
        :account_number,
        :ipv4_address,
        :last_seen_at,
        :schema,
        :metadata,
        :remote_access_requested
      ]

      change {Nixstasis.Devices.Changes.FormatMacAddress, []}
      validate {Nixstasis.Devices.Validations.SchemaDefinition, []}

      upsert? true
      upsert_identity :unique_mac_address
      upsert_fields {:replace_all_except, [:approval_status, :api_token_hash]}
    end

    update :update do
      require_atomic? false

      accept [
        :mac_address,
        :product_name,
        :account_number,
        :ipv4_address,
        :approval_status,
        :last_seen_at,
        :schema,
        :metadata,
        :remote_access_requested
      ]

      change {Nixstasis.Devices.Changes.FormatMacAddress, []}
      validate {Nixstasis.Devices.Validations.SchemaDefinition, []}
      validate {Nixstasis.Devices.Validations.ApprovalTransition, []}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :mac_address, :string do
      allow_nil? false
      constraints match: ~r/^([0-9A-F]{2}[:-]?){5}[0-9A-F]{2}$/i
    end

    attribute :product_name, :string

    attribute :account_number, :string do
      constraints min_length: 5, match: ~r/^\d+$/
    end

    attribute :ipv4_address, :string do
      constraints match: ~r/^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/
    end

    attribute :approval_status, Nixstasis.Types.ApprovalStatus do
      allow_nil? false
      default :pending
    end

    attribute :api_token_hash, :string

    attribute :last_seen_at, :utc_datetime

    attribute :schema, :map do
      allow_nil? false
      default %{}
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    attribute :remote_access_requested, :boolean do
      allow_nil? false
      default false
    end

    timestamps()
  end

  relationships do
    has_many :pending_commands, Nixstasis.Devices.PendingCommand
    has_many :telemetry_events, Nixstasis.Monitoring.Telemetry
    has_many :alerts, Nixstasis.Monitoring.Alert
  end

  identities do
    identity :unique_mac_address, [:mac_address]
  end

  @doc """
  Normalizes a filter input value.
  Returns trimmed binary values and `nil` for empty/non-binary inputs.
  """
  def normalize_filter_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_filter_value(_), do: nil
end
