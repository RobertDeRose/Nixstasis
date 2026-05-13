defmodule Nixstasis.Devices.SshKeyManager do
  @moduledoc """
  Manages the generation of ephemeral SSH keys for remote access sessions.
  """

  use GenServer

  @terminal_sessions_name __MODULE__.TerminalSessions
  @terminal_session_ttl_ms 60 * 60 * 1000

  @impl true
  def init(:terminal_sessions), do: {:ok, %{sessions: %{}}}

  def start_link(:terminal_sessions) do
    GenServer.start_link(__MODULE__, :terminal_sessions, name: @terminal_sessions_name)
  end

  @impl true
  def handle_call({:create_terminal_session, device_id, private_key, ttl_ms}, _from, state) do
    session_ref = Ecto.UUID.generate()
    expires_at = DateTime.add(DateTime.utc_now(), ttl_ms, :millisecond)
    timer = Process.send_after(self(), {:terminal_session_expired, session_ref}, max(ttl_ms, 0))

    session = %{device_id: to_string(device_id), private_key: private_key, expires_at: expires_at, timer: timer}
    state = put_in(state.sessions[session_ref], session)

    {:reply, {:ok, session_ref}, state}
  end

  def handle_call({:fetch_terminal_session, session_ref, device_id}, _from, state) do
    device_id = to_string(device_id)

    case Map.get(state.sessions, session_ref) do
      %{device_id: session_device_id, private_key: _private_key, expires_at: _expires_at}
      when session_device_id != device_id ->
        {:reply, {:error, :device_mismatch}, clear_terminal_session_state(state, session_ref)}

      %{private_key: private_key, expires_at: expires_at} ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:reply, {:ok, %{private_key: private_key, expires_at: expires_at}}, state}
        else
          {:reply, {:error, :expired}, clear_terminal_session_state(state, session_ref)}
        end

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:clear_terminal_session, session_ref}, _from, state) do
    {:reply, :ok, clear_terminal_session_state(state, session_ref)}
  end

  def handle_call({:terminal_session_active?, session_ref}, _from, state) do
    case Map.get(state.sessions, session_ref) do
      %{expires_at: expires_at} ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:reply, true, state}
        else
          {:reply, false, clear_terminal_session_state(state, session_ref)}
        end

      nil ->
        {:reply, false, state}
    end
  end

  @impl true
  def handle_info({:terminal_session_expired, session_ref}, state) do
    {:noreply, clear_terminal_session_state(state, session_ref)}
  end

  @doc """
  Stores SSH key material server-side behind an opaque, expiring session ref.
  """
  def create_terminal_session(device_id, private_key, opts \\ []) when is_binary(private_key) do
    ensure_terminal_sessions_manager!()
    ttl_ms = Keyword.get(opts, :ttl_ms, @terminal_session_ttl_ms)
    GenServer.call(@terminal_sessions_name, {:create_terminal_session, device_id, private_key, ttl_ms})
  end

  @doc """
  Fetches key material for a matching, unexpired terminal session ref.
  """
  def fetch_terminal_session(session_ref, device_id) when is_binary(session_ref) do
    ensure_terminal_sessions_manager!()
    GenServer.call(@terminal_sessions_name, {:fetch_terminal_session, session_ref, device_id})
  end

  def fetch_terminal_session(_session_ref, _device_id), do: {:error, :not_found}

  @doc """
  Removes terminal SSH key material for a session ref.
  """
  def clear_terminal_session(session_ref) when is_binary(session_ref) do
    ensure_terminal_sessions_manager!()
    GenServer.call(@terminal_sessions_name, {:clear_terminal_session, session_ref})
  end

  def clear_terminal_session(_session_ref), do: :ok

  @doc """
  Returns true when terminal key material is still stored for the session ref.
  """
  def terminal_session_active?(session_ref) when is_binary(session_ref) do
    ensure_terminal_sessions_manager!()
    GenServer.call(@terminal_sessions_name, {:terminal_session_active?, session_ref})
  end

  def terminal_session_active?(_session_ref), do: false

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

  defp ensure_terminal_sessions_manager! do
    unless Process.whereis(@terminal_sessions_name) do
      raise RuntimeError,
        message: "#{inspect(@terminal_sessions_name)} is not running; check supervision tree ordering"
    end
  end

  defp clear_terminal_session_state(state, session_ref) do
    case Map.pop(state.sessions, session_ref) do
      {%{timer: timer}, sessions} ->
        Process.cancel_timer(timer)
        %{state | sessions: sessions}

      {nil, _sessions} ->
        state
    end
  end
end
