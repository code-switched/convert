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

  # Determine whether to use colors
  local use_color="false"
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    use_color="true"
  fi

  local color reset
  if [ "$use_color" = "true" ]; then
    reset='\033[0m'
    case "$level" in
      ERROR) color='\033[31m' ;;
      WARN)  color='\033[33m' ;;
      INFO)  color='\033[36m' ;;
      DEBUG) color='\033[90m' ;;
      *)     color='\033[0m'  ;;
    esac
  else
    color=''
    reset=''
  fi

  # Console
  printf "%b\n" "${color}${msg}${reset}"

  # File
  if [ -n "${LOG_FILE:-}" ]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "${now} [${level}] ${msg}" >> "$LOG_FILE"
  fi
}


