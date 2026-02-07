defmodule Nixstasis.Domain do
  @moduledoc """
  Ash domain for the Nixstasis application.
  """

  use Ash.Domain,
    extensions: [AshJsonApi.Domain, AshPhoenix]

  json_api do
    authorize? false
    prefix "/api/json"

    routes do
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

    resource Nixstasis.Devices.PendingCommand do
      define :list_pending_commands, action: :read
      define :create_pending_command, action: :create
      define :update_pending_command, action: :update
      define :destroy_pending_command, action: :destroy
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
  end
end
