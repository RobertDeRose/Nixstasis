# shellcheck shell=bash
# shellcheck disable=SC1091

SOURCE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")" # Script's directory
source "${SOURCE_DIR}/_logging.sh"

CONFIG_DIR="/etc/nixstasis"
ID_FILE="${CONFIG_DIR}/id"

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

#########################################
# Get Device MAC address
#
# Output:
#   str  - The MAC Address of eth0
#########################################
function get_mac_address() {
  cat /sys/class/net/eth0/address
}

#########################################
# Get Device standardized remote access name
#
# Output:
#   str  - A unique name for the device
#########################################
function get_name() {
  echo "atom-$(get_mac_address | tr -d ':' | tr '[:upper:]' '[:lower:]')"
}

#########################################
# Set Device registration id
#
# Input:
#   id: uuid  - The id returned during registration
# Returns:
#   0 - If ID was saved successfully
#   _ - The system error that caused the failure
#########################################
function set_id() {
  [ ! -e "${CONFIG_DIR}" ] && mkdir -p "${CONFIG_DIR}"

  echo "$1" > "$ID_FILE"
}

#########################################
# Get Device registration id
#
# Output:
#   id: uuid  - The id returned during registration
# Returns:
#   0 - If API request was successful
#   1 - Otherwise
#########################################
function get_id() {
  if [ ! -e "${ID_FILE}" ]; then
    log_fatal "Device registration file is missing"
    return 1
  fi

  ID="$(cat "${CONFIG_DIR}/id")"
  if [[ -z ${ID} ]]; then
    log_fatal "Device registration id is missing"
    return 2
  fi

  echo "$ID"
}

#########################################
# Convert JSON to an Bash Associative Array format
#
# Example:
#   declare -A test="( $( json_outputting_command | json2aa))"
#########################################
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
# Output:
#   JSON with keys:
#   - id
#   - mac_address
#   - ip_address
#   - account
#   - store
#   - door
#   - software_version
#   - firmware_version
#   - remote_access_token
#   - remote_access_requested
#   - remote_connection_string
#   - status
#   - last_seen
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
# Output:
#   JSON with keys:
#   - id
#   - mac_address
#   - ip_address
#   - account
#   - store
#   - door
#   - software_version
#   - firmware_version
#   - remote_access_token
#   - remote_access_requested
#   - remote_connection_string
#   - status
#   - last_seen
#########################################
function poll_nixstasis() {
  local id="$1"
  local data="$2"
  _post "device/${id}/poll" "${data}"
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
# Create a DeviceUpdate Object
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
# Create a DeviceConnection Object
#
# Use this when only updating remote access data
#
# Arguments:
#   remote_connection_string: str   - The URI needed to access the device remotely
#   remote_access_token: str        - The security token needed to access the devices remote configurstion screen
# Outputs:
#   json string ready for use with `poll_nixstasis`
#########################################
function DeviceConnection() {
  jq -rn \
    --arg remote_connection_string "$1" \
    --arg remote_access_token "$2" \
    '
  def nullIfEmpty(arg): if arg == "" then null else arg end;
  {
    remote_access_token: nullIfEmpty($remote_access_token),
    remote_connection_string: nullIfEmpty($remote_connection_string)
  }'
}

#########################################
# Create a Reader Object
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
