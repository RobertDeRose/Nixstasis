defmodule Nixstasis.Alerts do
  @moduledoc """
  Context module for alerts.
  """

  require Ash.Query

  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.Alert

  @doc """
  Counts active alerts visible to the optional Ash actor.
  """
  def count_active(opts \\ []) do
    Alert
    |> Ash.Query.filter(status == :active)
    |> Ash.count!(domain: Domain, actor: Keyword.get(opts, :actor))
  end
end
