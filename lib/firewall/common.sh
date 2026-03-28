#!/usr/bin/env bash
# ==============================================================================
# File:         lib/firewall/common.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Common firewall interface and dispatch layer
# Description:  Provides a unified interface for firewall operations. Routes
#               calls to the appropriate backend (firewalld, ipset, iptables,
#               nftables, ufw) based on the selected or detected firewall.
#               Implements the adapter pattern for consistent API access.
# Notes:        - Requires detection modules to be loaded and run first
#               - Each backend implements the same function signature set
#               - All operations validate firewall availability before dispatch
# Version:      1.1.5
# ==============================================================================

# Prevent double-sourcing
[[ -n "${_APOTROPAIOS_FW_COMMON_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_FW_COMMON_LOADED=1

# ==============================================================================
# State Variables
# ==============================================================================

# Currently selected firewall backend
FW_ACTIVE_BACKEND=""

# ==============================================================================
# fw_set_backend()
# Description:  Set the active firewall backend for operations.
# Parameters:   $1 - Firewall name (must be installed)
# Returns:      0 on success, E_FW_NOT_FOUND if not installed
# ==============================================================================
fw_set_backend() {
    local fw_name="${1:?fw_set_backend requires firewall name}"

    # Validate it's a known firewall
    if ! util_array_contains "${fw_name}" "${SUPPORTED_FW_LIST[@]}"; then
        log_error "fw_common" "Unknown firewall backend: ${fw_name}"
        return "${E_FW_NOT_FOUND}"
    fi

    # Validate it's installed
    if ! fw_is_installed "${fw_name}"; then
        log_error "fw_common" "Firewall not installed: ${fw_name}"
        return "${E_FW_NOT_FOUND}"
    fi

    FW_ACTIVE_BACKEND="${fw_name}"
    log_info "fw_common" "Active firewall backend set to: ${fw_name}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_get_backend()
# Description:  Return the currently active firewall backend name.
# Returns:      Backend name on stdout
# ==============================================================================
fw_get_backend() {
    printf '%s' "${FW_ACTIVE_BACKEND}"
}

# ==============================================================================
# _fw_require_backend() [INTERNAL]
# Description:  Assert that a backend is selected and available.
# Returns:      0 if ready, 1 if not
# ==============================================================================
_fw_require_backend() {
    if [[ -z "${FW_ACTIVE_BACKEND}" ]]; then
        log_error "fw_common" "No firewall backend selected. Call fw_set_backend first."
        return 1
    fi
    return 0
}

# ==============================================================================
# fw_dispatch()
# Description:  Dispatch a firewall operation to the active backend.
#               Routes to the backend-specific function: fw_<backend>_<operation>
# Parameters:   $1 - Operation name (e.g., "add_rule", "remove_rule")
#               $2+ - Operation arguments
# Returns:      Return code from the backend function
# ==============================================================================
fw_dispatch() {
    local operation="${1:?fw_dispatch requires operation name}"
    shift

    _fw_require_backend || return 1

    local func_name="fw_${FW_ACTIVE_BACKEND}_${operation}"

    # Verify the backend function exists
    if ! declare -f "${func_name}" &>/dev/null; then
        log_error "fw_common" "Backend function not found: ${func_name}"
        return "${E_GENERAL}"
    fi

    log_debug "fw_common" "Dispatching: ${func_name} $*"
    "${func_name}" "$@"
}

# ==============================================================================
# Unified Firewall Operations (delegate to active backend)
# ==============================================================================

# Add a firewall rule
fw_add_rule() {
    fw_dispatch "add_rule" "$@"
}

# Remove a firewall rule
fw_remove_rule() {
    fw_dispatch "remove_rule" "$@"
}

# List current rules
fw_list_rules() {
    fw_dispatch "list_rules" "$@"
}

# Enable/start the firewall
fw_enable() {
    fw_dispatch "enable" "$@"
}

# Disable/stop the firewall
fw_disable() {
    fw_dispatch "disable" "$@"
}

# Get firewall status
fw_status() {
    fw_dispatch "status" "$@"
}

# Block all traffic (inbound and outbound)
fw_block_all() {
    fw_dispatch "block_all" "$@"
}

# Allow all traffic (inbound and outbound)
fw_allow_all() {
    fw_dispatch "allow_all" "$@"
}

# Reset firewall to default configuration
fw_reset() {
    fw_dispatch "reset" "$@"
}

# Save current configuration
fw_save() {
    fw_dispatch "save" "$@"
}

# Reload configuration from saved state
fw_reload() {
    fw_dispatch "reload" "$@"
}

# Export current configuration to text
fw_export_config() {
    fw_dispatch "export_config" "$@"
}

# ==============================================================================
# fw_exec_with_backend()
# Description:  Execute a function with a specific backend, temporarily
#               switching from the current one. Restores original backend after.
# Parameters:   $1 - Backend name to use
#               $2 - Function to call
#               $3+ - Function arguments
# Returns:      Return code from the function
# ==============================================================================
fw_exec_with_backend() {
    local target_backend="${1:?requires backend name}"
    local func="${2:?requires function name}"
    shift 2

    local original_backend="${FW_ACTIVE_BACKEND}"
    local rc

    fw_set_backend "${target_backend}" || return $?
    "${func}" "$@" && rc=0 || rc=$?

    # Restore original backend
    if [[ -n "${original_backend}" ]]; then
        FW_ACTIVE_BACKEND="${original_backend}"
    fi

    return "${rc}"
}
