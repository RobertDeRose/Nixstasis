defmodule NixstasisWeb.LiveViewTestHelpers do
  @moduledoc false

  def alert_new_path, do: "/alerts/new"
  def alert_edit_path(rule_id), do: "/alerts/#{rule_id}/edit"
end
