defmodule Nixstasis.AlertsTest do
  use Nixstasis.DataCase
  alias Nixstasis.Alerts

  describe "alert counts" do
    test "count_active/0 returns integer" do
      assert is_integer(Alerts.count_active())
    end
  end
end
