#!/usr/bin/env bash
# ==============================================================================
# File:         lib/detection/fw_detect.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Firewall application detection, version discovery, and status
# Description:  Detects installed firewall applications (firewalld, ipset,
#               iptables, nftables, ufw), retrieves their versions, and checks
#               their running status. Results are stored in associative arrays
#               for efficient lookup by other modules.
# Notes:        - Requires lib/core/constants.sh, logging.sh, utils.sh
#               - Detection is non-destructive (read-only operations)
#               - Results stored in global associative arrays (Bash Lesson #9)
#               - Version parsing handles varied output formats across distros
# Version:      1.1.5
# ==============================================================================

# Prevent double-sourcing
[[ -n "${_APOTROPAIOS_FW_DETECT_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_FW_DETECT_LOADED=1

# ==============================================================================
# Detection Result Variables (Global)
# ==============================================================================

# Associative arrays: keyed by firewall name (firewalld, ipset, iptables, nftables, ufw)
declare -A FW_DETECTED_INSTALLED=()   # 1 = installed, 0 = not found
declare -A FW_DETECTED_VERSION=()     # Version string or "unknown"
declare -A FW_DETECTED_BINARY=()      # Full path to binary
declare -A FW_DETECTED_RUNNING=()     # 1 = running/active, 0 = not running
declare -A FW_DETECTED_ENABLED=()     # 1 = enabled at boot, 0 = not enabled

# Count of detected firewalls
FW_DETECTED_COUNT=0

# ==============================================================================
# fw_detect_all()
# Description:  Detect all supported firewall applications.
# Returns:      0 on success (even if no firewalls found)
# ==============================================================================
fw_detect_all() {
    log_info "fw_detect" "Beginning firewall detection scan"
    FW_DETECTED_COUNT=0

    local fw_name fw_binary
    local i=0

    for fw_name in "${SUPPORTED_FW_LIST[@]}"; do
        fw_binary="${SUPPORTED_FW_BINARIES[${i}]}"
        _fw_detect_single "${fw_name}" "${fw_binary}"
        ((i++)) || true
    done

    log_info "fw_detect" "Firewall detection complete: ${FW_DETECTED_COUNT} firewall(s) found"
    return "${E_SUCCESS}"
}

# ==============================================================================
# _fw_detect_single() [INTERNAL]
# Description:  Detect a single firewall application.
# Parameters:   $1 - Firewall name (e.g., "firewalld")
#               $2 - Binary name (e.g., "firewall-cmd")
# ==============================================================================
_fw_detect_single() {
    local fw_name="${1:?_fw_detect_single requires firewall name}"
    local fw_binary="${2:?_fw_detect_single requires binary name}"

    log_debug "fw_detect" "Checking for ${fw_name} (binary: ${fw_binary})"

    # Check if binary exists
    local binary_path
    binary_path="$(command -v "${fw_binary}" 2>/dev/null)" || binary_path=""

    if [[ -z "${binary_path}" ]]; then
        FW_DETECTED_INSTALLED["${fw_name}"]=0
        FW_DETECTED_VERSION["${fw_name}"]=""
        FW_DETECTED_BINARY["${fw_name}"]=""
        FW_DETECTED_RUNNING["${fw_name}"]=0
        FW_DETECTED_ENABLED["${fw_name}"]=0
        log_debug "fw_detect" "${fw_name}: not installed"
        return
    fi

    FW_DETECTED_INSTALLED["${fw_name}"]=1
    FW_DETECTED_BINARY["${fw_name}"]="${binary_path}"
    ((FW_DETECTED_COUNT++)) || true

    # Get version
    local version
    version="$(_fw_get_version "${fw_name}" "${binary_path}")"
    FW_DETECTED_VERSION["${fw_name}"]="${version}"

    # Check running status
    local running
    running="$(_fw_check_running "${fw_name}")"
    FW_DETECTED_RUNNING["${fw_name}"]="${running}"

    # Check enabled at boot
    local enabled
    enabled="$(_fw_check_enabled "${fw_name}")"
    FW_DETECTED_ENABLED["${fw_name}"]="${enabled}"

    log_info "fw_detect" "${fw_name}: installed (v${version}) running=${running} enabled=${enabled} path=${binary_path}"
}

# ==============================================================================
# _fw_get_version() [INTERNAL]
# Description:  Extract version string from a firewall binary's output.
# Parameters:   $1 - Firewall name
#               $2 - Binary path
# Returns:      Version string on stdout
# ==============================================================================
_fw_get_version() {
    local fw_name="$1"
    local binary_path="$2"
    local version="unknown"
    local raw_output

    case "${fw_name}" in
        firewalld)
            # firewall-cmd --version outputs just the version number
            raw_output="$(timeout 5 "${binary_path}" --version 2>/dev/null)" || true
            version="$(printf '%s' "${raw_output}" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)" || true
            ;;
        ipset)
            # ipset --version outputs "ipset vX.Y.Z, protocol version: N"
            raw_output="$(timeout 5 "${binary_path}" --version 2>/dev/null)" || true
            version="$(printf '%s' "${raw_output}" | grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | sed 's/^v//')" || true
            ;;
        iptables)
            # iptables --version outputs "iptables vX.Y.Z (..."
            raw_output="$(timeout 5 "${binary_path}" --version 2>/dev/null)" || true
            version="$(printf '%s' "${raw_output}" | grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | sed 's/^v//')" || true
            ;;
        nftables)
            # nft --version outputs "nftables vX.Y.Z (..."
            raw_output="$(timeout 5 "${binary_path}" --version 2>/dev/null)" || true
            version="$(printf '%s' "${raw_output}" | grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | sed 's/^v//')" || true
            ;;
        ufw)
            # ufw --version or ufw version outputs "ufw X.Y.Z"
            raw_output="$(timeout 5 "${binary_path}" version 2>/dev/null)" || \
                raw_output="$(timeout 5 "${binary_path}" --version 2>/dev/null)" || true
            version="$(printf '%s' "${raw_output}" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)" || true
            ;;
    esac

    [[ -z "${version}" ]] && version="unknown"
    printf '%s' "${version}"
}

# ==============================================================================
# _fw_check_running() [INTERNAL]
# Description:  Check if a firewall service is currently running.
# Parameters:   $1 - Firewall name
# Returns:      "1" if running, "0" if not (on stdout)
# ==============================================================================
_fw_check_running() {
    local fw_name="$1"
    local running=0

    case "${fw_name}" in
        firewalld)
            if util_is_command_available systemctl; then
                systemctl is-active --quiet firewalld 2>/dev/null && running=1
            elif util_is_command_available firewall-cmd; then
                timeout 5 firewall-cmd --state 2>/dev/null | grep -qi "running" && running=1
            fi
            ;;
        ipset)
            # ipset doesn't have a service — it's a kernel module interface
            # Check if the kernel module is loaded
            if [[ -f /proc/net/ip_tables_matches ]] || lsmod 2>/dev/null | grep -q "ip_set"; then
                running=1
            fi
            # ipset is always "running" if installed (kernel-level tool)
            if [[ "${FW_DETECTED_INSTALLED[ipset]:-0}" -eq 1 ]]; then
                running=1
            fi
            ;;
        iptables)
            # iptables is kernel-level; check if module is loaded
            if [[ -f /proc/net/ip_tables_names ]]; then
                running=1
            elif util_is_command_available iptables; then
                timeout 5 iptables -L -n 2>/dev/null | head -1 | grep -qi "Chain" && running=1
            fi
            ;;
        nftables)
            if util_is_command_available systemctl; then
                systemctl is-active --quiet nftables 2>/dev/null && running=1
            elif util_is_command_available nft; then
                timeout 5 nft list ruleset 2>/dev/null | head -1 && running=1
            fi
            ;;
        ufw)
            if util_is_command_available ufw; then
                timeout 5 ufw status 2>/dev/null | grep -qi "Status: active" && running=1
            fi
            ;;
    esac

    printf '%d' "${running}"
}

# ==============================================================================
# _fw_check_enabled() [INTERNAL]
# Description:  Check if a firewall service is enabled at boot.
# Parameters:   $1 - Firewall name
# Returns:      "1" if enabled, "0" if not (on stdout)
# ==============================================================================
_fw_check_enabled() {
    local fw_name="$1"
    local enabled=0

    # Only relevant for services managed by systemctl
    local service_name="${SUPPORTED_FW_SERVICES[$(util_array_index "${fw_name}" "${SUPPORTED_FW_LIST[@]}" 2>/dev/null || echo 0)]:-}"

    if [[ -n "${service_name}" ]] && util_is_command_available systemctl; then
        systemctl is-enabled --quiet "${service_name}" 2>/dev/null && enabled=1
    fi

    printf '%d' "${enabled}"
}

# ==============================================================================
# fw_detect_single()
# Description:  Detect a specific firewall by name.
# Parameters:   $1 - Firewall name from SUPPORTED_FW_LIST
# Returns:      0 if found and installed, E_FW_NOT_FOUND if not
# ==============================================================================
fw_detect_single() {
    local fw_name="${1:?fw_detect_single requires firewall name}"

    # Find the matching binary
    local i=0 found=0
    local fw_binary=""
    for item in "${SUPPORTED_FW_LIST[@]}"; do
        if [[ "${item}" == "${fw_name}" ]]; then
            fw_binary="${SUPPORTED_FW_BINARIES[${i}]}"
            found=1
            break
        fi
        ((i++)) || true
    done

    [[ "${found}" -eq 0 ]] && {
        log_error "fw_detect" "Unknown firewall name: ${fw_name}"
        return "${E_FW_NOT_FOUND}"
    }

    _fw_detect_single "${fw_name}" "${fw_binary}"

    if [[ "${FW_DETECTED_INSTALLED[${fw_name}]:-0}" -eq 1 ]]; then
        return "${E_SUCCESS}"
    fi

    return "${E_FW_NOT_FOUND}"
}

# ==============================================================================
# fw_get_installed()
# Description:  Return list of installed firewall names.
# Returns:      Space-separated list on stdout
# ==============================================================================
fw_get_installed() {
    local fw_name
    local result=""
    for fw_name in "${SUPPORTED_FW_LIST[@]}"; do
        if [[ "${FW_DETECTED_INSTALLED[${fw_name}]:-0}" -eq 1 ]]; then
            result="${result}${result:+ }${fw_name}"
        fi
    done
    printf '%s' "${result}"
}

# ==============================================================================
# fw_get_info()
# Description:  Print detected firewall information.
# ==============================================================================
fw_get_info() {
    local fw_name
    printf '\n  %bDetected Firewalls:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    util_print_separator "─" 60

    for fw_name in "${SUPPORTED_FW_LIST[@]}"; do
        local installed="${FW_DETECTED_INSTALLED[${fw_name}]:-0}"
        if [[ "${installed}" -eq 1 ]]; then
            local version="${FW_DETECTED_VERSION[${fw_name}]:-unknown}"
            local running="${FW_DETECTED_RUNNING[${fw_name}]:-0}"
            local enabled="${FW_DETECTED_ENABLED[${fw_name}]:-0}"
            local status_color status_text

            if [[ "${running}" -eq 1 ]]; then
                status_color="${COLOR_GREEN}"
                status_text="running"
            else
                status_color="${COLOR_YELLOW}"
                status_text="stopped"
            fi

            printf '  %b%-12s%b v%-10s [%b%-7s%b] %s\n' \
                "${COLOR_BOLD}" "${fw_name}" "${COLOR_RESET}" \
                "${version}" \
                "${status_color}" "${status_text}" "${COLOR_RESET}" \
                "$( [[ "${enabled}" -eq 1 ]] && echo '(enabled)' || echo '(disabled)' )"
        else
            printf '  %b%-12s%b %-12s [%b%-7s%b]\n' \
                "${COLOR_DIM}" "${fw_name}" "${COLOR_RESET}" \
                "" \
                "${COLOR_DIM}" "not installed" "${COLOR_RESET}"
        fi
    done
}

# ==============================================================================
# fw_is_installed()
# Description:  Check if a specific firewall is installed.
# Parameters:   $1 - Firewall name
# Returns:      0 if installed, 1 if not
# ==============================================================================
fw_is_installed() {
    local fw_name="${1:?fw_is_installed requires firewall name}"
    [[ "${FW_DETECTED_INSTALLED[${fw_name}]:-0}" -eq 1 ]]
}

# ==============================================================================
# fw_is_running()
# Description:  Check if a specific firewall is currently running.
# Parameters:   $1 - Firewall name
# Returns:      0 if running, 1 if not
# ==============================================================================
fw_is_running() {
    local fw_name="${1:?fw_is_running requires firewall name}"
    [[ "${FW_DETECTED_RUNNING[${fw_name}]:-0}" -eq 1 ]]
}
