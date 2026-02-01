defmodule Nixstasis.Repo do
  use Ecto.Repo,
    otp_app: :nixstasis,
    adapter: Ecto.Adapters.Postgres
end
