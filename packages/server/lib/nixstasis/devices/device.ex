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

  alias Nixstasis.Devices
  alias Nixstasis.Monitoring

  @runtime_device_fields [
    id: [type: :uuid, allow_nil?: false],
    mac_address: [type: :string, allow_nil?: false],
    product_name: [type: :string],
    account_number: [type: :string],
    approval_status: [type: Nixstasis.Types.ApprovalStatus, allow_nil?: false],
    last_seen_at: [type: :utc_datetime],
    schema: [type: :map, allow_nil?: false],
    metadata: [type: :map, allow_nil?: false],
    remote_access_requested: [type: :boolean, allow_nil?: false],
    api_token: [type: :string]
  ]

  @runtime_list_device_fields [
    id: [type: :uuid, allow_nil?: false],
    mac_address: [type: :string, allow_nil?: false],
    product_name: [type: :string],
    account_number: [type: :string],
    approval_status: [type: Nixstasis.Types.ApprovalStatus, allow_nil?: false],
    last_seen_at: [type: :utc_datetime],
    schema: [type: :map, allow_nil?: false],
    metadata: [type: :map, allow_nil?: false]
  ]

  @runtime_response_fields [
    data: [type: :map, allow_nil?: false, constraints: [fields: @runtime_device_fields]]
  ]

  @runtime_list_response_fields [
    data: [type: {:array, :map}, allow_nil?: false, constraints: [items: [fields: @runtime_list_device_fields]]],
    meta: [type: :map, allow_nil?: false]
  ]

  @heartbeat_command_fields [
    command_id: [type: :string, allow_nil?: false],
    type: [type: :string, allow_nil?: false],
    args: [type: {:array, :string}, allow_nil?: false],
    payload: [type: :map],
    public_key: [type: :string],
    payload_ref: [type: :string],
    queued_at: [type: :utc_datetime, allow_nil?: false]
  ]

  @heartbeat_probe_fields [
    catalog_version: [type: :string, allow_nil?: false],
    package_names: [type: {:array, :string}, allow_nil?: false],
    command_probes: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [
        items: [
          fields: [
            name: [type: :string, allow_nil?: false],
            os_family: [type: :string],
            package_name: [type: :string],
            command_path: [type: :string, allow_nil?: false]
          ]
        ]
      ]
    ]
  ]

  @heartbeat_data_fields [
    commands: [
      type: {:array, :map},
      allow_nil?: false,
      constraints: [items: [fields: @heartbeat_command_fields]]
    ],
    remote_access_token: [type: :string],
    command_inventory_probe: [type: :map, constraints: [fields: @heartbeat_probe_fields]]
  ]

  @heartbeat_response_fields [
    data: [type: :map, allow_nil?: false, constraints: [fields: @heartbeat_data_fields]]
  ]

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
      upsert_fields {:replace_all_except, [:id, :approval_status, :api_token_hash]}
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

    action :list_runtime_devices, :map do
      constraints fields: @runtime_list_response_fields

      argument :product, :string
      argument :account_number, :string
      argument :approval_status, :string
      argument :connectivity_status, :string
      argument :ipv4_address, :string

      run fn input, _context ->
        {:ok, Devices.runtime_list(input.arguments)}
      end
    end

    action :register_runtime_device, :map do
      constraints fields: @runtime_response_fields

      argument :mac_address, :string, allow_nil?: false
      argument :product_name, :string
      argument :account_number, :string
      argument :ipv4_address, :string
      argument :schema_definition, :map
      argument :schema, :map
      argument :metadata, :map
      argument :remote_access_requested, :boolean

      run fn input, _context ->
        Devices.register_runtime_device(input.arguments)
      end
    end

    action :heartbeat, :map do
      constraints fields: @heartbeat_response_fields

      argument :device_id, :uuid, allow_nil?: false
      argument :telemetry, :map, default: %{}
      argument :connection_status, :map, default: %{}
      argument :command_inventory, :map

      run fn input, _context ->
        case Devices.get_device(input.arguments.device_id) do
          {:ok, device} when is_map(device) ->
            case Monitoring.heartbeat(device, heartbeat_payload(input.arguments)) do
              {:ok, updated_device, commands} ->
                {:ok, %{data: Monitoring.heartbeat_response_data(updated_device, commands)}}

              {:error, _reason} ->
                {:error, "heartbeat processing failed"}
            end

          {:ok, nil} ->
            {:error, "device not found"}

          {:error, _reason} ->
            {:error, "device not found"}
        end
      end
    end
  end

  defp heartbeat_payload(arguments) do
    Map.take(arguments, [:telemetry, :connection_status, :command_inventory])
  end

  attributes do
    uuid_primary_key :id

    attribute :mac_address, :string do
      allow_nil? false
      constraints match: ~r/^([0-9A-F]{2}[:-]?){5}[0-9A-F]{2}$/i
      public? true
    end

    attribute :product_name, :string do
      public? true
    end

    attribute :account_number, :string do
      constraints min_length: 5, match: ~r/^\d+$/
      public? true
    end

    attribute :ipv4_address, :string do
      constraints match: ~r/^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/
      public? true
    end

    attribute :approval_status, Nixstasis.Types.ApprovalStatus do
      allow_nil? false
      default :pending
      public? true
    end

    attribute :api_token_hash, :string

    attribute :last_seen_at, :utc_datetime do
      public? true
    end

    attribute :schema, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :remote_access_requested, :boolean do
      allow_nil? false
      default false
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :pending_commands, Nixstasis.Devices.PendingCommand do
      public? true
    end

    has_many :telemetry_events, Nixstasis.Monitoring.Telemetry do
      public? true
    end

    has_many :alerts, Nixstasis.Monitoring.Alert do
      public? true
    end

    has_many :command_policy_assignments, Nixstasis.CommandAllowlists.DevicePolicyAssignment do
      public? true
    end

    has_many :device_group_memberships, Nixstasis.Devices.DeviceGroupMembership do
      destination_attribute :device_id
    end

    many_to_many :device_groups, Nixstasis.Devices.DeviceGroup do
      through Nixstasis.Devices.DeviceGroupMembership
      source_attribute_on_join_resource :device_id
      destination_attribute_on_join_resource :group_id
    end
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
