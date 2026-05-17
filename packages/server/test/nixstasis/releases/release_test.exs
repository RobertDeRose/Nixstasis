defmodule Nixstasis.ReleaseTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Deployment
  alias Nixstasis.Release

  test "deployment port defaults to the canonical runtime value" do
    System.delete_env("PORT")

    assert Deployment.port() == 4000
  end

  test "release module exposes migrate entrypoint" do
    assert function_exported?(Release, :migrate, 0)
  end
end
