defmodule Nixstasis.Scripts.AuditTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Scripts.Audit

  test "emits an operator script audit event with actor identity" do
    Audit.subscribe()

    assert :ok = Audit.emit(:validated, "ops", %{script_id: "abc"})
    assert_receive {:script_audit, %{action: :validated, actor_id: "ops", actor_type: :operator}}
  end

  test "emits device-originated script audit events with device identity" do
    Audit.subscribe()

    assert :ok = Audit.emit_device(:test_result, "device-1", %{script_id: "abc"})
    assert_receive {:script_audit, %{action: :test_result, actor_id: "device-1", actor_type: :device}}
  end

  test "rejects operator script audit events without actor identity" do
    assert {:error, :missing_actor} = Audit.emit(:validated, " ", %{script_id: "abc"})
  end
end
