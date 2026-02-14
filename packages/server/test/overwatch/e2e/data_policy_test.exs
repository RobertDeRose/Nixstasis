defmodule Nixstasis.E2E.DataPolicyTest do
  use Nixstasis.DataCase

  alias Nixstasis.E2E.DataPolicy

  setup do
    previous = Application.get_env(:nixstasis, :e2e)
    Application.put_env(:nixstasis, :e2e, allowed_env_labels: ["local"])

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:nixstasis, :e2e)
      else
        Application.put_env(:nixstasis, :e2e, previous)
      end
    end)

    :ok
  end

  test "allows configured environments" do
    assert :ok = DataPolicy.validate_environment("local")
  end

  test "rejects unapproved environments" do
    assert {:error, message} = DataPolicy.validate_environment("prod")
    assert message =~ "not approved"
  end
end
