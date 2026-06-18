defmodule Nixstasis.Scripts.Authorization do
  @moduledoc """
  Authorization helpers for script workbench actions.
  """

  alias NixstasisWeb.Permissions

  def can_view?(session), do: Permissions.can_view_scripts?(session)
  def can_manage?(session), do: Permissions.can_manage_scripts?(session)

  def can_create?(session), do: can_manage?(session)
  def can_edit?(session), do: can_manage?(session)
  def can_validate?(session), do: can_manage?(session)
  def can_test?(session), do: can_manage?(session)
  def can_deploy?(session), do: can_manage?(session)
  def can_archive?(session), do: can_manage?(session)
end
