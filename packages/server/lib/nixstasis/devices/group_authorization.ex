defmodule Nixstasis.Devices.GroupAuthorization do
  @moduledoc """
  Trusted server-built authorization used by device group context operations.
  """

  @enforce_keys [:actor_id, :can_manage_devices?, :can_manage_all_devices?, :authorized_device_ids]
  defstruct [:actor_id, :can_manage_devices?, :can_manage_all_devices?, :authorized_device_ids]
end
