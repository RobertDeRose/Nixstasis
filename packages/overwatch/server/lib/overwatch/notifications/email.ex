defmodule Nixstasis.Notifications.Email do
  import Swoosh.Email

  def send_alert_email(to, alert) do
    new()
    |> to(to)
    |> from({"Nixstasis", "alerts@nixstasis.local"})
    |> subject("Alert: #{alert.type} - #{alert.message}")
    |> html_body("<h1>Alert Triggered</h1><p>#{alert.message}</p>")
    |> Nixstasis.Mailer.deliver()
  end
end
