defmodule Nixstasis.Provisioning.ArtifactTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Provisioning.Artifact

  test "accepts the bounded raw and archive filenames" do
    for filename <- [
          "config.toml",
          "config-bundle.tar.gz",
          "config-bundle.tgz",
          "config.tar.zst",
          "config.tar.zstd",
          "config.tzst"
        ] do
      assert {:ok, artifact} = Artifact.prepare("bytes", filename)
      assert artifact.filename == filename
      assert artifact.size == 5
      assert byte_size(artifact.sha256) == 64
    end
  end

  test "rejects unsupported filenames, empty artifacts, and oversized artifacts" do
    assert {:error, :empty_artifact} = Artifact.prepare("", "config.toml")
    assert {:error, :unsupported_filename} = Artifact.prepare("bytes", "../config.toml")

    oversized = :binary.copy("x", Artifact.max_size() + 1)
    assert {:error, :artifact_too_large} = Artifact.prepare(oversized, "config.toml")
  end
end
