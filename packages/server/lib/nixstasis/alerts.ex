defmodule Nixstasis.Alerts do
  @moduledoc """
  Context module for alerts.
  """

  require Ash.Query

  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.Alert

  @doc """
  Counts active alerts.
  """
  def count_active do
    Alert
    |> Ash.Query.filter(status == :active)
    |> Ash.count!(domain: Domain)
  end
end
