defmodule Nixstasis.E2E.Protocol do
  @moduledoc """
  Validates E2E runner protocol compatibility.
  """

  def validate(version) when is_binary(version) do
    normalized = String.trim(version)
    supported = supported_versions()

    cond do
      normalized == "" ->
        {:error, {:protocol_mismatch, "Missing required X-E2E-Protocol-Version header."}}

      normalized in supported ->
        {:ok, normalized}

      true ->
        {:error,
         {:protocol_mismatch, "Unsupported protocol version '#{normalized}'. Supported: #{Enum.join(supported, ", ")}."}}
    end
  end

  def validate(_version) do
    {:error, {:protocol_mismatch, "Missing required X-E2E-Protocol-Version header."}}
  end

  def supported_versions do
    Application.get_env(:nixstasis, :e2e, [])
    |> Keyword.get(:protocol_versions, ["1"])
  end
end
