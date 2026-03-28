#!/usr/bin/env bash
# ==============================================================================
# File:         lib/core/logging.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Structured logging framework with file and console output
# Description:  Provides enterprise-grade logging with structured format,
#               multiple log levels, dual output (console + file), log file
#               rotation awareness, file handle tracking, and correlation ID
#               support. Implements NIST SP 800-92 and OWASP logging best
#               practices. Supports runtime log level adjustment via --log-level.
# Notes:        - Requires lib/core/constants.sh to be sourced first
#               - Log files are written with restricted permissions (600)
#               - File descriptor tracking prevents handle loss
#               - All sensitive data is masked before logging
#               - Thread-safe via atomic writes to log files
# Version:      1.1.5
# ==============================================================================

# Prevent double-sourcing
[[ -n "${_APOTROPAIOS_LOGGING_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_LOGGING_LOADED=1

# ==============================================================================
# Logging State Variables
# ==============================================================================

# Current log level (mutable — can be changed at runtime via --log-level)
APOTROPAIOS_LOG_LEVEL="${DEFAULT_LOG_LEVEL:-2}"

# Log file path (set by log_init)
APOTROPAIOS_LOG_FILE=""

# Log file descriptor (tracked to prevent handle loss)
APOTROPAIOS_LOG_FD=""

# Flag indicating if logging is initialized
APOTROPAIOS_LOG_INITIALIZED=0

# Correlation ID for current execution context
APOTROPAIOS_LOG_CORRELATION_ID=""

# Counter for log entries (overflow protection)
APOTROPAIOS_LOG_ENTRY_COUNT=0

# ==============================================================================
# log_init()
# Description:  Initialize the logging subsystem. Creates log directory,
#               generates timestamped log file, opens file descriptor,
#               and validates write capability.
# Parameters:   $1 - Base log directory (required)
#               $2 - Log level (optional, default: from config)
# Returns:      0 on success, E_LOG_FAIL on failure
# ==============================================================================
log_init() {
    local log_dir="${1:?log_init requires log directory}"
    local log_level="${2:-${APOTROPAIOS_LOG_LEVEL}}"
    local timestamp
    local log_file

    # Validate log directory path — WHITELIST approach (more secure + portable)
    # Reject path traversal
    if [[ "${log_dir}" == *".."* ]]; then
        printf '[CRITICAL] [logging] Invalid log directory path: directory traversal detected (%s)\n' "${log_dir}" >&2
        return "${E_LOG_FAIL}"
    fi

    # Reject paths with dangerous characters via whitelist
    if [[ ! "${log_dir}" =~ ${PATTERN_SAFE_DIR} ]]; then
        printf '[CRITICAL] [logging] Invalid log directory path: contains unsafe characters (%s)\n' "${log_dir}" >&2
        printf '[CRITICAL] [logging] Path must contain only: a-z A-Z 0-9 / _ . ~ : + - space\n' >&2
        return "${E_LOG_FAIL}"
    fi

    # Create log directory with secure permissions
    if ! mkdir -p "${log_dir}" 2>/dev/null; then
        printf '[CRITICAL] [logging] Failed to create log directory: %s\n' "${log_dir}" >&2
        return "${E_LOG_FAIL}"
    fi
    chmod "${SECURE_DIR_PERMS}" "${log_dir}" 2>/dev/null || true

    # Generate timestamped log filename
    timestamp="$(date -u '+%Y-%m-%dT%H-%M-%S' 2>/dev/null)" || timestamp="unknown"
    log_file="${log_dir}/apotropaios-${timestamp}.log"

    # Create log file with secure permissions
    if ! touch "${log_file}" 2>/dev/null; then
        printf '[CRITICAL] [logging] Failed to create log file: %s\n' "${log_file}" >&2
        return "${E_LOG_FAIL}"
    fi
    chmod "${SECURE_FILE_PERMS}" "${log_file}" 2>/dev/null || true

    # Open file descriptor for logging (use FD 3)
    # Close existing FD if open
    if [[ -n "${APOTROPAIOS_LOG_FD}" ]]; then
        exec 3>&- 2>/dev/null || true
    fi

    APOTROPAIOS_LOG_FD=3
    if ! exec 3>>"${log_file}" 2>/dev/null; then
        printf '[CRITICAL] [logging] Failed to open log file descriptor: %s\n' "${log_file}" >&2
        return "${E_LOG_FAIL}"
    fi

    # Set state
    APOTROPAIOS_LOG_FILE="${log_file}"
    APOTROPAIOS_LOG_LEVEL="${log_level}"
    APOTROPAIOS_LOG_INITIALIZED=1
    APOTROPAIOS_LOG_ENTRY_COUNT=0

    # Generate execution correlation ID
    APOTROPAIOS_LOG_CORRELATION_ID="$(log_generate_correlation_id)"

    # Write initialization marker
    _log_write "${LOG_LEVEL_INFO}" "logging" \
        "Logging initialized: file=${log_file} level=${LOG_LEVEL_NAMES[${log_level}]:-UNKNOWN} correlation_id=${APOTROPAIOS_LOG_CORRELATION_ID}"

    return "${E_SUCCESS}"
}

# ==============================================================================
# log_shutdown()
# Description:  Cleanly shut down the logging subsystem. Flushes and closes
#               the log file descriptor.
# Parameters:   None
# Returns:      0 on success
# ==============================================================================
log_shutdown() {
    if [[ "${APOTROPAIOS_LOG_INITIALIZED}" -eq 1 ]]; then
        _log_write "${LOG_LEVEL_INFO}" "logging" \
            "Logging shutdown: entries_written=${APOTROPAIOS_LOG_ENTRY_COUNT}"

        # Close file descriptor
        if [[ -n "${APOTROPAIOS_LOG_FD}" ]]; then
            exec 3>&- 2>/dev/null || true
        fi

        APOTROPAIOS_LOG_INITIALIZED=0
        APOTROPAIOS_LOG_FD=""
    fi
    return "${E_SUCCESS}"
}

# ==============================================================================
# log_set_level()
# Description:  Change the runtime log level.
# Parameters:   $1 - Log level (name or number)
# Returns:      0 on success, 1 on invalid level
# ==============================================================================
log_set_level() {
    local level_input="${1:?log_set_level requires a level}"
    local level_num

    # Accept both numeric and string levels
    if [[ "${level_input}" =~ ^[0-9]+$ ]]; then
        level_num="${level_input}"
    else
        level_num="${LOG_LEVEL_NUMBERS[${level_input}]:-}"
    fi

    if [[ -z "${level_num}" ]]; then
        log_error "logging" "Invalid log level: ${level_input}"
        return 1
    fi

    local old_level="${APOTROPAIOS_LOG_LEVEL}"
    APOTROPAIOS_LOG_LEVEL="${level_num}"

    _log_write "${LOG_LEVEL_INFO}" "logging" \
        "Log level changed: ${LOG_LEVEL_NAMES[${old_level}]:-${old_level}} -> ${LOG_LEVEL_NAMES[${level_num}]:-${level_num}}"

    return "${E_SUCCESS}"
}

# ==============================================================================
# Primary Logging Functions
# Each wraps _log_write with the appropriate level constant.
# Parameters:   $1 - Context/module name
#               $2 - Message
#               $3 - Additional context (optional)
# ==============================================================================

log_trace() {
    _log_write "${LOG_LEVEL_TRACE}" "$@"
}

log_debug() {
    _log_write "${LOG_LEVEL_DEBUG}" "$@"
}

log_info() {
    _log_write "${LOG_LEVEL_INFO}" "$@"
}

log_warning() {
    _log_write "${LOG_LEVEL_WARNING}" "$@"
}

log_error() {
    _log_write "${LOG_LEVEL_ERROR}" "$@"
}

log_critical() {
    _log_write "${LOG_LEVEL_CRITICAL}" "$@"
}

# ==============================================================================
# _log_write() [INTERNAL]
# Description:  Core log writing function. Formats structured log entry and
#               writes to both file and console (respecting log level filter).
#               Performs file handle validation before each write.
# Parameters:   $1 - Log level (numeric)
#               $2 - Context/module name
#               $3 - Message
#               $4 - Additional structured context (optional)
# Returns:      0 on success, E_LOG_HANDLE_LOST if file handle is lost
# ==============================================================================
_log_write() {
    local level="${1:?_log_write requires level}"
    local context="${2:?_log_write requires context}"
    local message="${3:-}"
    local extra_context="${4:-}"

    # Level filtering — skip if below current threshold
    if [[ "${level}" -lt "${APOTROPAIOS_LOG_LEVEL}" ]]; then
        return 0
    fi

    # Sanitize message — remove control characters, mask sensitive patterns
    message="$(_log_sanitize_message "${message}")"

    # Build structured log line
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null)" || \
        timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || \
        timestamp="UNKNOWN"

    local level_name="${LOG_LEVEL_NAMES[${level}]:-LVL${level}}"
    local corr_id="${APOTROPAIOS_LOG_CORRELATION_ID:-none}"
    local log_line

    if [[ -n "${extra_context}" ]]; then
        log_line="[${timestamp}] [${level_name}] [${context}] [cid:${corr_id}] ${message} | ${extra_context}"
    else
        log_line="[${timestamp}] [${level_name}] [${context}] [cid:${corr_id}] ${message}"
    fi

    # Write to log file (if initialized and handle valid)
    if [[ "${APOTROPAIOS_LOG_INITIALIZED}" -eq 1 ]]; then
        if ! _log_verify_handle; then
            # Attempt handle recovery
            if ! _log_recover_handle; then
                printf '%s\n' "${log_line}" >&2
                return "${E_LOG_HANDLE_LOST}"
            fi
        fi

        # Check file size before writing (rotation awareness)
        _log_check_size

        # Atomic write to file descriptor
        printf '%s\n' "${log_line}" >&"${APOTROPAIOS_LOG_FD}" 2>/dev/null || {
            printf '[CRITICAL] [logging] Write to log file failed, falling back to stderr\n' >&2
            printf '%s\n' "${log_line}" >&2
        }

        # Increment counter with overflow protection
        ((APOTROPAIOS_LOG_ENTRY_COUNT++)) || true
    fi

    # Write to console (with color, respecting level)
    _log_console "${level}" "${level_name}" "${context}" "${message}"

    return 0
}

# ==============================================================================
# _log_console() [INTERNAL]
# Description:  Write formatted, colorized log entry to console (stderr).
#               Only writes if log level meets threshold.
# Parameters:   $1 - Level (numeric), $2 - Level name, $3 - Context, $4 - Message
# ==============================================================================
_log_console() {
    local level="$1"
    local level_name="$2"
    local context="$3"
    local message="$4"
    local color=""

    # Select color based on level
    case "${level}" in
        "${LOG_LEVEL_TRACE}")    color="${COLOR_DIM}" ;;
        "${LOG_LEVEL_DEBUG}")    color="${COLOR_CYAN}" ;;
        "${LOG_LEVEL_INFO}")     color="${COLOR_GREEN}" ;;
        "${LOG_LEVEL_WARNING}")  color="${COLOR_YELLOW}" ;;
        "${LOG_LEVEL_ERROR}")    color="${COLOR_RED}" ;;
        "${LOG_LEVEL_CRITICAL}") color="${COLOR_BOLD}${COLOR_RED}" ;;
    esac

    # Write to stderr so it doesn't interfere with stdout data
    printf '%b[%-8s] [%s] %s%b\n' \
        "${color}" "${level_name}" "${context}" "${message}" "${COLOR_RESET}" >&2
}

# ==============================================================================
# _log_verify_handle() [INTERNAL]
# Description:  Verify that the log file descriptor is still valid and writable.
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
_log_verify_handle() {
    # Check FD is set
    [[ -z "${APOTROPAIOS_LOG_FD}" ]] && return 1

    # Check FD is open (test write with empty string)
    if ! printf '' >&"${APOTROPAIOS_LOG_FD}" 2>/dev/null; then
        return 1
    fi

    # Check log file still exists on disk
    if [[ -n "${APOTROPAIOS_LOG_FILE}" ]] && [[ ! -f "${APOTROPAIOS_LOG_FILE}" ]]; then
        return 1
    fi

    return 0
}

# ==============================================================================
# _log_recover_handle() [INTERNAL]
# Description:  Attempt to recover a lost log file handle by reopening the
#               log file or creating a new one.
# Returns:      0 on recovery success, 1 on failure
# ==============================================================================
_log_recover_handle() {
    local log_file="${APOTROPAIOS_LOG_FILE}"

    # If original file is gone, create a new one
    if [[ ! -f "${log_file}" ]]; then
        local log_dir
        log_dir="$(dirname "${log_file}" 2>/dev/null)" || return 1
        local timestamp
        timestamp="$(date -u '+%Y-%m-%dT%H-%M-%S' 2>/dev/null)" || timestamp="recovery"
        log_file="${log_dir}/apotropaios-${timestamp}-recovered.log"
    fi

    # Attempt to recreate file and reopen FD
    if touch "${log_file}" 2>/dev/null; then
        chmod "${SECURE_FILE_PERMS}" "${log_file}" 2>/dev/null || true
        if exec 3>>"${log_file}" 2>/dev/null; then
            APOTROPAIOS_LOG_FILE="${log_file}"
            printf '[WARNING] [logging] Log handle recovered: %s\n' "${log_file}" >&2
            return 0
        fi
    fi

    printf '[CRITICAL] [logging] Log handle recovery failed\n' >&2
    return 1
}

# ==============================================================================
# _log_check_size() [INTERNAL]
# Description:  Check if the current log file exceeds maximum size.
#               If so, rotate to a new file. Retains up to MAX_LOG_FILES_RETAINED.
# ==============================================================================
_log_check_size() {
    [[ -z "${APOTROPAIOS_LOG_FILE}" ]] && return

    local file_size=0
    if [[ -f "${APOTROPAIOS_LOG_FILE}" ]]; then
        file_size="$(stat -c%s "${APOTROPAIOS_LOG_FILE}" 2>/dev/null)" || \
            file_size="$(wc -c < "${APOTROPAIOS_LOG_FILE}" 2>/dev/null)" || \
            file_size=0
    fi

    if [[ "${file_size}" -gt "${MAX_LOG_FILE_SIZE_BYTES}" ]]; then
        _log_rotate
    fi
}

# ==============================================================================
# _log_rotate() [INTERNAL]
# Description:  Rotate the current log file by closing the current FD,
#               renaming the file, and opening a new log file.
# ==============================================================================
_log_rotate() {
    local log_dir
    log_dir="$(dirname "${APOTROPAIOS_LOG_FILE}" 2>/dev/null)" || return

    # Close current FD
    exec 3>&- 2>/dev/null || true

    # Rename with rotation suffix
    local rotated_name="${APOTROPAIOS_LOG_FILE}.$(date -u '+%s' 2>/dev/null).rotated"
    mv "${APOTROPAIOS_LOG_FILE}" "${rotated_name}" 2>/dev/null || true

    # Clean up old rotated files (keep MAX_LOG_FILES_RETAINED)
    local old_files
    old_files="$(find "${log_dir}" -name "apotropaios-*.log*" -type f 2>/dev/null | sort | head -n -"${MAX_LOG_FILES_RETAINED}" 2>/dev/null)" || true
    if [[ -n "${old_files}" ]]; then
        while IFS= read -r old_file; do
            rm -f "${old_file}" 2>/dev/null || true
        done <<< "${old_files}"
    fi

    # Open new log file
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H-%M-%S' 2>/dev/null)" || timestamp="rotated"
    APOTROPAIOS_LOG_FILE="${log_dir}/apotropaios-${timestamp}.log"
    touch "${APOTROPAIOS_LOG_FILE}" 2>/dev/null || true
    chmod "${SECURE_FILE_PERMS}" "${APOTROPAIOS_LOG_FILE}" 2>/dev/null || true
    exec 3>>"${APOTROPAIOS_LOG_FILE}" 2>/dev/null || true

    printf '[INFO] [logging] Log rotated to: %s\n' "${APOTROPAIOS_LOG_FILE}" >&2
}

# ==============================================================================
# _log_sanitize_message() [INTERNAL]
# Description:  Remove control characters and mask sensitive patterns from log
#               messages. Covers key=value, JSON, HTTP headers, and URL-encoded
#               formats. Defense-in-depth: called on every log write.
# Parameters:   $1 - Raw message string
# Returns:      Sanitized message via stdout
# ==============================================================================
_log_sanitize_message() {
    local msg="${1:-}"

    # Remove ASCII control characters (except newline, tab)
    msg="$(printf '%s' "${msg}" | tr -d '\000-\010\013\014\016-\037' 2>/dev/null)" || true

    # Mask key=value patterns (most common in bash logging)
    # Matches: password=xxx, token=xxx, key=xxx, secret=xxx, apikey=xxx, api_key=xxx
    msg="$(printf '%s' "${msg}" | sed -E \
        -e 's/(password|passwd|secret|token|key|apikey|api_key|api_secret|access_key|private_key)=[^ ]*/\1=***MASKED***/gi' \
        2>/dev/null)" || true

    # Mask key="quoted value" patterns (multi-word secrets)
    msg="$(printf '%s' "${msg}" | sed -E \
        -e 's/(password|passwd|secret|token|key|apikey|api_key)="[^"]*"/\1="***MASKED***"/gi' \
        -e "s/(password|passwd|secret|token|key|apikey|api_key)='[^']*'/\1='***MASKED***'/gi" \
        2>/dev/null)" || true

    # Mask JSON patterns: "password": "value" or "token": "value"
    msg="$(printf '%s' "${msg}" | sed -E \
        -e 's/"(password|passwd|secret|token|key|apikey|api_key|api_secret|access_key)"[[:space:]]*:[[:space:]]*"[^"]*"/"\1": "***MASKED***"/gi' \
        2>/dev/null)" || true

    # Mask HTTP Authorization headers: Authorization: Bearer xxx / Basic xxx
    msg="$(printf '%s' "${msg}" | sed -E \
        -e 's/(Authorization)[[:space:]]*:[[:space:]]*(Bearer|Basic|Digest|Token)[[:space:]]+[^ ]*/\1: \2 ***MASKED***/gi' \
        2>/dev/null)" || true

    printf '%s' "${msg}"
}

# ==============================================================================
# log_generate_correlation_id()
# Description:  Generate a unique correlation ID for the current execution.
#               Uses /dev/urandom for cryptographic randomness.
# Returns:      Correlation ID string via stdout
# ==============================================================================
log_generate_correlation_id() {
    local cid=""

    # Attempt /dev/urandom (preferred — cryptographically random)
    if [[ -r /dev/urandom ]]; then
        cid="$(head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n' 2>/dev/null)" || true
    fi

    # Fallback: PID + timestamp + RANDOM
    if [[ -z "${cid}" ]] || [[ "${#cid}" -lt 8 ]]; then
        cid="$(printf '%05d%010d%05d' "$$" "$(date +%s 2>/dev/null || echo 0)" "${RANDOM:-0}" 2>/dev/null)" || cid="fallback-$$"
    fi

    printf '%s' "${cid}"
}

# ==============================================================================
# log_get_file()
# Description:  Return the current log file path.
# Returns:      Log file path via stdout
# ==============================================================================
log_get_file() {
    printf '%s' "${APOTROPAIOS_LOG_FILE}"
}

# ==============================================================================
# log_get_level()
# Description:  Return the current log level name.
# Returns:      Log level name via stdout
# ==============================================================================
log_get_level() {
    printf '%s' "${LOG_LEVEL_NAMES[${APOTROPAIOS_LOG_LEVEL}]:-UNKNOWN}"
}

# ==============================================================================
# log_get_entry_count()
# Description:  Return the number of log entries written in this session.
# Returns:      Entry count via stdout
# ==============================================================================
log_get_entry_count() {
    printf '%d' "${APOTROPAIOS_LOG_ENTRY_COUNT}"
}
