defmodule Nixstasis.Monitoring.TelemetryLimits do
  @moduledoc """
  Bounds untrusted heartbeat telemetry before it can affect durable state.

  The limits intentionally apply to the normalized telemetry document that is
  persisted and indexed, rather than to unrelated heartbeat fields.
  """

  @max_encoded_bytes 65_536
  @max_depth 8
  @max_total_keys 512
  @max_map_entries 128
  @max_key_bytes 128
  @max_array_items 256
  @max_string_bytes 16_384

  @doc "Returns the fixed telemetry resource limits enforced by the server."
  def limits do
    %{
      max_encoded_bytes: @max_encoded_bytes,
      max_depth: @max_depth,
      max_total_keys: @max_total_keys,
      max_map_entries: @max_map_entries,
      max_key_bytes: @max_key_bytes,
      max_array_items: @max_array_items,
      max_string_bytes: @max_string_bytes
    }
  end

  @doc "Validates one normalized telemetry payload against all persistence limits."
  def validate(payload) when is_map(payload) do
    with {:ok, _key_count} <- walk(payload, 0, 0),
         :ok <- validate_encoded_size(payload) do
      :ok
    else
      {:error, :encoded_bytes} ->
        {:error, "telemetry exceeds maximum encoded size of #{@max_encoded_bytes} bytes"}

      {:error, :depth} ->
        {:error, "telemetry exceeds maximum nesting depth of #{@max_depth}"}

      {:error, :total_keys} ->
        {:error, "telemetry exceeds maximum total key count of #{@max_total_keys}"}

      {:error, :map_entries} ->
        {:error, "telemetry object exceeds maximum key count of #{@max_map_entries}"}

      {:error, :key_bytes} ->
        {:error, "telemetry key exceeds maximum size of #{@max_key_bytes} bytes"}

      {:error, :array_items} ->
        {:error, "telemetry array exceeds maximum item count of #{@max_array_items}"}

      {:error, :string_bytes} ->
        {:error, "telemetry string exceeds maximum size of #{@max_string_bytes} bytes"}

      {:error, :json} ->
        {:error, "telemetry must contain only JSON-compatible values"}
    end
  end

  def validate(_payload), do: {:error, "telemetry must be a JSON object"}

  defp validate_encoded_size(payload) do
    case Jason.encode(payload) do
      {:ok, encoded} when byte_size(encoded) <= @max_encoded_bytes -> :ok
      {:ok, _encoded} -> {:error, :encoded_bytes}
      {:error, _reason} -> {:error, :json}
    end
  end

  defp walk(_value, depth, _key_count) when depth > @max_depth, do: {:error, :depth}

  defp walk(value, _depth, key_count) when is_binary(value) do
    if byte_size(value) <= @max_string_bytes,
      do: {:ok, key_count},
      else: {:error, :string_bytes}
  end

  defp walk(value, _depth, key_count)
       when is_number(value) or is_boolean(value) or is_nil(value),
       do: {:ok, key_count}

  defp walk(value, _depth, _key_count) when is_struct(value), do: {:error, :json}

  defp walk(value, depth, key_count) when is_map(value) do
    cond do
      map_size(value) > @max_map_entries ->
        {:error, :map_entries}

      key_count + map_size(value) > @max_total_keys ->
        {:error, :total_keys}

      true ->
        next_key_count = key_count + map_size(value)

        Enum.reduce_while(value, {:ok, next_key_count}, fn {key, child}, {:ok, count} ->
          with :ok <- validate_key(key),
               {:ok, child_count} <- walk(child, depth + 1, count) do
            {:cont, {:ok, child_count}}
          else
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  defp walk(value, depth, key_count) when is_list(value) do
    if array_limit_exceeded?(value) do
      {:error, :array_items}
    else
      Enum.reduce_while(value, {:ok, key_count}, fn child, {:ok, count} ->
        case walk(child, depth + 1, count) do
          {:ok, child_count} -> {:cont, {:ok, child_count}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp walk(_value, _depth, _key_count), do: {:error, :json}

  defp array_limit_exceeded?(value) do
    value
    |> Enum.take(@max_array_items + 1)
    |> length()
    |> Kernel.>(@max_array_items)
  end

  defp validate_key(key) when is_binary(key) do
    if byte_size(key) <= @max_key_bytes, do: :ok, else: {:error, :key_bytes}
  end

  defp validate_key(key) when is_atom(key), do: key |> Atom.to_string() |> validate_key()
  defp validate_key(_key), do: {:error, :json}
end
