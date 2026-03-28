#!/usr/bin/env bash
# ==============================================================================
# File:         lib/core/utils.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Common utility functions and performance helpers
# Description:  Provides shared helper functions used across the framework
#               including string manipulation, array operations, timestamp
#               generation, file operations, and performance measurement.
# Notes:        - Requires lib/core/constants.sh, logging.sh
#               - All functions are pure where possible (Bash Lesson #16)
#               - No external dependencies
# Version:      1.1.5
# ==============================================================================

# Prevent double-sourcing
[[ -n "${_APOTROPAIOS_UTILS_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_UTILS_LOADED=1

# ==============================================================================
# util_timestamp()
# Description:  Generate an ISO 8601 UTC timestamp.
# Returns:      Timestamp string on stdout
# ==============================================================================
util_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf 'UNKNOWN'
}

# ==============================================================================
# util_timestamp_epoch()
# Description:  Return current time as Unix epoch seconds.
# Returns:      Epoch seconds on stdout
# ==============================================================================
util_timestamp_epoch() {
    date '+%s' 2>/dev/null || printf '0'
}

# ==============================================================================
# util_timestamp_filename()
# Description:  Generate a filename-safe timestamp.
# Returns:      Timestamp string (no colons) on stdout
# ==============================================================================
util_timestamp_filename() {
    date -u '+%Y-%m-%dT%H-%M-%S' 2>/dev/null || printf 'unknown'
}

# ==============================================================================
# util_to_lower()
# Description:  Convert string to lowercase.
# Parameters:   $1 - Input string
# Returns:      Lowercase string on stdout
# ==============================================================================
util_to_lower() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

# ==============================================================================
# util_to_upper()
# Description:  Convert string to uppercase.
# Parameters:   $1 - Input string
# Returns:      Uppercase string on stdout
# ==============================================================================
util_to_upper() {
    printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]'
}

# ==============================================================================
# util_trim()
# Description:  Trim leading and trailing whitespace.
# Parameters:   $1 - Input string
# Returns:      Trimmed string on stdout
# ==============================================================================
util_trim() {
    local str="${1:-}"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    printf '%s' "${str}"
}

# ==============================================================================
# util_is_command_available()
# Description:  Check if a command exists on the system.
# Parameters:   $1 - Command name
# Returns:      0 if available, 1 if not
# ==============================================================================
util_is_command_available() {
    command -v "${1:-}" &>/dev/null
}

# ==============================================================================
# util_require_command()
# Description:  Assert that a command is available. Log error if not.
# Parameters:   $1 - Command name
#               $2 - Context/reason (optional)
# Returns:      0 if available, 1 if not
# ==============================================================================
util_require_command() {
    local cmd="${1:?util_require_command requires command name}"
    local context="${2:-}"

    if ! util_is_command_available "${cmd}"; then
        log_error "utils" "Required command not found: ${cmd}" "${context:+context=${context}}"
        return 1
    fi
    return 0
}

# ==============================================================================
# util_array_contains()
# Description:  Check if an array contains a specific value.
# Parameters:   $1 - Value to search for
#               $2+ - Array elements
# Returns:      0 if found, 1 if not
# ==============================================================================
util_array_contains() {
    local needle="${1:?util_array_contains requires a value}"
    shift
    local item
    for item in "$@"; do
        [[ "${item}" == "${needle}" ]] && return 0
    done
    return 1
}

# ==============================================================================
# util_array_index()
# Description:  Find the index of a value in an array.
# Parameters:   $1 - Value to search for
#               $2+ - Array elements
# Returns:      0 and index on stdout if found, 1 if not
# ==============================================================================
util_array_index() {
    local needle="${1:?util_array_index requires a value}"
    shift
    local i=0
    local item
    for item in "$@"; do
        if [[ "${item}" == "${needle}" ]]; then
            printf '%d' "${i}"
            return 0
        fi
        ((i++)) || true
    done
    return 1
}

# ==============================================================================
# util_confirm()
# Description:  Prompt user for yes/no confirmation.
# Parameters:   $1 - Prompt message
#               $2 - Default (y/n, optional, default: n)
# Returns:      0 if confirmed (yes), 1 if denied (no)
# ==============================================================================
util_confirm() {
    local message="${1:?util_confirm requires a message}"
    local default="${2:-n}"
    local prompt reply

    if [[ "${default}" == "y" ]]; then
        prompt="${message} [Y/n]: "
    else
        prompt="${message} [y/N]: "
    fi

    # Read from terminal directly (not stdin pipe)
    printf '%b%s%b' "${COLOR_YELLOW}" "${prompt}" "${COLOR_RESET}" >&2
    read -r reply </dev/tty 2>/dev/null || reply="${default}"

    reply="$(util_to_lower "${reply}")"

    case "${reply}" in
        y|yes) return 0 ;;
        n|no)  return 1 ;;
        "")
            [[ "${default}" == "y" ]] && return 0
            return 1
            ;;
        *)     return 1 ;;
    esac
}

# ==============================================================================
# util_file_age_seconds()
# Description:  Calculate the age of a file in seconds.
# Parameters:   $1 - File path
# Returns:      Age in seconds on stdout, or -1 if file doesn't exist
# ==============================================================================
util_file_age_seconds() {
    local file="${1:?util_file_age_seconds requires file path}"

    [[ ! -f "${file}" ]] && { printf '%d' -1; return 1; }

    local file_mtime now age
    file_mtime="$(stat -c %Y "${file}" 2>/dev/null)" || \
        file_mtime="$(stat -f %m "${file}" 2>/dev/null)" || \
        { printf '%d' -1; return 1; }

    now="$(util_timestamp_epoch)"
    age=$((now - file_mtime))
    printf '%d' "${age}"
    return 0
}

# ==============================================================================
# util_human_duration()
# Description:  Convert seconds to human-readable duration string.
# Parameters:   $1 - Duration in seconds
# Returns:      Human-readable string on stdout (e.g., "2h 15m 30s")
# ==============================================================================
util_human_duration() {
    local seconds="${1:-0}"
    local days hours minutes

    days=$((seconds / 86400))
    seconds=$((seconds % 86400))
    hours=$((seconds / 3600))
    seconds=$((seconds % 3600))
    minutes=$((seconds / 60))
    seconds=$((seconds % 60))

    local result=""
    [[ "${days}" -gt 0 ]] && result="${days}d "
    [[ "${hours}" -gt 0 ]] && result="${result}${hours}h "
    [[ "${minutes}" -gt 0 ]] && result="${result}${minutes}m "
    result="${result}${seconds}s"

    printf '%s' "${result}"
}

# ==============================================================================
# util_human_bytes()
# Description:  Convert bytes to human-readable size string.
# Parameters:   $1 - Size in bytes
# Returns:      Human-readable string on stdout (e.g., "1.5 MB")
# ==============================================================================
util_human_bytes() {
    local bytes="${1:-0}"

    if [[ "${bytes}" -ge 1073741824 ]]; then
        printf '%.1f GB' "$(echo "scale=1; ${bytes}/1073741824" | bc 2>/dev/null || echo 0)"
    elif [[ "${bytes}" -ge 1048576 ]]; then
        printf '%.1f MB' "$(echo "scale=1; ${bytes}/1048576" | bc 2>/dev/null || echo 0)"
    elif [[ "${bytes}" -ge 1024 ]]; then
        printf '%.1f KB' "$(echo "scale=1; ${bytes}/1024" | bc 2>/dev/null || echo 0)"
    else
        printf '%d B' "${bytes}"
    fi
}

# ==============================================================================
# util_parallel_exec()
# Description:  Execute multiple commands in parallel with a concurrency limit.
#               Uses background jobs with wait for synchronization.
# Parameters:   $1 - Max concurrent jobs
#               $2+ - Commands to execute (one per argument)
# Returns:      0 if all succeed, 1 if any fail
# ==============================================================================
util_parallel_exec() {
    local max_jobs="${1:?util_parallel_exec requires max jobs}"
    shift

    local -a pids=()
    local cmd
    local overall_rc=0
    local running=0

    for cmd in "$@"; do
        # Wait if at max concurrency
        while [[ "${running}" -ge "${max_jobs}" ]]; do
            wait -n 2>/dev/null || true
            ((running--)) || true
        done

        # Launch in background
        eval "${cmd}" &
        pids+=($!)
        ((running++)) || true
    done

    # Wait for all remaining jobs
    local pid
    for pid in "${pids[@]}"; do
        wait "${pid}" 2>/dev/null || overall_rc=1
    done

    return "${overall_rc}"
}

# ==============================================================================
# util_print_banner()
# Description:  Print the Apotropaios banner/header.
# ==============================================================================
util_print_banner() {
    printf '%b' "${COLOR_CYAN}"
    cat << 'BANNER'
    _                _                         _
   / \   _ __   ___ | |_ _ __ ___  _ __   __ _(_) ___  ___
  / _ \ | '_ \ / _ \| __| '__/ _ \| '_ \ / _` | |/ _ \/ __|
 / ___ \| |_) | (_) | |_| | | (_) | |_) | (_| | | (_) \__ \
/_/   \_\ .__/ \___/ \__|_|  \___/| .__/ \__,_|_|\___/|___/
        |_|                       |_|
BANNER
    printf '%b        Firewall Manager v%s%b\n\n' "${COLOR_BOLD}" "${APOTROPAIOS_VERSION}" "${COLOR_RESET}"
}

# ==============================================================================
# util_print_separator()
# Description:  Print a visual separator line.
# Parameters:   $1 - Character to use (default: ─)
#               $2 - Width (default: 72)
# ==============================================================================
util_print_separator() {
    local char="${1:-─}"
    local width="${2:-72}"
    local i
    printf '%b' "${COLOR_DIM}"
    for ((i = 0; i < width; i++)); do
        printf '%s' "${char}"
    done
    printf '%b\n' "${COLOR_RESET}"
}

# ==============================================================================
# util_print_kv()
# Description:  Print a key-value pair with aligned formatting.
# Parameters:   $1 - Key
#               $2 - Value
#               $3 - Key width (optional, default: 20)
# ==============================================================================
util_print_kv() {
    local key="${1:-}"
    local value="${2:-}"
    local width="${3:-20}"
    printf '  %b%-*s%b : %s\n' "${COLOR_BOLD}" "${width}" "${key}" "${COLOR_RESET}" "${value}"
}

# ==============================================================================
# util_read_kv_file()
# Description:  Read a key=value file into an associative array.
#               Skips comments (#) and empty lines.
# Parameters:   $1 - File path
#               $2 - Associative array name (nameref)
# Returns:      0 on success, 1 on failure
# ==============================================================================
util_read_kv_file() {
    local file="${1:?util_read_kv_file requires file path}"
    local -n _target_array="${2:?util_read_kv_file requires array name}"

    [[ ! -f "${file}" ]] && {
        log_error "utils" "KV file not found: ${file}"
        return 1
    }

    local line key value
    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Skip comments and empty lines
        [[ -z "${line}" ]] && continue
        [[ "${line}" == "#"* ]] && continue

        # Extract key=value
        key="${line%%=*}"
        value="${line#*=}"

        # Trim whitespace
        key="$(util_trim "${key}")"
        value="$(util_trim "${value}")"

        [[ -n "${key}" ]] && _target_array["${key}"]="${value}"
    done < "${file}"

    return 0
}

# ==============================================================================
# util_write_kv_file()
# Description:  Write an associative array to a key=value file.
# Parameters:   $1 - File path
#               $2 - Associative array name (nameref)
#               $3 - Header comment (optional)
# Returns:      0 on success
# ==============================================================================
util_write_kv_file() {
    local file="${1:?util_write_kv_file requires file path}"
    local -n _source_array="${2:?util_write_kv_file requires array name}"
    local header="${3:-}"

    {
        [[ -n "${header}" ]] && printf '# %s\n' "${header}"
        printf '# Generated: %s\n\n' "$(util_timestamp)"

        local key
        for key in "${!_source_array[@]}"; do
            printf '%s=%s\n' "${key}" "${_source_array[${key}]}"
        done
    } > "${file}" 2>/dev/null || {
        log_error "utils" "Failed to write KV file: ${file}"
        return 1
    }

    chmod "${SECURE_FILE_PERMS}" "${file}" 2>/dev/null || true
    return 0
}
