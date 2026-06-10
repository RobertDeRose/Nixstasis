defmodule Nixstasis.Scripts.AuditTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Scripts.Audit

  test "emits a script audit event payload" do
    assert :ok = Audit.emit(:validated, %{script_id: "abc", actor: "ops"})
  end
end
