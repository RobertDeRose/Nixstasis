defmodule Nixstasis.Devices.SshKeyManager do
  @moduledoc """
  Manages the generation of ephemeral SSH keys for remote access sessions.
  """

  @doc """
  Generates an ephemeral SSH key pair.

  ## Options

    * `:type` - The type of key to generate. Defaults to `:ed25519`. Supported types: `:ed25519`, `:rsa`.

  ## Returns

  `{:ok, %{private_key: String.t(), public_key: String.t()}}` or `{:error, reason}`.
  """
  def generate_key_pair(opts \\ []) do
    type = Keyword.get(opts, :type, :ed25519)
    dir = System.tmp_dir!()
    id = Ecto.UUID.generate()
    key_path = Path.join(dir, "nixstasis_ssh_#{id}")

    # Ensure cleanup even if something crashes, though we will delete explicitly
    try do
      args = key_gen_args(type, key_path)

      case System.cmd("ssh-keygen", args, stderr_to_stdout: true) do
        {_, 0} ->
          read_keys(key_path)

        {output, _} ->
          {:error, "ssh-keygen failed: #{output}"}
      end
    after
      File.rm(key_path)
      File.rm("#{key_path}.pub")
    end
  end

  defp key_gen_args(:ed25519, path) do
    ["-t", "ed25519", "-f", path, "-N", "", "-C", "nixstasis-remote-access"]
  end

  defp key_gen_args(:rsa, path) do
    ["-t", "rsa", "-b", "4096", "-f", path, "-N", "", "-C", "nixstasis-remote-access"]
  end

  defp read_keys(path) do
    with {:ok, private_key} <- File.read(path),
         {:ok, public_key} <- File.read("#{path}.pub") do
      {:ok, %{private_key: private_key, public_key: String.trim(public_key)}}
    else
      {:error, reason} -> {:error, "Failed to read generated keys: #{inspect(reason)}"}
    end
  end
end
