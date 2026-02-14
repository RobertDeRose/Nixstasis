defmodule Nixstasis.E2E.JourneySelectionTest do
  use Nixstasis.DataCase

  alias Nixstasis.E2E.JourneySelection

  setup do
    previous = Application.get_env(:nixstasis, :e2e)
    Application.put_env(:nixstasis, :e2e, suites: %{"full" => ["auth", "dashboard"]})

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:nixstasis, :e2e)
      else
        Application.put_env(:nixstasis, :e2e, previous)
      end
    end)

    :ok
  end

  test "returns full suite when no selection provided" do
    assert {:ok, ["auth", "dashboard"]} = JourneySelection.resolve("full", [])
  end

  test "rejects invalid journey selection" do
    assert {:error, message} = JourneySelection.resolve("full", ["auth", "logout"])
    assert message =~ "Invalid journeys"
  end
end
