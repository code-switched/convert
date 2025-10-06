#!/bin/bash

# Common logging for bash tools
# Usage in a tool script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/../common/log.sh"
#   LOG_FILE="${SCRIPT_DIR}/logs/tool.log"   # optional; if unset, only console
#   LOG_LEVEL="INFO"                          # optional; default DEBUG
#   log INFO "message"

_log_level_value() {
  case "$1" in
    DEBUG) echo 10 ;;
    INFO)  echo 20 ;;
    WARN)  echo 30 ;;
    ERROR) echo 40 ;;
    *)     echo 10 ;; # default DEBUG
  esac
}

log() {
  local level="$1"; shift
  local msg="$*"
  local now
  now="$(date '+%Y-%m-%d %H:%M:%S')"

  local want="${LOG_LEVEL:-DEBUG}"
  if [ "$(_log_level_value "$level")" -lt "$(_log_level_value "$want")" ]; then
    return 0
  fi

  local color reset
  reset='\e[0m'
  case "$level" in
    ERROR) color='\e[31m' ;;
    WARN)  color='\e[33m' ;;
    INFO)  color='\e[36m' ;;
    DEBUG) color='\e[90m' ;;
    *)     color='\e[0m'  ;;
  esac

  # Console
  echo -e "${color}${msg}${reset}"

  # File
  if [ -n "${LOG_FILE:-}" ]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "${now} [${level}] ${msg}" >> "$LOG_FILE"
  fi
}


