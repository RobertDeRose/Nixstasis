defmodule Nixstasis.Dashboard do
  @moduledoc """
  Context module for the Dashboard.
  """

  alias Nixstasis.Devices
  alias Nixstasis.Alerts
  alias Nixstasis.Dashboard.Stats

  @doc """
  Retrieves the current aggregated statistics for the dashboard.
  """
  @spec get_vital_stats() :: Stats.t()
  def get_vital_stats do
    %Stats{
      total_devices: Devices.count_all(),
      online_devices: Devices.count_by_status(:online),
      offline_devices: Devices.count_by_status(:offline),
      pending_approvals: Devices.count_pending_approvals(),
      active_alerts: Alerts.count_active()
    }
  end
end
