Code.require_file(
  Path.expand(
    "../../../../priv/repo/migrations/20260803120000_deduplicate_terminal_revokes.exs",
    __DIR__
  )
)

defmodule Nixstasis.Repo.Migrations.DeduplicateTerminalRevokesTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Repo
  alias Nixstasis.Repo.Migrations.DeduplicateTerminalRevokes

  test "deduplicates terminal revokes without deleting other commands" do
    {:ok, device} =
      Devices.create_device(%{
        mac_address: "AA:BB:CC:DD:EE:01",
        product_name: "migration-test"
      })

    session_ref = "migration-session"
    revoke_payload = revoke_payload(session_ref)

    Repo.query!("DROP INDEX IF EXISTS pending_commands_terminal_revoke_unique")

    {:ok, older} =
      Domain.create_pending_command(%{
        device_id: device.id,
        command_payload: revoke_payload,
        status: :queued,
        queued_at: ~U[2026-08-03 16:00:00Z]
      })

    {:ok, newer} =
      Domain.create_pending_command(%{
        device_id: device.id,
        command_payload: revoke_payload,
        status: :queued,
        queued_at: ~U[2026-08-03 17:00:00Z]
      })

    {:ok, unrelated} =
      Domain.create_pending_command(%{
        device_id: device.id,
        command_payload: %{
          "type" => "ssh_authorize",
          "payload" => %{"name" => session_ref}
        },
        status: :queued,
        queued_at: ~U[2026-08-03 18:00:00Z]
      })

    assert :ok = DeduplicateTerminalRevokes.deduplicate_existing_revokes(Repo)

    remaining_ids =
      Repo.all(
        from command in "pending_commands",
          where: command.device_id == type(^device.id, Ecto.UUID),
          order_by: command.queued_at,
          select: command.id
      )
      |> Enum.map(&Ecto.UUID.load!/1)

    assert remaining_ids == [newer.id, unrelated.id]
    refute older.id in remaining_ids
  end

  defp revoke_payload(session_ref) do
    %{
      "type" => "ssh_revoke",
      "payload" => %{
        "name" => session_ref,
        "content_type" => "application/vnd.nixstasis.ssh-revoke+json;version=1",
        "data" => Jason.encode!(%{session_ref: session_ref})
      }
    }
  end
end
