defmodule Nixstasis.Notifications.Webhook do
  @moduledoc """
  Sends alert notifications to configured webhooks.
  """

  def send_alert_webhook(url, alert) do
    Req.post(url,
      json: %{
        id: alert.id,
        type: alert.type,
        message: alert.message,
        triggered_at: alert.triggered_at
      }
    )
  end
end
