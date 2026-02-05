# Context Interface: Nixstasis.Devices

## Types

```elixir
@type t :: %Nixstasis.Devices.Device{
  id: Ecto.UUID.t(),
  name: String.t(),
  ipv4_address: Postgrex.INET.t() | nil,
  account_number: String.t() | nil,
  approval_status: :pending | :approved | :rejected,
  remote_access_requested: boolean(),
  last_polled_at: DateTime.t() | nil,
  # ... standard timestamps
}
```

## Public API

### List / Filter

```elixir
@doc """
Returns a list of devices matching the given criteria.
Used by LiveView Streams.
"""
@spec list_devices(params :: map()) :: [t()]
# params supports: :sort_by, :sort_dir, :status_filter, :search_query
```

### Management

```elixir
@doc "Creates a device (typically from self-registration)."
@spec create_device(attrs :: map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}

@doc "Updates device attributes."
@spec update_device(device :: t(), attrs :: map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}

@doc "Bulk approves devices by ID."
@spec approve_devices(ids :: [Ecto.UUID.t()]) :: {integer(), nil}

@doc "Bulk rejects (deletes or marks) devices by ID."
@spec reject_devices(ids :: [Ecto.UUID.t()]) :: {integer(), nil}
```

### Remote Access

```elixir
@doc """
Toggles the remote access flag.
Triggers frpc start/stop on the device via the next heartbeat response.
"""
@spec request_remote_access(device :: t(), active :: boolean()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}

@doc """
Establishes an SSH connection to the device via the frps tunnel.
Returns a PID to the GenServer managing the connection.
"""
@spec connect_ssh(device :: t(), opts :: keyword()) :: {:ok, pid()} | {:error, term()}
```
