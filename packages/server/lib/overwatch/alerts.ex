defmodule Nixstasis.Alerts do
  @moduledoc """
  Context module for alerts.
  """
  import Ecto.Query
  alias Nixstasis.Repo
  alias Nixstasis.Monitoring.Alert

  @doc """
  Counts active alerts.
  """
  def count_active do
    Alert
    |> where([a], a.status == "active")
    |> Repo.aggregate(:count, :id)
  end
end
