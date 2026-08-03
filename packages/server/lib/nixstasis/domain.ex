defmodule Nixstasis.Domain do
  @moduledoc """
  Ash domain for the Nixstasis application.
  """

  use Ash.Domain,
    extensions: [AshJsonApi.Domain, AshPhoenix]

  alias Nixstasis.CommandAllowlists.PolicyResolver
  alias Nixstasis.CommandCatalog.Resolver, as: CatalogResolver

  json_api do
    authorize? false
    prefix "/api/json"

    routes do
      base_route "/builder_contract", Nixstasis.SchemaOptions.BuilderContract do
        route :get, "/schema_references", :list_schema_references, name: "list_builder_schema_references"

        route :get, "/schemas/:schema_id/versions/:schema_version/options", :options_for,
          name: "get_builder_schema_options",
          query_params: [:builder]

        route :post, "/builder_configurations/validate", :validate_builder_configuration,
          name: "validate_builder_configuration"
      end

      base_route "/device_runtime/devices", Nixstasis.Devices.Device do
        route :get, "/", :list_runtime_devices, name: "list_runtime_devices"

        route :post, "/register", :register_runtime_device, name: "register_runtime_device"

        route :post, "/:device_id/heartbeat", :heartbeat,
          name: "heartbeat",
          modify_conn: &__MODULE__.put_ok_status/4

        route :post, "/:device_id/command_results", :acknowledge_command_results,
          name: "acknowledge_command_results",
          modify_conn: &__MODULE__.put_accepted_status/4

        route :get, "/:device_id/command_payloads/:ref", :fetch_command_payload, name: "fetch_command_payload"
      end

      base_route "/devices", Nixstasis.Devices.Device do
        get :read
        index :read
        post :create
        patch :update
        delete :destroy
      end

      base_route "/pending_commands", Nixstasis.Devices.PendingCommand do
        get :read
        index :read
        post :create
        patch :update
        delete :destroy
      end

      base_route "/alerts", Nixstasis.Monitoring.Alert do
        get :read
        index :read
        post :create
        patch :update
        delete :destroy
      end

      base_route "/alert_rules", Nixstasis.Monitoring.AlertRule do
        get :read
        index :read
        post :create
        patch :update
        delete :destroy
      end

      base_route "/telemetry_events", Nixstasis.Monitoring.Telemetry do
        get :read
        index :read
        post :create
      end

      base_route "/custom_reports", Nixstasis.Reporting.CustomReport do
        get :read
        index :read
        post :create
        patch :update
        delete :destroy
      end

      base_route "/system_settings", Nixstasis.SystemSetting do
        get :read
        index :read
        post :create
        patch :update
        delete :destroy
      end
    end
  end

  def put_ok_status(conn, _subject, _result, _request), do: Plug.Conn.put_status(conn, :ok)

  def put_accepted_status(conn, _subject, _result, _request),
    do: Plug.Conn.put_status(conn, :accepted)

  def preview_command_policy(attrs), do: PolicyResolver.preview(attrs)
  def preview_catalog_command_compatibility(attrs), do: CatalogResolver.preview(attrs)
  def command_inventory_probe_manifest, do: CatalogResolver.probe_manifest()

  resources do
    resource Nixstasis.Devices.Device do
      define :list_devices, action: :read
      define :get_device, action: :read, get_by: [:id]
      define :get_device_by_mac, action: :read, get_by: [:mac_address]
      define :create_device, action: :create
      define :register_device, action: :register
      define :update_device, action: :update
      define :destroy_device, action: :destroy
    end

    resource Nixstasis.Devices.DeviceGroup do
      define :list_device_groups, action: :read
      define :get_device_group, action: :read, get_by: [:id]
      define :create_device_group, action: :create
      define :update_device_group, action: :update
      define :destroy_device_group, action: :destroy
    end

    resource Nixstasis.Devices.DeviceGroupMembership do
      define :list_device_group_memberships, action: :read
      define :get_device_group_membership, action: :read, get_by: [:id]
      define :create_device_group_membership, action: :create
      define :destroy_device_group_membership, action: :destroy
    end

    resource Nixstasis.Devices.PendingCommand do
      define :list_pending_commands, action: :read
      define :create_pending_command, action: :create
      define :update_pending_command, action: :update
      define :destroy_pending_command, action: :destroy
    end

    resource Nixstasis.CommandAllowlists.CommandEntry do
      define :list_command_allowlist_entries, action: :read
      define :get_command_allowlist_entry, action: :read, get_by: [:id]
      define :create_command_allowlist_entry, action: :create
      define :update_command_allowlist_entry, action: :update
    end

    resource Nixstasis.CommandAllowlists.CommandEntryVersion do
      define :list_command_allowlist_entry_versions, action: :read
      define :create_command_allowlist_entry_version, action: :create
    end

    resource Nixstasis.CommandAllowlists.Category do
      define :list_command_allowlist_categories, action: :read
      define :get_command_allowlist_category, action: :read, get_by: [:id]
      define :create_command_allowlist_category, action: :create
      define :update_command_allowlist_category, action: :update
      define :destroy_command_allowlist_category, action: :destroy
    end

    resource Nixstasis.CommandAllowlists.CommandEntryCategory do
      define :list_command_allowlist_entry_categories, action: :read
      define :create_command_allowlist_entry_category, action: :create
      define :destroy_command_allowlist_entry_category, action: :destroy
    end

    resource Nixstasis.CommandAllowlists.DevicePolicyAssignment do
      define :list_command_policy_assignments, action: :read
      define :get_command_policy_assignment, action: :read, get_by: [:id]
      define :create_command_policy_assignment, action: :create
    end

    resource Nixstasis.CommandAllowlists.DevicePolicyAssignmentSource do
      define :list_command_policy_assignment_sources, action: :read
      define :create_command_policy_assignment_source, action: :create
    end

    resource Nixstasis.CommandAllowlists.PolicyDeliveryResult do
      define :list_command_policy_delivery_results, action: :read
      define :create_command_policy_delivery_result, action: :create
    end

    resource Nixstasis.CommandCatalog.Category do
      define :list_command_catalog_categories, action: :read
      define :get_command_catalog_category, action: :read, get_by: [:id]
      define :create_command_catalog_category, action: :create
      define :update_command_catalog_category, action: :update
      define :destroy_command_catalog_category, action: :destroy
    end

    resource Nixstasis.CommandCatalog.CatalogCommand do
      define :list_command_catalog_commands, action: :read
      define :get_command_catalog_command, action: :read, get_by: [:id]
      define :create_command_catalog_command, action: :create
      define :update_command_catalog_command, action: :update
    end

    resource Nixstasis.CommandCatalog.PackageMapping do
      define :list_command_catalog_mappings, action: :read
      define :get_command_catalog_mapping, action: :read, get_by: [:id]
      define :create_command_catalog_mapping, action: :create
      define :update_command_catalog_mapping, action: :update
      define :destroy_command_catalog_mapping, action: :destroy
    end

    resource Nixstasis.CommandCatalog.DeviceInventorySnapshot do
      define :list_device_command_inventory_snapshots, action: :read
      define :get_device_command_inventory_snapshot, action: :read, get_by: [:id]
      define :create_device_command_inventory_snapshot, action: :create
      define :update_device_command_inventory_snapshot, action: :update
      define :destroy_device_command_inventory_snapshot, action: :destroy
    end

    resource Nixstasis.Scripts.ScriptDraft do
      define :list_script_drafts, action: :read
      define :get_script_draft, action: :read, get_by: [:id]
      define :create_script_draft, action: :create
      define :update_script_draft, action: :update
      define :destroy_script_draft, action: :destroy
    end

    resource Nixstasis.Scripts.ScriptVersion do
      define :list_script_versions, action: :read
      define :get_script_version, action: :read, get_by: [:id]
      define :create_script_version, action: :create
      define :update_script_version, action: :update
      define :destroy_script_version, action: :destroy
    end

    resource Nixstasis.Scripts.ScriptValidationRun do
      define :list_script_validation_runs, action: :read
      define :create_script_validation_run, action: :create
      define :update_script_validation_run, action: :update
      define :destroy_script_validation_run, action: :destroy
    end

    resource Nixstasis.Scripts.ScriptTestRun do
      define :list_script_test_runs, action: :read
      define :create_script_test_run, action: :create
      define :update_script_test_run, action: :update
      define :destroy_script_test_run, action: :destroy
    end

    resource Nixstasis.Scripts.ScriptDeploymentRun do
      define :list_script_deployment_runs, action: :read
      define :create_script_deployment_run, action: :create
      define :update_script_deployment_run, action: :update
      define :destroy_script_deployment_run, action: :destroy
    end

    resource Nixstasis.Scripts.ScriptClientAction do
      define :list_script_client_actions, action: :read
      define :create_script_client_action, action: :create
      define :update_script_client_action, action: :update
      define :destroy_script_client_action, action: :destroy
    end

    resource Nixstasis.Monitoring.Alert do
      define :list_alerts, action: :read
      define :create_alert, action: :create
      define :update_alert, action: :update
      define :destroy_alert, action: :destroy
    end

    resource Nixstasis.Monitoring.AlertRule do
      define :list_rules, action: :read
      define :get_rule, action: :read, get_by: [:id]
      define :create_rule, action: :create
      define :update_rule, action: :update
      define :destroy_rule, action: :destroy
    end

    resource Nixstasis.Monitoring.Telemetry do
      define :list_telemetry_events, action: :read
      define :create_telemetry_event, action: :create
    end

    resource Nixstasis.Reporting.CustomReport do
      define :list_custom_reports, action: :read
      define :get_custom_report, action: :read, get_by: [:id]
      define :create_custom_report, action: :create
      define :update_custom_report, action: :update
      define :destroy_custom_report, action: :destroy
    end

    resource Nixstasis.SystemSetting do
      define :get_setting_by_key, action: :read, get_by: [:key]
      define :create_setting, action: :create
      define :update_setting, action: :update
    end

    resource Nixstasis.SchemaOptions.BuilderContract do
      define :list_builder_schema_references, action: :list_schema_references

      define :get_builder_schema_options,
        action: :options_for,
        args: [:schema_id, :schema_version, :builder]

      define :validate_builder_configuration,
        action: :validate_builder_configuration,
        args: [:builder, :schema_id, :schema_version, :selections]
    end
  end
end
