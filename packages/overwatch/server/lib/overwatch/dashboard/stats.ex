defmodule Nixstasis.Dashboard.Stats do
  @moduledoc """
  A struct representing the vital statistics for the dashboard.
  """

  defstruct total_devices: 0,
            online_devices: 0,
            offline_devices: 0,
            pending_approvals: 0,
            active_alerts: 0

  @type t :: %__MODULE__{
          total_devices: non_neg_integer(),
          online_devices: non_neg_integer(),
          offline_devices: non_neg_integer(),
          pending_approvals: non_neg_integer(),
          active_alerts: non_neg_integer()
        }
end
