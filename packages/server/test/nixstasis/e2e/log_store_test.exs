defmodule Nixstasis.E2E.LogStoreTest do
  use Nixstasis.DataCase

  alias Nixstasis.E2E.LogStore

  setup do
    previous = Application.get_env(:nixstasis, :e2e)
    Application.put_env(:nixstasis, :e2e, log_dir: "tmp/e2e-logs")

    on_exit(fn ->
      File.rm_rf!("tmp/e2e-logs")

      if is_nil(previous) do
        Application.delete_env(:nixstasis, :e2e)
      else
        Application.put_env(:nixstasis, :e2e, previous)
      end
    end)

    :ok
  end

  test "writes and reads logs" do
    {:ok, path} = LogStore.write_log("run-1", "auth", "ok")
    assert {:ok, "ok"} = LogStore.read_log(path)
  end

  test "deletes logs" do
    {:ok, path} = LogStore.write_log("run-1", "dashboard", "line")
    assert :ok = LogStore.delete_log(path)
    assert {:error, :enoent} = File.read(path)
  end

  test "returns log_unavailable when reading a missing log" do
    missing = Path.join(LogStore.log_dir(), "run-missing/auth.log")
    assert {:error, :log_unavailable} = LogStore.read_log(missing)
  end

  test "returns log size for an existing log" do
    {:ok, path} = LogStore.write_log("run-1", "auth", "hello")
    assert {:ok, 5} = LogStore.log_size(path)
  end

  test "deletes run directory with all journey logs" do
    {:ok, first_path} = LogStore.write_log("run-1", 1, "auth", "one")
    {:ok, second_path} = LogStore.write_log("run-1", 2, "dashboard", "two")
    run_dir = Path.dirname(first_path)

    assert File.exists?(first_path)
    assert File.exists?(second_path)
    assert File.dir?(run_dir)

    assert :ok = LogStore.delete_run_dir("run-1")
    refute File.exists?(first_path)
    refute File.exists?(second_path)
    refute File.dir?(run_dir)
  end
end
