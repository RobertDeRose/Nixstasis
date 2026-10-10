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
         :ok <- validate_key_blob(decoded, algorithm) do
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

  # Parses the complete SSH wire-format key so truncated or padded blobs are
  # rejected before they can be enrolled or written to known_hosts.
  defp validate_key_blob(decoded, algorithm) do
    with {:ok, ^algorithm, body} <- read_field(decoded),
         :ok <- validate_key_body(algorithm, body) do
      :ok
    else
      _ -> {:error, :invalid_ssh_host_key}
    end
  end

  defp validate_key_body("ssh-ed25519", body) do
    case read_field(body) do
      {:ok, <<_key::binary-size(32)>>, ""} -> :ok
      _ -> {:error, :invalid_ssh_host_key}
    end
  end

  defp validate_key_body("ssh-rsa", body) do
    with {:ok, exponent, rest} when exponent != "" <- read_field(body),
         {:ok, modulus, ""} when modulus != "" <- read_field(rest) do
      :ok
    else
      _ -> {:error, :invalid_ssh_host_key}
    end
  end

  defp validate_key_body("ecdsa-sha2-" <> curve, body) do
    with {:ok, ^curve, rest} <- read_field(body),
         {:ok, <<4, coordinates::binary>>, ""} <- read_field(rest),
         true <- byte_size(coordinates) == 2 * ecdsa_coordinate_bytes(curve) do
      :ok
    else
      _ -> {:error, :invalid_ssh_host_key}
    end
  end

  defp ecdsa_coordinate_bytes("nistp256"), do: 32
  defp ecdsa_coordinate_bytes("nistp384"), do: 48
  defp ecdsa_coordinate_bytes("nistp521"), do: 66

  defp read_field(<<length::unsigned-big-integer-size(32), field::binary-size(length), rest::binary>>),
    do: {:ok, field, rest}

  defp read_field(_binary), do: :error
end
