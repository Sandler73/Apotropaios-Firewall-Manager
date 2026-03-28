#!/usr/bin/env bash
# ==============================================================================
# File:         lib/core/errors.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Error handling framework with trap handlers and graceful recovery
# Description:  Provides comprehensive error handling including signal traps,
#               cleanup orchestration, retry logic, graceful degradation, and
#               error context tracking. Implements idempotent cleanup handlers
#               per Bash Lesson #11 and proper exit code preservation.
# Notes:        - Requires lib/core/constants.sh and lib/core/logging.sh
#               - Trap handlers are idempotent (safe to call multiple times)
#               - Cleanup functions are registered and executed in LIFO order
#               - All arithmetic under set -e uses || true (Bash Lesson #1)
# Version:      1.1.5
# ==============================================================================

# Prevent double-sourcing
[[ -n "${_APOTROPAIOS_ERRORS_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_ERRORS_LOADED=1

# ==============================================================================
# Error State Variables
# ==============================================================================

# Stack of registered cleanup functions (LIFO execution order)
declare -a _CLEANUP_STACK=()

# Flag to prevent recursive cleanup
_CLEANUP_IN_PROGRESS=0

# Last error context (for detailed reporting)
_LAST_ERROR_FUNCTION=""
_LAST_ERROR_LINE=""
_LAST_ERROR_COMMAND=""

# ==============================================================================
# error_init()
# Description:  Initialize the error handling subsystem. Registers signal
#               traps for EXIT, SIGTERM, SIGINT, SIGHUP, and ERR.
# Parameters:   None
# Returns:      0 on success
# ==============================================================================
error_init() {
    # Register trap handlers
    # EXIT fires on normal exit, set -e exits, and signal-triggered exits
    trap '_error_exit_handler' EXIT
    trap '_error_signal_handler SIGTERM' SIGTERM
    trap '_error_signal_handler SIGINT' SIGINT
    trap '_error_signal_handler SIGHUP' SIGHUP

    # ERR trap for tracking error context (bash 4.0+)
    trap '_error_err_handler "${FUNCNAME[0]:-main}" "${LINENO}" "${BASH_COMMAND}"' ERR

    log_debug "errors" "Error handling initialized with signal traps"
    return "${E_SUCCESS}"
}

# ==============================================================================
# error_register_cleanup()
# Description:  Register a cleanup function to be called on exit/signal.
#               Functions are executed in LIFO (last registered, first called)
#               order during cleanup. Functions must be idempotent.
# Parameters:   $1 - Function name or command string to execute
# Returns:      0 on success
# ==============================================================================
error_register_cleanup() {
    local cleanup_func="${1:?error_register_cleanup requires a function name}"
    _CLEANUP_STACK+=("${cleanup_func}")
    log_trace "errors" "Cleanup function registered: ${cleanup_func} (stack depth: ${#_CLEANUP_STACK[@]})"
    return "${E_SUCCESS}"
}

# ==============================================================================
# error_unregister_cleanup()
# Description:  Remove a previously registered cleanup function.
# Parameters:   $1 - Function name to remove
# Returns:      0 on success, 1 if not found
# ==============================================================================
error_unregister_cleanup() {
    local cleanup_func="${1:?error_unregister_cleanup requires a function name}"
    local -a new_stack=()
    local found=0

    for item in "${_CLEANUP_STACK[@]}"; do
        if [[ "${item}" == "${cleanup_func}" ]] && [[ "${found}" -eq 0 ]]; then
            found=1
            continue
        fi
        new_stack+=("${item}")
    done

    _CLEANUP_STACK=("${new_stack[@]}")

    if [[ "${found}" -eq 1 ]]; then
        log_trace "errors" "Cleanup function unregistered: ${cleanup_func}"
        return 0
    fi
    return 1
}

# ==============================================================================
# _error_exit_handler() [INTERNAL]
# Description:  EXIT trap handler. Preserves exit code, executes cleanup
#               stack in LIFO order, then exits with original code.
# ==============================================================================
_error_exit_handler() {
    local exit_code=$?

    # Prevent recursive cleanup
    if [[ "${_CLEANUP_IN_PROGRESS}" -eq 1 ]]; then
        return
    fi
    _CLEANUP_IN_PROGRESS=1

    # Execute cleanup stack in reverse order (LIFO)
    local stack_size="${#_CLEANUP_STACK[@]}"
    if [[ "${stack_size}" -gt 0 ]]; then
        log_debug "errors" "Executing ${stack_size} cleanup handlers (exit_code=${exit_code})"

        local i
        for ((i = stack_size - 1; i >= 0; i--)); do
            local func="${_CLEANUP_STACK[${i}]}"
            log_trace "errors" "Executing cleanup: ${func}"
            # Execute each cleanup function, suppress errors
            eval "${func}" 2>/dev/null || {
                log_warning "errors" "Cleanup function failed: ${func}"
            }
        done
    fi

    # Shutdown logging last
    log_debug "errors" "Exit handler complete (exit_code=${exit_code})"

    _CLEANUP_IN_PROGRESS=0
    exit "${exit_code}"
}

# ==============================================================================
# _error_signal_handler() [INTERNAL]
# Description:  Signal trap handler. Logs the received signal, then triggers
#               exit which will fire the EXIT handler for cleanup.
# Parameters:   $1 - Signal name (e.g., SIGTERM)
# ==============================================================================
_error_signal_handler() {
    local signal="${1:-UNKNOWN}"
    log_warning "errors" "Signal received: ${signal}" "pid=$$"

    # For SIGINT, provide user feedback
    if [[ "${signal}" == "SIGINT" ]]; then
        printf '\n%bInterrupt received. Cleaning up...%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}" >&2
    fi

    # Exit with signal-specific code (128 + signal number)
    case "${signal}" in
        SIGTERM) exit 143 ;;
        SIGINT)  exit 130 ;;
        SIGHUP)  exit 129 ;;
        *)       exit "${E_SIGNAL_RECEIVED}" ;;
    esac
}

# ==============================================================================
# _error_err_handler() [INTERNAL]
# Description:  ERR trap handler. Records error context for debugging.
#               Does not exit — set -e handles that.
# Parameters:   $1 - Function name, $2 - Line number, $3 - Failed command
# ==============================================================================
_error_err_handler() {
    _LAST_ERROR_FUNCTION="${1:-unknown}"
    _LAST_ERROR_LINE="${2:-0}"
    _LAST_ERROR_COMMAND="${3:-unknown}"
    # Only log at trace level to avoid noise from expected failures
    log_trace "errors" "ERR trapped: func=${_LAST_ERROR_FUNCTION} line=${_LAST_ERROR_LINE} cmd=${_LAST_ERROR_COMMAND}"
}

# ==============================================================================
# error_get_context()
# Description:  Return the last error context as a formatted string.
# Returns:      Error context string via stdout
# ==============================================================================
error_get_context() {
    printf 'function=%s line=%s command=%s' \
        "${_LAST_ERROR_FUNCTION:-unknown}" \
        "${_LAST_ERROR_LINE:-0}" \
        "${_LAST_ERROR_COMMAND:-unknown}"
}

# ==============================================================================
# error_retry()
# Description:  Execute a command with retry logic and exponential backoff.
#               Retries on non-zero exit code up to max_retries times.
# Parameters:   $1 - Max retries (integer)
#               $2 - Initial delay in seconds
#               $3+ - Command and arguments to execute
# Returns:      Exit code of the last attempt
# ==============================================================================
error_retry() {
    local max_retries="${1:?error_retry requires max_retries}"
    local delay="${2:?error_retry requires initial delay}"
    shift 2

    local attempt=0
    local rc=0

    while [[ "${attempt}" -lt "${max_retries}" ]]; do
        ((attempt++)) || true

        log_debug "errors" "Retry attempt ${attempt}/${max_retries}: $*"

        # Execute the command
        if "$@"; then
            log_debug "errors" "Retry succeeded on attempt ${attempt}"
            return "${E_SUCCESS}"
        fi
        rc=$?

        if [[ "${attempt}" -lt "${max_retries}" ]]; then
            log_warning "errors" "Attempt ${attempt} failed (rc=${rc}), retrying in ${delay}s"
            sleep "${delay}" 2>/dev/null || true
            # Exponential backoff (cap at 60 seconds)
            local new_delay
            new_delay=$((delay * 2))
            if [[ "${new_delay}" -gt 60 ]]; then
                delay=60
            else
                delay="${new_delay}"
            fi
        fi
    done

    log_error "errors" "All ${max_retries} retry attempts failed for: $*"
    return "${rc}"
}

# ==============================================================================
# error_with_fallback()
# Description:  Execute a primary command. If it fails, execute a fallback.
# Parameters:   $1 - Primary command string
#               $2 - Fallback command string
#               $3 - Context description for logging
# Returns:      0 if either succeeds, last failure code otherwise
# ==============================================================================
error_with_fallback() {
    local primary="${1:?error_with_fallback requires primary command}"
    local fallback="${2:?error_with_fallback requires fallback command}"
    local context="${3:-operation}"

    log_debug "errors" "Executing primary: ${context}"
    if eval "${primary}" 2>/dev/null; then
        return "${E_SUCCESS}"
    fi

    local primary_rc=$?
    log_warning "errors" "Primary failed (rc=${primary_rc}), executing fallback: ${context}"

    if eval "${fallback}" 2>/dev/null; then
        log_info "errors" "Fallback succeeded: ${context}"
        return "${E_SUCCESS}"
    fi

    local fallback_rc=$?
    log_error "errors" "Both primary and fallback failed: ${context} (primary_rc=${primary_rc}, fallback_rc=${fallback_rc})"
    return "${fallback_rc}"
}

# ==============================================================================
# error_die()
# Description:  Log a critical error and exit immediately.
# Parameters:   $1 - Error message
#               $2 - Exit code (optional, default: E_GENERAL)
#               $3 - Context (optional)
# Returns:      Does not return (calls exit)
# ==============================================================================
error_die() {
    local message="${1:?error_die requires a message}"
    local exit_code="${2:-${E_GENERAL}}"
    local context="${3:-fatal}"

    log_critical "${context}" "${message}" "exit_code=${exit_code}"
    exit "${exit_code}"
}

# ==============================================================================
# error_assert()
# Description:  Assert a condition is true. If false, log and return error.
# Parameters:   $1 - Condition description
#               $2+ - Command to evaluate
# Returns:      0 if condition is true, 1 if false
# ==============================================================================
error_assert() {
    local description="${1:?error_assert requires description}"
    shift

    if ! "$@" 2>/dev/null; then
        log_error "assert" "Assertion failed: ${description}"
        return 1
    fi
    return 0
}

# ==============================================================================
# error_safe_exec()
# Description:  Execute a command capturing its exit code without triggering
#               set -e. Useful for commands where non-zero is expected/valid.
# Parameters:   $1 - Variable name to store exit code
#               $2+ - Command and arguments
# Returns:      Always 0 (exit code stored in named variable)
# ==============================================================================
error_safe_exec() {
    local -n _rc_var="${1:?error_safe_exec requires variable name}"
    shift
    "$@" && _rc_var=0 || _rc_var=$?
    return 0
}
