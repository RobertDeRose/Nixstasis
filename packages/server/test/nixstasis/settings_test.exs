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

  describe "operator-managed settings" do
    test "rejects settings mutations without admin settings permission" do
      assert {:error, :forbidden} = Settings.put_offline_window(%{"can_manage" => false}, 20)

      assert {:error, :forbidden} =
               Settings.put_notifications_config(%{"can_manage" => false}, %{
                 "email" => "attacker@example.com",
                 "webhook_url" => "https://127.0.0.1/internal"
               })

      assert Settings.get_setting("offline_window") == nil
      assert Settings.get_setting("notifications") == nil
    end

    test "rejects private webhook destinations before saving" do
      assert {:error, {:invalid_webhook_url, :non_public_address}} =
               Settings.put_notifications_config(%{"can_manage" => true}, %{
                 "email" => "alerts@example.com",
                 "webhook_url" => "https://127.0.0.1/internal"
               })

      assert Settings.get_setting("notifications") == nil
    end

    test "blank webhook input preserves the masked stored destination and explicit clear removes it" do
      stored_url = "https://hooks.example.invalid/alert?token=stored-secret"

      assert {:ok, _setting} =
               Settings.put_setting("notifications", %{
                 "email" => "old@example.com",
                 "webhook_url" => stored_url
               })

      assert {:ok, _setting} =
               Settings.put_notifications_config(%{"can_manage" => true}, %{
                 "email" => "new@example.com",
                 "webhook_url" => "",
                 "clear_webhook_url" => "false"
               })

      assert Settings.get_notifications_config() == %{
               "email" => "new@example.com",
               "webhook_url" => stored_url
             }

      assert {:ok, _setting} =
               Settings.put_notifications_config(%{"can_manage" => true}, %{
                 "email" => "new@example.com",
                 "webhook_url" => "",
                 "clear_webhook_url" => "true"
               })

      assert Settings.get_notifications_config() == %{
               "email" => "new@example.com",
               "webhook_url" => nil
             }
    end
  end
end
