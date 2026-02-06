defmodule NixstasisWeb.HeartbeatJSON do
  def show(%{commands: commands}) do
    %{
      data: %{
        commands:
          for(
            cmd <- commands,
            do: %{
              id: cmd.id,
              payload: cmd.command_payload,
              queued_at: cmd.queued_at
            }
          )
      }
    }
  end
end
