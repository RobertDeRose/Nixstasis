defmodule NixstasisWeb.Plugs.E2EAuthorization do
  @moduledoc false

  import Plug.Conn

  alias NixstasisWeb.DeviceAuthentication

  @runner_header "x-e2e-runner-id"

  def init(opts), do: opts

  def call(conn, _opts) do
    with [runner_id] <- get_req_header(conn, @runner_header),
         true <- valid_runner_id?(runner_id),
         {:ok, provided_token} <- bearer_token(conn),
         {:ok, expected_token} <- configured_token(runner_id),
         true <- secure_match?(expected_token, provided_token) do
      assign(conn, :e2e_runner_id, runner_id)
    else
      _ -> reject(conn)
    end
  end

  defp configured_token(runner_id) do
    case Application.get_env(:nixstasis, :e2e_runners, %{}) do
      %{^runner_id => token} when is_binary(token) and byte_size(token) >= 32 -> {:ok, token}
      _ -> :error
    end
  end

  # Reuse the device parser so the scheme is case-insensitive per RFC 9110.
  defp bearer_token(conn) do
    case DeviceAuthentication.bearer_token(conn) do
      {:ok, token} when byte_size(token) >= 32 -> {:ok, token}
      _ -> :error
    end
  end

  defp secure_match?(expected, provided) do
    expected_digest = :crypto.hash(:sha256, expected)
    provided_digest = :crypto.hash(:sha256, provided)
    Plug.Crypto.secure_compare(expected_digest, provided_digest)
  end

  defp valid_runner_id?(runner_id) when is_binary(runner_id) do
    Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/, runner_id)
  end

  defp valid_runner_id?(_), do: false

  defp reject(conn) do
    body = Jason.encode!(%{error: %{code: "unauthorized", message: "Valid E2E runner credentials are required."}})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:unauthorized, body)
    |> halt()
  end
end
