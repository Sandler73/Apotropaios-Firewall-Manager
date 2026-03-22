#!/usr/bin/env bash
# ==============================================================================
# File:         lib/backup/immutable.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Immutable snapshot management for system recovery
# Description:  Creates and manages immutable snapshots of firewall state that
#               cannot be modified after creation. Uses filesystem immutable
#               attributes (chattr +i) where available, with checksum-based
#               integrity verification as fallback.
# Notes:        - chattr +i requires root and ext2/3/4/btrfs filesystem
#               - Falls back to checksum verification on unsupported filesystems
#               - Snapshots include all firewall configs + rule index
# Version:      1.0.0
# ==============================================================================

[[ -n "${_APOTROPAIOS_IMMUTABLE_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_IMMUTABLE_LOADED=1

# ==============================================================================
# immutable_create()
# Description:  Create an immutable snapshot of current firewall state.
# Parameters:   $1 - Snapshot label
# Returns:      0 on success
# ==============================================================================
immutable_create() {
    local label="${1:-snapshot}"

    [[ -z "${_BACKUP_DIR}" ]] && {
        log_error "immutable" "Backup subsystem not initialized"
        return "${E_BACKUP_FAIL}"
    }

    local immutable_dir="${_BACKUP_DIR}/immutable"
    security_secure_dir "${immutable_dir}" || return "${E_BACKUP_FAIL}"

    # Create backup first
    backup_create "immutable_${label}" || return "${E_BACKUP_FAIL}"

    local backup_file="${_BACKUP_LAST_FILE}"
    [[ -z "${backup_file}" ]] || [[ ! -f "${backup_file}" ]] && {
        log_error "immutable" "No backup file available for immutable snapshot"
        return "${E_BACKUP_FAIL}"
    }

    # Copy to immutable directory
    local snapshot_name
    snapshot_name="$(basename "${backup_file}")"
    local immutable_file="${immutable_dir}/${snapshot_name}"

    cp "${backup_file}" "${immutable_file}" 2>/dev/null || {
        log_error "immutable" "Failed to copy backup to immutable directory"
        return "${E_BACKUP_FAIL}"
    }
    cp "${backup_file}.sha256" "${immutable_file}.sha256" 2>/dev/null || true

    # Generate and store integrity checksum
    local checksum
    checksum="$(security_file_checksum "${immutable_file}")" || true
    printf '%s  %s\n' "${checksum}" "${snapshot_name}" > "${immutable_file}.integrity" 2>/dev/null || true

    # Try to set immutable attribute
    if util_is_command_available chattr; then
        if chattr +i "${immutable_file}" 2>/dev/null; then
            chattr +i "${immutable_file}.sha256" 2>/dev/null || true
            chattr +i "${immutable_file}.integrity" 2>/dev/null || true
            log_info "immutable" "Immutable attribute set on snapshot"
        else
            log_warning "immutable" "Cannot set immutable attribute (filesystem may not support it)"
        fi
    fi

    chmod "${SECURE_FILE_PERMS}" "${immutable_file}" 2>/dev/null || true
    log_info "immutable" "Immutable snapshot created: ${immutable_file}" "checksum=${checksum:-none}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# immutable_verify()
# Description:  Verify integrity of all immutable snapshots.
# Returns:      0 if all pass, 1 if any fail
# ==============================================================================
immutable_verify() {
    local immutable_dir="${_BACKUP_DIR}/immutable"
    [[ ! -d "${immutable_dir}" ]] && { log_info "immutable" "No immutable snapshots"; return 0; }

    local failed=0
    local checked=0

    while IFS= read -r integrity_file; do
        [[ -z "${integrity_file}" ]] && continue

        local snapshot_file="${integrity_file%.integrity}"
        local expected_checksum
        expected_checksum="$(awk '{print $1}' "${integrity_file}" 2>/dev/null)" || continue

        [[ -z "${expected_checksum}" ]] && continue
        [[ ! -f "${snapshot_file}" ]] && {
            log_error "immutable" "Snapshot missing: ${snapshot_file}"
            ((failed++)) || true
            continue
        }

        ((checked++)) || true
        if security_verify_checksum "${snapshot_file}" "${expected_checksum}"; then
            log_debug "immutable" "Verified: $(basename "${snapshot_file}")"
        else
            log_error "immutable" "INTEGRITY FAILURE: $(basename "${snapshot_file}")"
            ((failed++)) || true
        fi
    done < <(find "${immutable_dir}" -name "*.integrity" -type f 2>/dev/null)

    log_info "immutable" "Verified ${checked} snapshot(s): ${failed} failure(s)"
    [[ "${failed}" -gt 0 ]] && return 1
    return 0
}

# ==============================================================================
# immutable_list()
# Description:  List immutable snapshots.
# ==============================================================================
immutable_list() {
    local immutable_dir="${_BACKUP_DIR}/immutable"
    [[ ! -d "${immutable_dir}" ]] && {
        printf '  %bNo immutable snapshots%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
        return
    }

    local -a snapshots=()
    while IFS= read -r file; do
        [[ -n "${file}" ]] && snapshots+=("${file}")
    done < <(find "${immutable_dir}" -name "${BACKUP_PREFIX}_*${BACKUP_EXTENSION}" -type f 2>/dev/null | sort -r)

    printf '\n  %bImmutable Snapshots (%d):%b\n' "${COLOR_BOLD}" "${#snapshots[@]}" "${COLOR_RESET}"
    util_print_separator "─" 70

    local snapshot
    for snapshot in "${snapshots[@]}"; do
        local name size
        name="$(basename "${snapshot}")"
        size="$(stat -c%s "${snapshot}" 2>/dev/null)" || size=0
        printf '  %-55s %s\n' "${name}" "$(util_human_bytes "${size}")"
    done
}
