# shellcheck shell=bash
# shellcheck disable=SC1091

SOURCE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")" # Script's directory
source "${SOURCE_DIR}/_logging.sh"

API_URL="https://nixstasis.device.<domain>/api/v1"
HEADERS=(
  -H 'accept: application/json'
  -H 'Content-Type: application/json'
)

function _post() {
  local endpoint="$1"
  local payload="$2"

  curl -q -X POST "${API_URL}/${endpoint}" "${HEADERS[@]}" -d "${payload}" 2> /dev/null
}

function json2aa() {
  cat - | jq -r 'to_entries[] | "[\(.key)]=\"\(.value)\""'
}

#########################################
# Register a Device with Nixstasis
#
# Arguments:
#   data: json  - The DeviceCreate object
# Returns:
#   0 - If API request was successful
#   1 - Otherwise
# Output Environment:
#   RESPONSE[id]
#   RESPONSE[mac_address]
#   RESPONSE[ip_address]
#   RESPONSE[account]
#   RESPONSE[store]
#   RESPONSE[door]
#   RESPONSE[software_version]
#   RESPONSE[firmware_version]
#   RESPONSE[remote_access_token]
#   RESPONSE[remote_access_requested]
#   RESPONSE[remote_connection_string]
#   RESPONSE[status]
#   RESPONSE[last_seen]
#########################################
function register_device() {
  local payload="$1"
  _post "device/register" "${payload}"
}

#########################################
# Poll Nixstasis with updated device Data
#
# Arguments:
#   id: uuid    - The id return by Nixstasis after registering the device
#   data: json  - The DeviceCreate object
# Returns:
#   0 - If API request was successful
#   1 - Otherwise
# Output Environment:
#   RESPONSE[id]
#   RESPONSE[mac_address]
#   RESPONSE[ip_address]
#   RESPONSE[account]
#   RESPONSE[store]
#   RESPONSE[door]
#   RESPONSE[software_version]
#   RESPONSE[firmware_version]
#   RESPONSE[remote_access_token]
#   RESPONSE[remote_access_requested]
#   RESPONSE[remote_connection_string]
#   RESPONSE[status]
#   RESPONSE[last_seen]
#########################################
function poll_nixstasis() {
  local id="$1"
  local data="$2"
  _post "device/poll/${id}" "${data}"
}

#########################################
# Create a DeviceCreate Object
#
# Arguments:
#   mac_address: str  - The device's MAC address
#   ip_address: str   - The device's IPv4 address
# Outputs:
#   json string ready for use with `register_device`
#########################################
function DeviceCreate() {
  jq -n \
    --arg mac_address "$1" \
    --arg ip_address "$2" \
    '{
    mac_address: $mac_address,
    ip_address: $ip_address
  }'
}

#########################################
# Create a DeviceCreate Object
#
# Arguments:
#   account: int                    - The account number the device is associated with
#   store: str                      - The store number where the device is located
#   door: str                       - The door where the device is installed
#   software_version: str           - The software version running on the device
#   firmware_version: str           - The expected firmware version to be running on all attached readers
#   remote_access_token: str        - The security token needed to access the devices remote configurstion screen
#   remote_connection_string: str   - The URI needed to access the device remotely
# Outputs:
#   json string ready for use with `poll_nixstasis`
#########################################
function DeviceUpdate() {
  jq -rn \
    --argjson account "${1:-null}" \
    --arg store "$2" \
    --arg door "$3" \
    --arg software_version "$4" \
    --arg firmware_version "$5" \
    --arg remote_access_token "$6" \
    --arg remote_connection_string "$7" \
    '
  def nullIfEmpty(arg): if arg == "" then null else arg end;
  {
    account: nullIfEmpty($account),
    store: nullIfEmpty($store),
    door: nullIfEmpty($door),
    software_version: nullIfEmpty($software_version),
    firmware_version: nullIfEmpty($firmware_version),
    remote_access_token: nullIfEmpty($remote_access_token),
    remote_connection_string: nullIfEmpty($remote_connection_string)
  }'
}

#########################################
# Create a DeviceCreate Object
#
# Arguments:
#   serial_number: str  - The serial number of the reader
#   position: str       - The position of the reader in the aisle
#   profile: str        - The profile the reader is running
#   tx_band: str        - The TX Bands the reader is operating at
#   region: str         - The region the reader is configured to operate
#   model: str          - The reader model, either 1500, 1550, or 2000
#   version: str        - The firmware version running on the reader
#   status": enum       - The state of the reader either online or offline,
#   finalized: bool     - Is the reader fully provisioned and tuned to operate
#   inventory: bool     - Is the reader current reading tags or not
# Outputs:
#   json string ready for use with `poll_nixstasis`
#########################################
function Reader() {
  jq -n \
    --arg serial_number "$1" \
    --arg position "$2" \
    --arg profile "$3" \
    --arg tx_band "$4" \
    --arg region "$5" \
    --arg model "$6" \
    --arg version "$7" \
    --arg status "$8" \
    --argjson finalized "${9:-null}" \
    --argjson inventory "${10:-null}" \
    '{
    serial_number: $serial_number,
    position: $position,
    profile: $profile,
    tx_band: $tx_band,
    region: $region,
    model: $model,
    version: $version,
    status: $status,
    finalized: $finalized,
    inventory: $inventory
  }'
}
