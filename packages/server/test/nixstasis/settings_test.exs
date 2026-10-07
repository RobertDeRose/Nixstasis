defmodule Nixstasis.SettingsTest do
  use Nixstasis.DataCase

  alias Nixstasis.Repo
  alias Nixstasis.Settings
  alias Nixstasis.SystemSetting

  describe "get_offline_window/0" do
    test "returns a positive integer stored as a number" do
      assert {:ok, _setting} = Settings.put_setting("offline_window", %{"minutes" => 15})

      assert Settings.get_offline_window() == 15
    end

    test "returns a positive integer stored as a string" do
      Repo.insert!(%SystemSetting{key: "offline_window", value: %{"minutes" => "20"}})

      assert Settings.get_offline_window() == 20
    end

    test "falls back to default for invalid stored values" do
      Repo.insert!(%SystemSetting{key: "offline_window", value: %{"minutes" => "not-a-number"}})

      assert Settings.get_offline_window() == 10
    end

    test "falls back to default for non-positive stored values" do
      Repo.insert!(%SystemSetting{key: "offline_window", value: %{"minutes" => 0}})

      assert Settings.get_offline_window() == 10
    end
  end

  describe "put_offline_window/2" do
    test "normalizes positive integers and trimmed integer strings" do
      for {input, expected} <- [{1, 1}, {15, 15}, {"20", 20}, {" 30 ", 30}] do
        assert {:ok, setting} = Settings.put_offline_window(%{"can_manage" => true}, input)
        assert setting.value == %{"minutes" => expected}
        assert Settings.get_offline_window() == expected
      end
    end

    test "rejects invalid minutes without creating a setting" do
      for input <- [0, -5, 1.5, "0", "-5", "1.5", "", " ", "15minutes", nil, true, %{}, []] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Settings.put_offline_window(%{"can_manage" => true}, input)

        assert Settings.get_setting("offline_window") == nil
      end
    end

    test "invalid minutes leave the previously saved window unchanged" do
      assert {:ok, _setting} = Settings.put_offline_window(%{"can_manage" => true}, 25)

      for input <- ["0", "-5", "1.5", "not-a-number"] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Settings.put_offline_window(%{"can_manage" => true}, input)

        assert Settings.get_setting("offline_window") == %{"minutes" => 25}
        assert Settings.get_offline_window() == 25
      end
    end
  end

  test "raw context writes use resource validation and normalization" do
    assert {:error, %Ash.Error.Invalid{}} = Settings.put_setting("offline_window", %{"minutes" => 0})
    assert Settings.get_setting("offline_window") == nil

    assert {:ok, setting} = Settings.put_setting("offline_window", %{"minutes" => " 15 "})
    assert setting.value == %{"minutes" => 15}

    assert {:error, %Ash.Error.Invalid{}} =
             Settings.put_setting("notifications", %{"webhook_url" => "https://127.0.0.1/internal"})

    assert Settings.get_setting("notifications") == nil
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
      assert {:error, %Ash.Error.Invalid{}} =
               Settings.put_notifications_config(%{"can_manage" => true}, %{
                 "email" => "alerts@example.com",
                 "webhook_url" => "https://127.0.0.1/internal"
               })

      assert Settings.get_setting("notifications") == nil
    end

    test "rejects non-string webhook inputs without creating notifications settings" do
      for input <- [123, 1.5, true, false, [], ["https://example.com"], %{}],
          clear <- ["false", "true"] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Settings.put_notifications_config(%{"can_manage" => true}, %{
                   "email" => "alerts@example.com",
                   "webhook_url" => input,
                   "clear_webhook_url" => clear
                 })

        assert Exception.message(error) =~ "webhook URL must be a string"
        assert Settings.get_setting("notifications") == nil
      end
    end

    test "non-string webhook inputs leave the stored webhook and email unchanged" do
      stored = %{
        "email" => "old@example.com",
        "webhook_url" => "https://hooks.example.invalid/alert?token=stored-secret"
      }

      Repo.insert!(%SystemSetting{key: "notifications", value: stored})

      for input <- [123, 1.5, true, false, [], ["https://example.com"], %{}],
          clear <- ["false", "true"] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Settings.put_notifications_config(%{"can_manage" => true}, %{
                   "email" => "new@example.com",
                   "webhook_url" => input,
                   "clear_webhook_url" => clear
                 })

        assert Exception.message(error) =~ "webhook URL must be a string"
        assert Settings.get_notifications_config() == stored
      end
    end

    test "missing, nil and whitespace webhook inputs preserve the stored destination" do
      stored_url = "https://hooks.example.invalid/alert?token=stored-secret"

      Repo.insert!(%SystemSetting{
        key: "notifications",
        value: %{"email" => "old@example.com", "webhook_url" => stored_url}
      })

      for params <- [%{}, %{"webhook_url" => nil}, %{"webhook_url" => "  "}] do
        assert {:ok, _setting} =
                 Settings.put_notifications_config(
                   %{"can_manage" => true},
                   Map.put(params, "email", "new@example.com")
                 )

        assert Settings.get_notifications_config() == %{
                 "email" => "new@example.com",
                 "webhook_url" => stored_url
               }
      end
    end

    test "blank webhook input preserves the masked stored destination and explicit clear removes it" do
      stored_url = "https://hooks.example.invalid/alert?token=stored-secret"

      Repo.insert!(%SystemSetting{
        key: "notifications",
        value: %{"email" => "old@example.com", "webhook_url" => stored_url}
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
