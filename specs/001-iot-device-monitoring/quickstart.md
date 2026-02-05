# Quickstart: IoT Device Monitoring

## Prerequisites

- **Elixir**: 1.14+
- **Postgres**: 15+
- **Node.js**: 20+ (for assets)

## Setup

1. **Install Dependencies**:

    ```bash
    mix deps.get
    cd assets && npm install
    ```

2. **Database Setup**:

    ```bash
    mix ecto.setup
    ```

    *Note*: This runs migrations for `devices`, `telemetry_events`, `alert_rules`, `alerts`, `pending_commands`, `system_settings`, and `custom_reports`.

3. **Start Server**:

    ```bash
    mix phx.server
    ```

    Access Dashboard at `http://localhost:4000`.

## API Usage

### 1. Register a Device

**Endpoint**: `POST /api/v1/devices/register`

```bash
curl -X POST http://localhost:4000/api/v1/devices/register \
  -H "Content-Type: application/json" \
  -d '{
    "mac_address": "AA:BB:CC:DD:EE:01",
    "product_name": "sensor-v1",
    "firmware_version": "1.0.0",
    "schema_definition": {
      "type": "object",
      "properties": {
        "temp": {"type": "number"},
        "humidity": {"type": "number"}
      }
    },
    "metadata": {"location": "warehouse-1"}
  }'
```

**Response**:

```json
{
  "data": {
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "approval_status": "pending"
  }
}
```

### 2. Approve Device (Admin UI)

Navigate to `http://localhost:4000/devices/approvals` and click "Approve" for the new device.

### 3. Send Heartbeat & Telemetry

**Endpoint**: `POST /api/v1/devices/:device_id/heartbeat`

```bash
DEVICE_ID="YOUR_DEVICE_ID"
curl -X POST http://localhost:4000/api/v1/devices/$DEVICE_ID/heartbeat \
  -H "Content-Type: application/json" \
  -d '{
    "temp": 55.5,
    "humidity": 60
  }'
```

**Response** (includes pending commands):

```json
{
  "data": {
    "status": "ok",
    "commands": []
  }
}
```

## UI Features

### Alert Rules

1. Go to **Alerts > Rules** (`/alerts/rules`).
2. Create a new rule:
   - **Product Name**: `sensor-v1`
   - **JSON Path**: `temp`
   - **Operator**: `>`
   - **Threshold**: `50`
3. Send a heartbeat with `temp: 51`.
4. Check **Alerts Dashboard** (`/alerts`) to see the triggered alert.

### Custom Reports

1. Go to **Reports** (`/reports`).
2. Click **Create Report**.
3. Add fields to extract from JSON:
   - **Path**: `temp`, **Alias**: `Temperature`
   - **Path**: `humidity`, **Alias**: `Humidity`
4. Add filters (optional):
   - **Field**: `temp`, **Operator**: `>`, **Value**: `20`
5. Save and View.

## Testing

- **Run all tests**: `mix test`
- **Run Integration Suite**: `mix test test/nixstasis_web`
