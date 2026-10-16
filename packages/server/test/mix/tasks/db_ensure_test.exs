defmodule Mix.Tasks.Db.EnsureTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Db.Ensure

  describe "decode_container_status/1" do
    test "reads the object status reported by container 1.5" do
      assert Ensure.decode_container_status(%{"status" => %{"state" => "running"}}) == :running
      assert Ensure.decode_container_status(%{"status" => %{"state" => "stopped"}}) == :stopped
    end

    test "reads the string status reported by earlier container releases" do
      assert Ensure.decode_container_status(%{"status" => "running"}) == :running
      assert Ensure.decode_container_status(%{"status" => "stopped"}) == :stopped
    end

    test "treats unknown or absent status as missing" do
      assert Ensure.decode_container_status(%{"status" => %{"state" => "creating"}}) == :missing
      assert Ensure.decode_container_status(%{}) == :missing
      assert Ensure.decode_container_status(nil) == :missing
    end
  end
end
