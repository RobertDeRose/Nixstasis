defmodule Nixstasis.Dashboard do
  @moduledoc """
  Context module for the Dashboard.
  """

  alias Nixstasis.Alerts
  alias Nixstasis.Dashboard.Stats
  alias Nixstasis.Devices

  @doc """
  Retrieves dashboard statistics constrained by the verified device-data actor.

  Missing or invalid authorization fails closed to zero-valued statistics.
  """
  @spec get_vital_stats(map() | nil) :: Stats.t()
  def get_vital_stats(actor) when is_map(actor) do
    %Stats{
      total_devices: Devices.count_all(actor: actor),
      online_devices: Devices.count_by_status(:online, actor: actor),
      offline_devices: Devices.count_by_status(:offline, actor: actor),
      pending_approvals: Devices.count_pending_approvals(actor: actor),
      active_alerts: Alerts.count_active(actor: actor)
    }
  end

  def get_vital_stats(_actor), do: %Stats{}
end
