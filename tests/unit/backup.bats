#!/usr/bin/env bats
# ==============================================================================
# File:         tests/unit/backup.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Unit tests for backup, restore, and immutable modules.
# ==============================================================================

load '../helpers/test_helper'

_init_backup() {
    local backup_dir="${TEST_TMPDIR}/data/backups"
    mkdir -p "${backup_dir}"
    backup_init "${backup_dir}" 2>/dev/null
}

# ==============================================================================
# Backup Initialization
# ==============================================================================

@test "backup_init: creates backup directory" {
    local dir="${TEST_TMPDIR}/data/backups"
    backup_init "${dir}" 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    [ -d "${dir}" ]
}

@test "backup_init: directory has 700 permissions" {
    local dir="${TEST_TMPDIR}/data/backups"
    backup_init "${dir}" 2>/dev/null
    local perms
    perms="$(stat -c '%a' "${dir}" 2>/dev/null)"
    [ "${perms}" = "700" ]
}

# ==============================================================================
# Backup Creation
# ==============================================================================

@test "backup_create: creates tar.gz archive" {
    _init_backup
    backup_create "unit_test" 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    local count
    count="$(find "${TEST_TMPDIR}/data/backups" -name "*.tar.gz" -type f | wc -l)"
    [ "${count}" -ge 1 ]
}

@test "backup_create: creates SHA-256 checksum sidecar" {
    _init_backup
    backup_create "checksum_test" 2>/dev/null
    local count
    count="$(find "${TEST_TMPDIR}/data/backups" -name "*.sha256" -type f | wc -l)"
    [ "${count}" -ge 1 ]
}

@test "backup_create: sets _BACKUP_LAST_FILE" {
    _init_backup
    backup_create "lastfile_test" 2>/dev/null
    [ -n "${_BACKUP_LAST_FILE}" ]
    [ -f "${_BACKUP_LAST_FILE}" ]
}

@test "backup_create: archive filename contains label" {
    _init_backup
    backup_create "my_label_xyz" 2>/dev/null
    [[ "${_BACKUP_LAST_FILE}" == *"my_label_xyz"* ]]
}

@test "backup_create: multiple backups create distinct files" {
    _init_backup
    backup_create "first" 2>/dev/null
    local first="${_BACKUP_LAST_FILE}"
    sleep 1  # Ensure different timestamp
    backup_create "second" 2>/dev/null
    local second="${_BACKUP_LAST_FILE}"
    [ "${first}" != "${second}" ]
    [ -f "${first}" ]
    [ -f "${second}" ]
}

# ==============================================================================
# Backup Listing
# ==============================================================================

@test "backup_list: shows 'No backups' when empty" {
    _init_backup
    local output
    output="$(backup_list 2>/dev/null)"
    [[ "${output}" == *"No backups"* ]]
}

@test "backup_list: shows backup after creation" {
    _init_backup
    backup_create "visible_test" 2>/dev/null
    local output
    output="$(backup_list 2>/dev/null)"
    [[ "${output}" == *"visible_test"* ]]
}

# ==============================================================================
# Restore Point
# ==============================================================================

@test "backup_create_restore_point: creates restore-labeled backup" {
    _init_backup
    backup_create_restore_point "pre_change" 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    [[ "${_BACKUP_LAST_FILE}" == *"restore_pre_change"* ]]
}

# ==============================================================================
# Backup Integrity
# ==============================================================================

@test "backup: archive passes checksum verification" {
    _init_backup
    backup_create "integrity_test" 2>/dev/null
    local archive="${_BACKUP_LAST_FILE}"
    local sha_file="${archive}.sha256"
    [ -f "${sha_file}" ]

    local expected
    expected="$(awk '{print $1}' "${sha_file}")"
    security_verify_checksum "${archive}" "${expected}" && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

@test "backup: tampered archive fails checksum" {
    _init_backup
    backup_create "tamper_test" 2>/dev/null
    local archive="${_BACKUP_LAST_FILE}"
    local sha_file="${archive}.sha256"

    # Tamper with the archive
    printf '\x00' >> "${archive}"

    local expected
    expected="$(awk '{print $1}' "${sha_file}")"
    security_verify_checksum "${archive}" "${expected}" && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

# ==============================================================================
# Immutable Snapshots
# ==============================================================================

@test "immutable_list: shows 'No immutable snapshots' when empty" {
    _init_backup
    local output
    output="$(immutable_list 2>/dev/null)"
    [[ "${output}" == *"No immutable"* ]]
}

@test "immutable_verify: passes with no snapshots" {
    _init_backup
    immutable_verify 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}
