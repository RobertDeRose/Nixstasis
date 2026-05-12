defmodule Nixstasis.TLSObservations do
  @moduledoc false

  use GenServer

  @max_observations 50

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts), do: {:ok, []}

  def record(domain, approved?) when is_binary(domain) do
    if enabled?() do
      GenServer.call(__MODULE__, {:record, domain, approved?})
    end

    :ok
  end

  def list do
    GenServer.call(__MODULE__, :list)
  end

  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  def enabled? do
    Application.get_env(:nixstasis, :tls_observations_enabled, false)
  end

  @impl true
  def handle_call({:record, domain, approved?}, _from, observations) do
    observation = %{
      domain: domain,
      approved: approved?,
      observed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:reply, :ok, [observation | observations] |> Enum.take(@max_observations)}
  end

  @impl true
  def handle_call(:list, _from, observations), do: {:reply, observations, observations}

  @impl true
  def handle_call(:clear, _from, _observations), do: {:reply, :ok, []}
end
