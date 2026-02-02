defmodule NixstasisWeb.Router do
  use NixstasisWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {NixstasisWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", NixstasisWeb do
    pipe_through(:browser)

    live("/", DashboardLive.Index, :index)
    live("/devices/approvals", DeviceLive.Approval, :index)
    live("/devices", DeviceLive.Index, :index)
    live("/devices/new", DeviceLive.Index, :new)
    live("/alerts", AlertLive.Index, :index)
    live("/alerts/new", AlertLive.Index, :new)
    live("/alerts/rules", AlertLive.Rules, :index)
    live("/reports", ReportLive.Index, :index)
    live("/reports/new", ReportLive.Index, :new)
    live("/reports/:id", ReportLive.Show, :show)
    live("/settings", SettingsLive, :index)

    # get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  scope "/api/v1", NixstasisWeb do
    pipe_through(:api)

    post("/devices/register", DeviceController, :register)
    post("/devices/:device_id/heartbeat", HeartbeatController, :create)
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:nixstasis, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: NixstasisWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
