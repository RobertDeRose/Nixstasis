import Config

alias Nixstasis.Deployment

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/nixstasis start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :nixstasis, NixstasisWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    Deployment.required_env!("DATABASE_URL")

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :nixstasis, Nixstasis.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    Deployment.required_env!("SECRET_KEY_BASE")

  host = Deployment.required_env!("PHX_HOST")

  port =
    case Deployment.port() do
      4000 ->
        4000

      configured_port ->
        raise ArgumentError, "PORT must be 4000 for supported Compose deployment, got: #{configured_port}"
    end

  base_domain = Deployment.required_env!("BASE_DOMAIN")
  ssh_client_frp_host = Deployment.optional_env("NIXSTASIS_SSH_FRP_HOST", "frps")
  ssh_client_frp_port = Deployment.optional_env("FRPS_TCPMUX_PORT", "2022")

  config :nixstasis, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
  config :nixstasis, :base_domain, base_domain
  config :nixstasis, :ssh_client, frp_host: ssh_client_frp_host, frp_port: ssh_client_frp_port
  config :nixstasis, :e2e_enabled?, Deployment.enabled?("NIXSTASIS_E2E_ENABLED", false)
  config :nixstasis, :local_browser_auth_fallback?, Deployment.enabled?("NIXSTASIS_LOCAL_BROWSER_AUTH_FALLBACK", false)
  config :nixstasis, :tls_observations_enabled, Deployment.enabled?("NIXSTASIS_TLS_OBSERVATIONS_ENABLED", false)

  config :nixstasis, :deployment,
    base_domain: base_domain,
    phoenix_host: host,
    phoenix_port: port

  endpoint_config = [
    url: [host: host, port: 443, scheme: "https"],
    check_origin:
      ["//#{host}"] ++
        case System.get_env("CHECK_ORIGIN_EXTRA") do
          nil -> []
          extra -> Enum.map(String.split(extra, ",", trim: true), &"//#{String.trim(&1)}")
        end,
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
  ]

  endpoint_config =
    if Deployment.strict_boolean_env!("NIXSTASIS_FORCE_SSL", true) do
      Keyword.put(endpoint_config, :force_ssl, hsts: true, rewrite_on: [:x_forwarded_proto])
    else
      endpoint_config
    end

  config :nixstasis, NixstasisWeb.Endpoint, endpoint_config

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :nixstasis, NixstasisWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :nixstasis, NixstasisWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :nixstasis, Nixstasis.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
