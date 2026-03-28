#!/usr/bin/env bash
# ==============================================================================
# File:         lib/backup/restore.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Firewall configuration restoration from backups
# Description:  Restores firewall configurations from previously created backup
#               archives. Validates backup integrity before restoration.
# Notes:        - Creates a pre-restore backup automatically
#               - Validates archive integrity via SHA-256 checksum
#               - Supports selective backend restoration
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_RESTORE_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_RESTORE_LOADED=1

# ==============================================================================
# backup_restore()
# Description:  Restore firewall configuration from a backup archive.
# Parameters:   $1 - Backup file path
#               $2 - Specific backend to restore (optional, all if not specified)
# Returns:      0 on success, E_RESTORE_FAIL on failure
# ==============================================================================
backup_restore() {
    local backup_file="${1:?backup_restore requires backup file path}"
    local target_backend="${2:-all}"

    # Validate file exists
    [[ ! -f "${backup_file}" ]] && {
        log_error "restore" "Backup file not found: ${backup_file}"
        return "${E_BACKUP_NOT_FOUND}"
    }

    # Verify integrity if checksum available
    local checksum_file="${backup_file}.sha256"
    if [[ -f "${checksum_file}" ]]; then
        local expected
        expected="$(awk '{print $1}' "${checksum_file}" 2>/dev/null)" || true
        if [[ -n "${expected}" ]]; then
            if ! security_verify_checksum "${backup_file}" "${expected}"; then
                log_error "restore" "Backup integrity check failed — aborting restore"
                return "${E_INTEGRITY_FAIL}"
            fi
            log_info "restore" "Backup integrity verified"
        fi
    fi

    # Create pre-restore backup for safety
    log_info "restore" "Creating pre-restore safety backup"
    backup_create "pre_restore" "${target_backend}" || {
        log_warning "restore" "Failed to create pre-restore backup — proceeding with caution"
    }

    # Extract to temporary directory
    local extract_dir
    extract_dir="$(security_create_temp_dir "restore")" || return "${E_RESTORE_FAIL}"

    if ! tar -xzf "${backup_file}" -C "${extract_dir}" 2>/dev/null; then
        log_error "restore" "Failed to extract backup archive"
        rm -rf "${extract_dir}" 2>/dev/null || true
        return "${E_RESTORE_FAIL}"
    fi

    # Find the staging directory inside the extract
    local staging_dir
    staging_dir="$(find "${extract_dir}" -maxdepth 1 -type d -name ".staging_*" 2>/dev/null | head -1)" || true
    [[ -z "${staging_dir}" ]] && staging_dir="${extract_dir}"

    # Read manifest for metadata
    local manifest="${staging_dir}/${BACKUP_MANIFEST_FILE}"
    if [[ -f "${manifest}" ]]; then
        log_info "restore" "Backup manifest found"
        cat "${manifest}" | while IFS= read -r mline; do
            log_debug "restore" "Manifest: ${mline}"
        done
    fi

    # Restore configurations
    local restore_rc=0
    if [[ "${target_backend}" == "all" ]]; then
        _restore_all_backends "${staging_dir}" || restore_rc=$?
    else
        _restore_single_backend "${staging_dir}" "${target_backend}" || restore_rc=$?
    fi

    # Restore rule index if present
    local index_backup="${staging_dir}/rule_index.dat"
    if [[ -f "${index_backup}" ]]; then
        local rules_dir
        rules_dir="$(dirname "${_RULE_INDEX_FILE:-/dev/null}" 2>/dev/null)" || true
        if [[ -d "${rules_dir}" ]]; then
            cp "${index_backup}" "${_RULE_INDEX_FILE}" 2>/dev/null || true
            chmod "${SECURE_FILE_PERMS}" "${_RULE_INDEX_FILE}" 2>/dev/null || true
            rule_index_load || true
            log_info "restore" "Rule index restored"
        fi
    fi

    # Restore rule state if present
    local state_backup="${staging_dir}/rule_state.dat"
    if [[ -f "${state_backup}" ]] && [[ -n "${_RULE_STATE_FILE:-}" ]]; then
        cp "${state_backup}" "${_RULE_STATE_FILE}" 2>/dev/null || true
        chmod "${SECURE_FILE_PERMS}" "${_RULE_STATE_FILE}" 2>/dev/null || true
        log_info "restore" "Rule state restored"
    fi

    # Cleanup
    rm -rf "${extract_dir}" 2>/dev/null || true

    if [[ "${restore_rc}" -ne 0 ]]; then
        log_error "restore" "Restore completed with errors"
        return "${E_RESTORE_FAIL}"
    fi

    log_info "restore" "Restore completed successfully from: ${backup_file}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# _restore_all_backends() [INTERNAL]
# ==============================================================================
_restore_all_backends() {
    local staging="$1"
    local rc=0
    local fw_name

    for fw_name in "${SUPPORTED_FW_LIST[@]}"; do
        if [[ -f "${staging}/${fw_name}.conf" ]] && fw_is_installed "${fw_name}"; then
            _restore_single_backend "${staging}" "${fw_name}" || rc=1
        fi
    done
    return "${rc}"
}

# ==============================================================================
# _restore_single_backend() [INTERNAL]
# ==============================================================================
_restore_single_backend() {
    local staging="$1"
    local fw_name="$2"
    local config_file="${staging}/${fw_name}.conf"

    [[ ! -f "${config_file}" ]] && {
        log_warning "restore" "No backup config found for ${fw_name}"
        return 1
    }

    if ! fw_is_installed "${fw_name}"; then
        log_warning "restore" "${fw_name} not installed — skipping restore"
        return 1
    fi

    log_info "restore" "Restoring ${fw_name} configuration"

    case "${fw_name}" in
        iptables)
            if util_is_command_available iptables-restore; then
                iptables-restore < "${config_file}" 2>/dev/null || {
                    log_error "restore" "iptables restore failed"
                    return 1
                }
            fi
            ;;
        nftables)
            if util_is_command_available nft; then
                nft -f "${config_file}" 2>/dev/null || {
                    log_error "restore" "nftables restore failed"
                    return 1
                }
            fi
            ;;
        firewalld)
            # firewalld doesn't have a direct import; reload from saved permanent config
            if util_is_command_available firewall-cmd; then
                firewall-cmd --reload 2>/dev/null || true
            fi
            ;;
        ufw)
            # Restore ufw config directory if available
            if [[ -d "${staging}/ufw_etc" ]]; then
                cp -r "${staging}/ufw_etc/"* /etc/ufw/ 2>/dev/null || true
                ufw reload 2>/dev/null || true
            fi
            ;;
        ipset)
            if util_is_command_available ipset; then
                ipset restore < "${config_file}" 2>/dev/null || {
                    log_error "restore" "ipset restore failed"
                    return 1
                }
            fi
            ;;
    esac

    log_info "restore" "${fw_name} configuration restored"
    return 0
}
