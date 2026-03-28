#!/usr/bin/env bash
# ==============================================================================
# File:         lib/install/installer.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Firewall package installation and configuration
# Description:  Handles detection, download, installation, and initial
#               configuration of firewall packages across supported OS families.
#               Supports apt, dnf, and pacman package managers.
# Notes:        - Requires root privileges
#               - Creates restore point before installation
#               - Validates installation success after completion
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_INSTALLER_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_INSTALLER_LOADED=1

# ==============================================================================
# install_firewall()
# Description:  Install a firewall package.
# Parameters:   $1 - Firewall name from SUPPORTED_FW_LIST
# Returns:      0 on success, E_FW_INSTALL_FAIL on failure
# ==============================================================================
install_firewall() {
    local fw_name="${1:?install_firewall requires firewall name}"

    # Validate it's a supported firewall
    if ! util_array_contains "${fw_name}" "${SUPPORTED_FW_LIST[@]}"; then
        log_error "installer" "Unsupported firewall: ${fw_name}"
        return "${E_FW_INSTALL_FAIL}"
    fi

    # Check root
    security_check_root || {
        log_error "installer" "Root privileges required for installation"
        return "${E_PERMISSION}"
    }

    # Check if already installed
    if fw_is_installed "${fw_name}"; then
        log_info "installer" "${fw_name} is already installed"
        return "${E_SUCCESS}"
    fi

    # Create restore point
    backup_create_restore_point "pre_install_${fw_name}" || true

    # Determine package name for this OS
    local pkg_name
    pkg_name="$(_installer_get_package_name "${fw_name}")" || {
        log_error "installer" "Cannot determine package name for ${fw_name} on ${OS_DETECTED_ID}"
        return "${E_FW_INSTALL_FAIL}"
    }

    log_info "installer" "Installing ${fw_name} (package: ${pkg_name}) via ${OS_DETECTED_PKG_MANAGER}"

    # Install based on package manager
    local install_rc=0
    case "${OS_DETECTED_PKG_MANAGER}" in
        apt)
            _installer_apt_install "${pkg_name}" || install_rc=$?
            ;;
        dnf)
            _installer_dnf_install "${pkg_name}" || install_rc=$?
            ;;
        pacman)
            _installer_pacman_install "${pkg_name}" || install_rc=$?
            ;;
        *)
            log_error "installer" "Unsupported package manager: ${OS_DETECTED_PKG_MANAGER}"
            return "${E_FW_INSTALL_FAIL}"
            ;;
    esac

    if [[ "${install_rc}" -ne 0 ]]; then
        log_error "installer" "Failed to install ${fw_name}"
        return "${E_FW_INSTALL_FAIL}"
    fi

    # Verify installation
    fw_detect_single "${fw_name}" || {
        log_error "installer" "Installation verification failed: ${fw_name} not detected after install"
        return "${E_FW_INSTALL_FAIL}"
    }

    log_info "installer" "${fw_name} installed successfully (v${FW_DETECTED_VERSION[${fw_name}]:-unknown})"
    return "${E_SUCCESS}"
}

# ==============================================================================
# _installer_get_package_name() [INTERNAL]
# Description:  Determine the OS-specific package name for a firewall.
# ==============================================================================
_installer_get_package_name() {
    local fw_name="$1"
    local idx
    idx="$(util_array_index "${fw_name}" "${SUPPORTED_FW_LIST[@]}")" || return 1

    local pkg_spec="${SUPPORTED_FW_PACKAGES[${idx}]}"
    local pkg_name

    case "${OS_DETECTED_PKG_MANAGER}" in
        apt)    pkg_name="${pkg_spec%%:*}" ;;
        dnf)    pkg_name="$(printf '%s' "${pkg_spec}" | cut -d: -f2)" ;;
        pacman) pkg_name="${pkg_spec##*:}" ;;
        *)      return 1 ;;
    esac

    [[ -z "${pkg_name}" ]] && return 1
    printf '%s' "${pkg_name}"
}

# ==============================================================================
# Package manager install functions [INTERNAL]
# ==============================================================================

_installer_apt_install() {
    local pkg="$1"
    log_debug "installer" "Running: apt-get update && apt-get install -y ${pkg}"
    apt-get update -qq 2>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkg}" 2>/dev/null
}

_installer_dnf_install() {
    local pkg="$1"
    log_debug "installer" "Running: dnf install -y ${pkg}"
    dnf install -y --allowerasing "${pkg}" 2>/dev/null
}

_installer_pacman_install() {
    local pkg="$1"
    log_debug "installer" "Running: pacman -Sy --noconfirm ${pkg}"
    pacman -Sy --noconfirm "${pkg}" 2>/dev/null
}

# ==============================================================================
# update_firewall()
# Description:  Update a firewall package to latest version.
# Parameters:   $1 - Firewall name
# Returns:      0 on success
# ==============================================================================
update_firewall() {
    local fw_name="${1:?update_firewall requires firewall name}"

    security_check_root || return "${E_PERMISSION}"

    if ! fw_is_installed "${fw_name}"; then
        log_error "installer" "${fw_name} is not installed"
        return "${E_FW_NOT_FOUND}"
    fi

    backup_create_restore_point "pre_update_${fw_name}" || true

    local pkg_name
    pkg_name="$(_installer_get_package_name "${fw_name}")" || return "${E_FW_INSTALL_FAIL}"

    log_info "installer" "Updating ${fw_name} (package: ${pkg_name})"

    case "${OS_DETECTED_PKG_MANAGER}" in
        apt)
            apt-get update -qq 2>/dev/null || true
            DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq "${pkg_name}" 2>/dev/null || {
                log_error "installer" "Failed to update ${fw_name}"
                return "${E_FW_INSTALL_FAIL}"
            }
            ;;
        dnf)
            dnf update -y "${pkg_name}" 2>/dev/null || {
                log_error "installer" "Failed to update ${fw_name}"
                return "${E_FW_INSTALL_FAIL}"
            }
            ;;
        pacman)
            pacman -Syu --noconfirm "${pkg_name}" 2>/dev/null || {
                log_error "installer" "Failed to update ${fw_name}"
                return "${E_FW_INSTALL_FAIL}"
            }
            ;;
    esac

    # Re-detect to get new version
    fw_detect_single "${fw_name}" || true

    log_info "installer" "${fw_name} updated to v${FW_DETECTED_VERSION[${fw_name}]:-unknown}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# install_configure_firewall()
# Description:  Configure a freshly installed firewall with safe defaults.
# Parameters:   $1 - Firewall name
# Returns:      0 on success
# ==============================================================================
install_configure_firewall() {
    local fw_name="${1:?install_configure_firewall requires firewall name}"

    log_info "installer" "Configuring ${fw_name} with safe defaults"

    local service_name="${SUPPORTED_FW_SERVICES[$(util_array_index "${fw_name}" "${SUPPORTED_FW_LIST[@]}" 2>/dev/null || echo 0)]:-}"

    # Enable service if applicable
    if [[ -n "${service_name}" ]] && util_is_command_available systemctl; then
        systemctl enable "${service_name}" 2>/dev/null || true
        systemctl start "${service_name}" 2>/dev/null || true
        log_info "installer" "Service ${service_name} enabled and started"
    fi

    # Backend-specific configuration
    case "${fw_name}" in
        ufw)
            # Set default policies
            ufw default deny incoming 2>/dev/null || true
            ufw default allow outgoing 2>/dev/null || true
            ufw logging on 2>/dev/null || true
            printf 'y\n' | ufw enable 2>/dev/null || true
            ;;
        firewalld)
            firewall-cmd --set-default-zone=public 2>/dev/null || true
            ;;
    esac

    log_info "installer" "${fw_name} configured with safe defaults"
    return "${E_SUCCESS}"
}
