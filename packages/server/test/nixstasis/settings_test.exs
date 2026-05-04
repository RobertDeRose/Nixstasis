defmodule Nixstasis.SettingsTest do
  use Nixstasis.DataCase

  alias Nixstasis.Settings

  describe "get_offline_window/0" do
    test "returns a positive integer stored as a number" do
      assert {:ok, _setting} = Settings.put_setting("offline_window", %{"minutes" => 15})

      assert Settings.get_offline_window() == 15
    end

    test "returns a positive integer stored as a string" do
      assert {:ok, _setting} = Settings.put_setting("offline_window", %{"minutes" => "20"})

      assert Settings.get_offline_window() == 20
    end

    test "falls back to default for invalid stored values" do
      assert {:ok, _setting} = Settings.put_setting("offline_window", %{"minutes" => "not-a-number"})

      assert Settings.get_offline_window() == 10
    end

    test "falls back to default for non-positive stored values" do
      assert {:ok, _setting} = Settings.put_setting("offline_window", %{"minutes" => 0})

      assert Settings.get_offline_window() == 10
    end
  end
end
