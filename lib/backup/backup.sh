#!/usr/bin/env bash
# ==============================================================================
# File:         lib/backup/backup.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Firewall configuration backup and restore point management
# Description:  Creates timestamped backups of firewall configurations before
#               changes. Supports per-backend and full system backups with
#               integrity verification and retention management.
# Notes:        - Backups are compressed tar archives with SHA-256 checksums
#               - Pre-change restore points enable safe rollback
#               - Backup directory has restricted permissions
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_BACKUP_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_BACKUP_LOADED=1

# ==============================================================================
# State Variables
# ==============================================================================
_BACKUP_DIR=""
_BACKUP_LAST_FILE=""

# ==============================================================================
# backup_init()
# Description:  Initialize backup subsystem.
# Parameters:   $1 - Backup directory path
# Returns:      0 on success
# ==============================================================================
backup_init() {
    local backup_dir="${1:?backup_init requires directory}"

    security_secure_dir "${backup_dir}" || return "${E_GENERAL}"
    _BACKUP_DIR="${backup_dir}"

    log_info "backup" "Backup subsystem initialized: ${backup_dir}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# backup_create()
# Description:  Create a backup of current firewall configuration.
# Parameters:   $1 - Backup label/description (optional)
#               $2 - Specific backend (optional, all if not specified)
# Returns:      0 on success, backup file path in _BACKUP_LAST_FILE
# ==============================================================================
backup_create() {
    local label="${1:-manual}"
    local backend="${2:-all}"

    [[ -z "${_BACKUP_DIR}" ]] && {
        log_error "backup" "Backup subsystem not initialized"
        return "${E_BACKUP_FAIL}"
    }

    local timestamp
    timestamp="$(util_timestamp_filename)"
    local backup_name="${BACKUP_PREFIX}_${label}_${timestamp}"
    local staging_dir="${_BACKUP_DIR}/.staging_${backup_name}"
    local backup_file="${_BACKUP_DIR}/${backup_name}${BACKUP_EXTENSION}"

    # Create staging directory
    mkdir -p "${staging_dir}" 2>/dev/null || {
        log_error "backup" "Failed to create staging directory"
        return "${E_BACKUP_FAIL}"
    }
    chmod "${SECURE_DIR_PERMS}" "${staging_dir}" 2>/dev/null || true

    log_info "backup" "Creating backup: ${backup_name} (backend=${backend})"

    # Export configurations based on backend
    if [[ "${backend}" == "all" ]]; then
        _backup_export_all "${staging_dir}"
    else
        _backup_export_single "${staging_dir}" "${backend}"
    fi

    # Save rule index
    if [[ -f "${_RULE_INDEX_FILE:-}" ]]; then
        cp "${_RULE_INDEX_FILE}" "${staging_dir}/rule_index.dat" 2>/dev/null || true
    fi

    # Save rule state
    if [[ -f "${_RULE_STATE_FILE:-}" ]]; then
        cp "${_RULE_STATE_FILE}" "${staging_dir}/rule_state.dat" 2>/dev/null || true
    fi

    # Write manifest
    {
        printf '{\n'
        printf '  "name": "%s",\n' "${backup_name}"
        printf '  "timestamp": "%s",\n' "$(util_timestamp)"
        printf '  "label": "%s",\n' "${label}"
        printf '  "backend": "%s",\n' "${backend}"
        printf '  "version": "%s",\n' "${APOTROPAIOS_VERSION}"
        printf '  "os_id": "%s",\n' "${OS_DETECTED_ID:-unknown}"
        printf '  "os_version": "%s"\n' "${OS_DETECTED_VERSION:-unknown}"
        printf '}\n'
    } > "${staging_dir}/${BACKUP_MANIFEST_FILE}" 2>/dev/null || true

    # Create compressed archive
    if ! tar -czf "${backup_file}" -C "${_BACKUP_DIR}" ".staging_${backup_name}" 2>/dev/null; then
        log_error "backup" "Failed to create backup archive"
        rm -rf "${staging_dir}" 2>/dev/null || true
        return "${E_BACKUP_FAIL}"
    fi

    # Generate checksum
    local checksum
    checksum="$(security_file_checksum "${backup_file}")" || true
    if [[ -n "${checksum}" ]]; then
        printf '%s  %s\n' "${checksum}" "$(basename "${backup_file}")" > "${backup_file}.sha256" 2>/dev/null || true
    fi

    # Cleanup staging
    rm -rf "${staging_dir}" 2>/dev/null || true

    # Set permissions
    chmod "${SECURE_FILE_PERMS}" "${backup_file}" 2>/dev/null || true

    # Manage retention
    _backup_enforce_retention

    _BACKUP_LAST_FILE="${backup_file}"
    log_info "backup" "Backup created: ${backup_file}" "checksum=${checksum:-none}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# _backup_export_all() [INTERNAL]
# Description:  Export all detected firewall configurations.
# ==============================================================================
_backup_export_all() {
    local staging="$1"
    local fw_name

    for fw_name in "${SUPPORTED_FW_LIST[@]}"; do
        if fw_is_installed "${fw_name}"; then
            _backup_export_single "${staging}" "${fw_name}"
        fi
    done
}

# ==============================================================================
# _backup_export_single() [INTERNAL]
# Description:  Export a single firewall's configuration.
# ==============================================================================
_backup_export_single() {
    local staging="$1"
    local fw_name="$2"
    local output_file="${staging}/${fw_name}.conf"

    case "${fw_name}" in
        iptables)
            if util_is_command_available iptables-save; then
                iptables-save > "${output_file}" 2>/dev/null || true
            fi
            ;;
        nftables)
            if util_is_command_available nft; then
                nft list ruleset > "${output_file}" 2>/dev/null || true
            fi
            ;;
        firewalld)
            if util_is_command_available firewall-cmd; then
                firewall-cmd --list-all-zones > "${output_file}" 2>/dev/null || true
            fi
            ;;
        ufw)
            if util_is_command_available ufw; then
                ufw status numbered verbose > "${output_file}" 2>/dev/null || true
                # Copy ufw config files if accessible
                if [[ -d /etc/ufw ]]; then
                    cp -r /etc/ufw "${staging}/ufw_etc/" 2>/dev/null || true
                fi
            fi
            ;;
        ipset)
            if util_is_command_available ipset; then
                ipset save > "${output_file}" 2>/dev/null || true
            fi
            ;;
    esac

    if [[ -f "${output_file}" ]]; then
        chmod "${SECURE_FILE_PERMS}" "${output_file}" 2>/dev/null || true
    fi
}

# ==============================================================================
# _backup_enforce_retention() [INTERNAL]
# Description:  Remove old backups beyond the retention limit.
# ==============================================================================
_backup_enforce_retention() {
    [[ -z "${_BACKUP_DIR}" ]] && return

    local backup_count
    backup_count="$(find "${_BACKUP_DIR}" -maxdepth 1 -name "${BACKUP_PREFIX}_*${BACKUP_EXTENSION}" -type f 2>/dev/null | wc -l)" || backup_count=0

    if [[ "${backup_count}" -gt "${BACKUP_MAX_RETAINED}" ]]; then
        local excess=$((backup_count - BACKUP_MAX_RETAINED))
        log_debug "backup" "Removing ${excess} old backup(s) (retention: ${BACKUP_MAX_RETAINED})"

        find "${_BACKUP_DIR}" -maxdepth 1 -name "${BACKUP_PREFIX}_*${BACKUP_EXTENSION}" -type f -printf '%T@ %p\n' 2>/dev/null | \
            sort -n | head -n "${excess}" | awk '{print $2}' | \
            while IFS= read -r old_backup; do
                rm -f "${old_backup}" "${old_backup}.sha256" 2>/dev/null || true
                log_debug "backup" "Removed old backup: ${old_backup}"
            done
    fi
}

# ==============================================================================
# backup_list()
# Description:  List available backups.
# ==============================================================================
backup_list() {
    [[ -z "${_BACKUP_DIR}" ]] && {
        printf '  Backup subsystem not initialized\n'
        return
    }

    local -a backups=()
    while IFS= read -r file; do
        [[ -n "${file}" ]] && backups+=("${file}")
    done < <(find "${_BACKUP_DIR}" -maxdepth 1 -name "${BACKUP_PREFIX}_*${BACKUP_EXTENSION}" -type f 2>/dev/null | sort -r)

    if [[ "${#backups[@]}" -eq 0 ]]; then
        printf '  %bNo backups found%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
        return
    fi

    printf '\n  %bAvailable Backups (%d):%b\n' "${COLOR_BOLD}" "${#backups[@]}" "${COLOR_RESET}"
    util_print_separator "─" 80

    local i=1
    local backup
    for backup in "${backups[@]}"; do
        local name size
        name="$(basename "${backup}")"
        size="$(stat -c%s "${backup}" 2>/dev/null)" || size=0
        printf '  %b%2d.%b %-55s %s\n' "${COLOR_BOLD}" "${i}" "${COLOR_RESET}" \
            "${name}" "$(util_human_bytes "${size}")"
        ((i++)) || true
    done
}

# ==============================================================================
# backup_create_restore_point()
# Description:  Create a restore point before making changes.
# Parameters:   $1 - Description of pending change
# Returns:      0 on success
# ==============================================================================
backup_create_restore_point() {
    local description="${1:-pre-change}"
    local safe_desc
    safe_desc="$(printf '%s' "${description}" | tr ' ' '_' | tr -cd 'a-zA-Z0-9_-')"

    backup_create "restore_${safe_desc}" || {
        log_error "backup" "Failed to create restore point"
        return "${E_BACKUP_FAIL}"
    }

    log_info "backup" "Restore point created: ${_BACKUP_LAST_FILE}"
    return "${E_SUCCESS}"
}
