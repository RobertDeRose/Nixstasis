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

  scope "/api/json" do
    pipe_through [:api]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/json/open_api", default_model_expand_depth: 4

    forward "/", NixstasisWeb.AshJsonApiRouter
  end

  scope "/", NixstasisWeb do
    pipe_through(:browser)

    live("/", DashboardLive.Index, :index)
    live("/devices", DeviceLive.Index, :index)
    live("/devices/new", DeviceLive.Index, :new)
    live("/devices/:id", DeviceLive.Show, :show)
    live("/alerts", AlertLive.Index, :index)
    live("/alerts/new", AlertLive.Index, :new)
    live("/alerts/:id/edit", AlertLive.Index, :edit)
    live("/alerts/rules", AlertLive.Rules, :index)
    live("/reports", ReportLive.Index, :index)
    live("/reports/new", ReportLive.Index, :new)
    live("/reports/:id/edit", ReportLive.Index, :edit)
    live("/reports/:id", ReportLive.Show, :show)
    live("/settings", SettingsLive, :index)

    # get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  scope "/api/v1", NixstasisWeb do
    pipe_through(:api)

    get("/builder-schemas", BuilderSchemaController, :index)
    get("/builder-schemas/:schema_id/versions/:schema_version/options", BuilderSchemaController, :options)
    post("/builder-configurations/validate", BuilderConfigValidationController, :create)

    post("/devices/register", DeviceController, :register)
    post("/devices/:device_id/heartbeat", HeartbeatController, :create)
    post("/devices/:device_id/command_results", DeviceCommandController, :command_results)
    get("/devices/:device_id/command_payloads/:ref", DeviceCommandController, :command_payload)
    get("/check_domain", TLSController, :check_domain)
  end

  scope "/e2e", NixstasisWeb do
    pipe_through(:api)

    get("/suites", E2ERunController, :suites)
    get("/runs", E2ERunController, :index)
    post("/runs", E2ERunController, :create)
    get("/runs/:id", E2ERunController, :show)
    post("/runs/:id/cancel", E2ERunController, :cancel)
    get("/runs/:id/results", E2ERunResultController, :index)
    post("/runs/:id/results", E2ERunResultController, :create)
    get("/runs/:id/results/:journey_id/log", E2ERunResultController, :log)
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

      live_dashboard(
        "/dashboard",
        metrics: NixstasisWeb.Telemetry,
        ecto_repos: [Nixstasis.Repo],
        ecto_psql_extras_options: [long_running_queries: [threshold: "200 milliseconds"]],
        on_mount: [NixstasisWeb.LiveDashboard.ThemeHook],
        additional_pages: [
          e2e: NixstasisWeb.LiveDashboard.E2EPage
        ]
      )

      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  if Application.compile_env(:nixstasis, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
