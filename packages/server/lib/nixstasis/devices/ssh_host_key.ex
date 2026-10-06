defmodule Nixstasis.Devices.SshHostKey do
  @moduledoc false

  @allowed_algorithms MapSet.new([
                        "ssh-ed25519",
                        "ssh-rsa",
                        "ecdsa-sha2-nistp256",
                        "ecdsa-sha2-nistp384",
                        "ecdsa-sha2-nistp521"
                      ])
  @max_encoded_bytes 24_000
  @max_decoded_bytes 16_384

  def normalize(value) when is_binary(value) do
    trimmed = String.trim(value)

    with true <- byte_size(trimmed) > 0 and byte_size(trimmed) <= @max_encoded_bytes,
         [algorithm, encoded | _] <- String.split(trimmed, ~r/\s+/, parts: 3),
         true <- MapSet.member?(@allowed_algorithms, algorithm),
         {:ok, decoded} <- Base.decode64(encoded),
         true <- byte_size(decoded) > 0 and byte_size(decoded) <= @max_decoded_bytes,
         :ok <- validate_wire_algorithm(decoded, algorithm) do
      {:ok, algorithm <> " " <> encoded}
    else
      _ -> {:error, :invalid_ssh_host_key}
    end
  end

  def normalize(_value), do: {:error, :invalid_ssh_host_key}

  def fingerprint(value) do
    with {:ok, normalized} <- normalize(value),
         [_algorithm, encoded] <- String.split(normalized, " ", parts: 2),
         {:ok, decoded} <- Base.decode64(encoded) do
      {:ok, "SHA256:" <> Base.encode64(:crypto.hash(:sha256, decoded), padding: false)}
    else
      _ -> {:error, :invalid_ssh_host_key}
    end
  end

  def algorithm(value) do
    with {:ok, normalized} <- normalize(value),
         [algorithm, _encoded] <- String.split(normalized, " ", parts: 2) do
      {:ok, algorithm}
    end
  end

  defp validate_wire_algorithm(<<length::unsigned-big-integer-size(32), rest::binary>>, expected)
       when length > 0 and byte_size(rest) >= length do
    case rest do
      <<algorithm::binary-size(length), _::binary>> when algorithm == expected -> :ok
      _ -> {:error, :invalid_ssh_host_key}
    end
  end

  defp validate_wire_algorithm(_decoded, _expected), do: {:error, :invalid_ssh_host_key}
end
