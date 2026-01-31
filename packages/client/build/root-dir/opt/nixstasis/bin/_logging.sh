# shellcheck shell=bash
# shellcheck disable=SC1090,SC1091,SC2034
[[ ${BASH_SOURCE[0]} != "${0}" ]] && [[ "${_LOGGING_LOADED}" ]] && return

RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PURPLE='\033[0;35m'
DEFAULT='\033[0;39m'

_log() { echo -e "${!1}${*:2}${DEFAULT}" >&2; }
log_info() { _log "CYAN" " INFO | ${*}"; }
log_warn() { _log "YELLOW" " WARN | ${*}"; }
log_fatal() { _log "RED" "ERROR | ${*}"; }

_LOGGING_LOADED=1
