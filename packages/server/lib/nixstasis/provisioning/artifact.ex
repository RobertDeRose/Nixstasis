defmodule Nixstasis.Provisioning.Artifact do
  @moduledoc """
  Validates the bounded opaque artifact accepted by the AtomixOS bootstrap API.

  The server does not unpack or rewrite the artifact. AtomixOS owns TOML and
  archive validation; Nixstasis only enforces the transport size and canonical
  filename boundary before sending the exact bytes.
  """

  @max_size 32 * 1024 * 1024
  @filenames MapSet.new([
               "config.toml",
               "config-bundle.tar.gz",
               "config-bundle.tgz",
               "config.tar.zst",
               "config.tar.zstd",
               "config.tzst"
             ])

  def max_size, do: @max_size

  def prepare(bytes, filename \\ "config.toml")

  def prepare(bytes, filename) when is_binary(bytes) and is_binary(filename) do
    cond do
      bytes == "" ->
        {:error, :empty_artifact}

      byte_size(bytes) > @max_size ->
        {:error, :artifact_too_large}

      not MapSet.member?(@filenames, filename) ->
        {:error, :unsupported_filename}

      true ->
        {:ok,
         %{
           bytes: bytes,
           filename: filename,
           size: byte_size(bytes),
           sha256: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
         }}
    end
  end

  def prepare(_bytes, _filename), do: {:error, :invalid_artifact}
end
