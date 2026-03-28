#!/usr/bin/env bash
# ==============================================================================
# File:         lib/core/security.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Security controls, memory management, and integrity verification
# Description:  Provides security infrastructure including secure temporary file
#               creation, privilege checks, file integrity verification via
#               checksums, lock file management for concurrency control, secure
#               memory handling (variable scrubbing), and umask enforcement.
# Notes:        - Requires lib/core/constants.sh, logging.sh, errors.sh
#               - All temporary files created in secure temp directory
#               - Lock files use advisory locking with timeout
#               - Sensitive variables are scrubbed on cleanup
# Version:      1.1.5
# ==============================================================================

# Prevent double-sourcing
[[ -n "${_APOTROPAIOS_SECURITY_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_SECURITY_LOADED=1

# ==============================================================================
# Security State Variables
# ==============================================================================

# Track sensitive variables for scrubbing on exit
declare -a _SENSITIVE_VARS=()

# Track temporary files/dirs for cleanup
declare -a _SECURE_TEMP_FILES=()

# Lock file descriptor
_LOCK_FD=""

# ==============================================================================
# security_init()
# Description:  Initialize security subsystem. Sets umask, validates execution
#               environment, creates secure temp directory.
# Parameters:   $1 - Base directory for secure temp files
# Returns:      0 on success
# ==============================================================================
security_init() {
    local base_dir="${1:?security_init requires base directory}"

    # Set restrictive umask
    umask "${SECURE_UMASK}"
    log_debug "security" "Umask set to ${SECURE_UMASK}"

    # Validate bash version (security — ensure modern features available)
    local bash_major="${BASH_VERSINFO[0]:-0}"
    local bash_minor="${BASH_VERSINFO[1]:-0}"
    if [[ "${bash_major}" -lt 4 ]]; then
        log_critical "security" "Bash version ${BASH_VERSION} is too old. Minimum required: ${APOTROPAIOS_MIN_BASH_VERSION}"
        return "${E_GENERAL}"
    fi

    # Create secure temp directory
    local temp_dir="${base_dir}/${APOTROPAIOS_TEMP_DIR_REL}"
    if ! mkdir -p "${temp_dir}" 2>/dev/null; then
        log_error "security" "Failed to create secure temp directory: ${temp_dir}"
        return "${E_GENERAL}"
    fi
    chmod "${SECURE_DIR_PERMS}" "${temp_dir}" 2>/dev/null || true

    # Register cleanup for temp files
    error_register_cleanup "_security_cleanup"

    log_info "security" "Security subsystem initialized"
    return "${E_SUCCESS}"
}

# ==============================================================================
# security_check_root()
# Description:  Check if the script is running with root privileges.
# Returns:      0 if root, E_PERMISSION if not
# ==============================================================================
security_check_root() {
    if [[ "$(id -u 2>/dev/null)" -ne 0 ]]; then
        log_error "security" "Root privileges required. Current UID: $(id -u 2>/dev/null)"
        return "${E_PERMISSION}"
    fi
    log_debug "security" "Root privilege check passed"
    return "${E_SUCCESS}"
}

# ==============================================================================
# security_check_not_root()
# Description:  Verify the script is NOT running as root (for non-root tasks).
# Returns:      0 if not root, 1 if root
# ==============================================================================
security_check_not_root() {
    if [[ "$(id -u 2>/dev/null)" -eq 0 ]]; then
        log_warning "security" "Running as root is not recommended for this operation"
        return 1
    fi
    return 0
}

# ==============================================================================
# security_create_temp_file()
# Description:  Create a secure temporary file with restrictive permissions.
# Parameters:   $1 - Prefix for the temp file name (optional)
# Returns:      0 on success, temp file path on stdout
# ==============================================================================
security_create_temp_file() {
    local prefix="${1:-apotropaios}"
    local temp_file

    temp_file="$(mktemp "/tmp/${prefix}.XXXXXXXXXX" 2>/dev/null)" || {
        log_error "security" "Failed to create temporary file"
        return "${E_GENERAL}"
    }

    chmod "${SECURE_FILE_PERMS}" "${temp_file}" 2>/dev/null || true

    # Track for cleanup
    _SECURE_TEMP_FILES+=("${temp_file}")

    printf '%s' "${temp_file}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# security_create_temp_dir()
# Description:  Create a secure temporary directory with restrictive permissions.
# Parameters:   $1 - Prefix for the temp dir name (optional)
# Returns:      0 on success, temp dir path on stdout
# ==============================================================================
security_create_temp_dir() {
    local prefix="${1:-apotropaios}"
    local temp_dir

    temp_dir="$(mktemp -d "/tmp/${prefix}.XXXXXXXXXX" 2>/dev/null)" || {
        log_error "security" "Failed to create temporary directory"
        return "${E_GENERAL}"
    }

    chmod "${SECURE_DIR_PERMS}" "${temp_dir}" 2>/dev/null || true

    # Track for cleanup
    _SECURE_TEMP_FILES+=("${temp_dir}")

    printf '%s' "${temp_dir}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# security_register_sensitive_var()
# Description:  Register a variable name for secure scrubbing on cleanup.
# Parameters:   $1 - Variable name (without $)
# ==============================================================================
security_register_sensitive_var() {
    local var_name="${1:?security_register_sensitive_var requires variable name}"
    _SENSITIVE_VARS+=("${var_name}")
    log_trace "security" "Sensitive variable registered for scrubbing: ${var_name}"
}

# ==============================================================================
# security_scrub_vars()
# Description:  Overwrite all registered sensitive variables with empty strings
#               then unset them. Defense against memory inspection.
# ==============================================================================
security_scrub_vars() {
    local var_name
    for var_name in "${_SENSITIVE_VARS[@]}"; do
        # Overwrite with random data first, then empty, then unset
        if [[ -n "${!var_name+x}" ]]; then
            eval "${var_name}='XXXXXXXXXXXXXXXXXXXXXXXX'" 2>/dev/null || true
            eval "${var_name}=''" 2>/dev/null || true
            unset "${var_name}" 2>/dev/null || true
        fi
    done
    _SENSITIVE_VARS=()
    log_trace "security" "Sensitive variables scrubbed"
}

# ==============================================================================
# security_file_checksum()
# Description:  Generate a SHA-256 checksum of a file.
# Parameters:   $1 - File path
# Returns:      0 on success, checksum on stdout
# ==============================================================================
security_file_checksum() {
    local file="${1:?security_file_checksum requires file path}"

    [[ ! -f "${file}" ]] && {
        log_error "security" "Cannot checksum: file not found: ${file}"
        return "${E_GENERAL}"
    }

    local checksum
    # Try sha256sum first, then shasum as fallback
    if command -v sha256sum &>/dev/null; then
        checksum="$(sha256sum "${file}" 2>/dev/null | cut -d' ' -f1)"
    elif command -v shasum &>/dev/null; then
        checksum="$(shasum -a 256 "${file}" 2>/dev/null | cut -d' ' -f1)"
    else
        # Last resort: use openssl
        if command -v openssl &>/dev/null; then
            checksum="$(openssl dgst -sha256 "${file}" 2>/dev/null | awk '{print $NF}')"
        else
            log_error "security" "No SHA-256 utility available"
            return "${E_GENERAL}"
        fi
    fi

    if [[ -z "${checksum}" ]]; then
        log_error "security" "Failed to generate checksum for: ${file}"
        return "${E_GENERAL}"
    fi

    printf '%s' "${checksum}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# security_verify_checksum()
# Description:  Verify a file's integrity against a known checksum.
# Parameters:   $1 - File path
#               $2 - Expected checksum
# Returns:      0 if match, E_INTEGRITY_FAIL if mismatch
# ==============================================================================
security_verify_checksum() {
    local file="${1:?security_verify_checksum requires file path}"
    local expected="${2:?security_verify_checksum requires expected checksum}"
    local actual

    actual="$(security_file_checksum "${file}")" || return "${E_INTEGRITY_FAIL}"

    if [[ "${actual}" != "${expected}" ]]; then
        log_error "security" "Checksum mismatch for ${file}: expected=${expected} actual=${actual}"
        return "${E_INTEGRITY_FAIL}"
    fi

    log_debug "security" "Checksum verified for ${file}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# security_acquire_lock()
# Description:  Acquire an advisory lock. Uses flock(1) when available for
#               atomic, race-condition-free locking. Falls back to noclobber
#               file creation with PID validation for stale lock detection.
# Parameters:   $1 - Lock file path
#               $2 - Timeout in seconds (optional, default: LOCK_TIMEOUT_SECONDS)
# Returns:      0 on success, E_LOCK_FAIL or E_LOCK_TIMEOUT on failure
# ==============================================================================

# File descriptor used for flock (module-level, not per-call)
_FLOCK_FD=""

security_acquire_lock() {
    local lock_file="${1:?security_acquire_lock requires lock file path}"
    local timeout="${2:-${LOCK_TIMEOUT_SECONDS}}"

    # Preferred: use flock(1) for atomic locking (no TOCTOU race)
    if command -v flock &>/dev/null; then
        # Open the lock file on FD 9 for flock
        exec 9>>"${lock_file}" 2>/dev/null || {
            log_error "security" "Cannot open lock file for flock: ${lock_file}"
            return "${E_LOCK_FAIL}"
        }
        if flock -w "${timeout}" 9 2>/dev/null; then
            # Write our PID for identification
            printf '%s' "$$" > "${lock_file}" 2>/dev/null || true
            chmod "${SECURE_FILE_PERMS}" "${lock_file}" 2>/dev/null || true
            _LOCK_FD="${lock_file}"
            _FLOCK_FD=9
            log_debug "security" "Lock acquired (flock): ${lock_file}"
            return "${E_SUCCESS}"
        else
            exec 9>&- 2>/dev/null || true
            log_error "security" "flock timeout after ${timeout}s: ${lock_file}"
            return "${E_LOCK_TIMEOUT}"
        fi
    fi

    # Fallback: noclobber + PID check (has small TOCTOU window)
    log_debug "security" "flock not available, using noclobber fallback"
    local elapsed=0

    while [[ "${elapsed}" -lt "${timeout}" ]]; do
        # Try to create lock file atomically
        if (set -o noclobber; echo "$$" > "${lock_file}") 2>/dev/null; then
            chmod "${SECURE_FILE_PERMS}" "${lock_file}" 2>/dev/null || true
            _LOCK_FD="${lock_file}"
            _FLOCK_FD=""
            log_debug "security" "Lock acquired (noclobber): ${lock_file}"
            return "${E_SUCCESS}"
        fi

        # Check if the lock holder is still alive
        if [[ -f "${lock_file}" ]]; then
            local lock_pid
            lock_pid="$(cat "${lock_file}" 2>/dev/null)" || true
            if [[ -n "${lock_pid}" ]] && ! kill -0 "${lock_pid}" 2>/dev/null; then
                # Stale lock — remove and retry
                log_warning "security" "Removing stale lock file (PID ${lock_pid} is dead): ${lock_file}"
                rm -f "${lock_file}" 2>/dev/null || true
                continue
            fi
        fi

        sleep "${LOCK_RETRY_INTERVAL}" 2>/dev/null || true
        ((elapsed += LOCK_RETRY_INTERVAL)) || true
    done

    log_error "security" "Failed to acquire lock within ${timeout}s: ${lock_file}"
    return "${E_LOCK_TIMEOUT}"
}

# ==============================================================================
# security_release_lock()
# Description:  Release an advisory lock. Uses flock FD release when flock was
#               used, or file removal for noclobber-based locks.
# Parameters:   $1 - Lock file path (optional, uses last acquired if not given)
# Returns:      0 on success
# ==============================================================================
security_release_lock() {
    local lock_file="${1:-${_LOCK_FD}}"

    # Release flock FD if it was used
    if [[ -n "${_FLOCK_FD}" ]]; then
        exec 9>&- 2>/dev/null || true
        _FLOCK_FD=""
    fi

    if [[ -n "${lock_file}" ]] && [[ -f "${lock_file}" ]]; then
        # Verify we own the lock before removing
        local lock_pid
        lock_pid="$(cat "${lock_file}" 2>/dev/null)" || true
        if [[ "${lock_pid}" == "$$" ]]; then
            rm -f "${lock_file}" 2>/dev/null || true
            log_debug "security" "Lock released: ${lock_file}"
        else
            log_warning "security" "Lock file owned by different PID (${lock_pid}), not releasing"
        fi
    fi

    _LOCK_FD=""
    return "${E_SUCCESS}"
}

# ==============================================================================
# security_secure_dir()
# Description:  Ensure a directory exists with secure permissions.
# Parameters:   $1 - Directory path
# Returns:      0 on success
# ==============================================================================
security_secure_dir() {
    local dir="${1:?security_secure_dir requires directory path}"

    if ! mkdir -p "${dir}" 2>/dev/null; then
        log_error "security" "Failed to create directory: ${dir}"
        return "${E_GENERAL}"
    fi

    chmod "${SECURE_DIR_PERMS}" "${dir}" 2>/dev/null || {
        log_warning "security" "Failed to set permissions on: ${dir}"
    }

    return "${E_SUCCESS}"
}

# ==============================================================================
# security_secure_file()
# Description:  Set secure permissions on a file.
# Parameters:   $1 - File path
# Returns:      0 on success
# ==============================================================================
security_secure_file() {
    local file="${1:?security_secure_file requires file path}"

    [[ ! -f "${file}" ]] && {
        log_error "security" "File not found: ${file}"
        return "${E_GENERAL}"
    }

    chmod "${SECURE_FILE_PERMS}" "${file}" 2>/dev/null || {
        log_warning "security" "Failed to set permissions on: ${file}"
        return "${E_GENERAL}"
    }

    return "${E_SUCCESS}"
}

# ==============================================================================
# security_validate_binary()
# Description:  Validate that a binary exists and is executable. Prevents
#               execution of arbitrary paths.
# Parameters:   $1 - Binary name or path
# Returns:      0 if valid executable, 1 if not found/not executable
# ==============================================================================
security_validate_binary() {
    local binary="${1:?security_validate_binary requires binary name}"

    # If it's an absolute path, validate it directly
    if [[ "${binary}" == /* ]]; then
        if [[ -x "${binary}" ]] && [[ -f "${binary}" ]]; then
            return 0
        fi
        return 1
    fi

    # For command names, use command -v (POSIX-safe)
    if command -v "${binary}" &>/dev/null; then
        return 0
    fi

    return 1
}

# ==============================================================================
# _security_cleanup() [INTERNAL]
# Description:  Cleanup function registered with error_register_cleanup.
#               Scrubs sensitive variables and removes temp files.
# ==============================================================================
_security_cleanup() {
    # Scrub sensitive variables
    security_scrub_vars

    # Remove tracked temporary files/directories
    local temp_item
    for temp_item in "${_SECURE_TEMP_FILES[@]}"; do
        if [[ -e "${temp_item}" ]]; then
            rm -rf "${temp_item}" 2>/dev/null || true
        fi
    done
    _SECURE_TEMP_FILES=()

    # Release any held locks
    security_release_lock

    log_trace "security" "Security cleanup complete"
}

# ==============================================================================
# security_generate_uuid()
# Description:  Generate a UUID v4 using /dev/urandom. No external dependencies.
# Returns:      UUID string on stdout
# ==============================================================================
security_generate_uuid() {
    local uuid=""

    if [[ -r /dev/urandom ]]; then
        # Read 16 random bytes, format as UUID
        local hex
        hex="$(head -c 16 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n' 2>/dev/null)" || true

        if [[ "${#hex}" -ge 32 ]]; then
            # Set version (4) and variant (8, 9, a, or b)
            uuid="${hex:0:8}-${hex:8:4}-4${hex:13:3}-$(printf '%x' $(( (0x${hex:16:2} & 0x3f) | 0x80 )))${hex:18:2}-${hex:20:12}"
            printf '%s' "${uuid}"
            return 0
        fi
    fi

    # Fallback: construct from PID, time, RANDOM
    local part1 part2 part3 part4 part5
    part1="$(printf '%08x' "$$" 2>/dev/null)"
    part2="$(printf '%04x' "${RANDOM:-0}" 2>/dev/null)"
    part3="$(printf '4%03x' "$((RANDOM % 4096))" 2>/dev/null)"
    part4="$(printf '%04x' "$(( (RANDOM & 0x3fff) | 0x8000 ))" 2>/dev/null)"
    part5="$(printf '%012x' "$(date +%s%N 2>/dev/null | cut -c1-12)" 2>/dev/null)"

    printf '%s-%s-%s-%s-%s' "${part1}" "${part2}" "${part3}" "${part4}" "${part5}"
    return 0
}
