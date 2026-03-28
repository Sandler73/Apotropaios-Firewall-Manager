#!/usr/bin/env bats
# ==============================================================================
# File:         tests/unit/security.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Unit tests for security module — UUID generation, checksums,
#               temporary files, locking, binary validation, sensitive vars.
# ==============================================================================

load '../helpers/test_helper'

# ==============================================================================
# UUID Generation
# ==============================================================================

@test "security_generate_uuid: produces valid UUID v4 format" {
    local uuid
    uuid="$(security_generate_uuid)"
    [[ "${uuid}" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]
}

@test "security_generate_uuid: produces unique IDs across 10 calls" {
    local -a uuids=()
    local i
    for i in $(seq 1 10); do
        uuids+=("$(security_generate_uuid)")
    done
    # Check all are unique by comparing sorted unique count
    local unique_count
    unique_count="$(printf '%s\n' "${uuids[@]}" | sort -u | wc -l)"
    [ "${unique_count}" -eq 10 ]
}

@test "security_generate_uuid: output is exactly 36 characters" {
    local uuid
    uuid="$(security_generate_uuid)"
    [ "${#uuid}" -eq 36 ]
}

# ==============================================================================
# SHA-256 Checksums
# ==============================================================================

@test "security_file_checksum: produces 64-char hex string" {
    local testfile="${TEST_TMPDIR}/checksum_test.txt"
    printf 'test content for checksum' > "${testfile}"
    local checksum
    checksum="$(security_file_checksum "${testfile}")"
    [ "${#checksum}" -eq 64 ]
    [[ "${checksum}" =~ ^[a-f0-9]{64}$ ]]
}

@test "security_file_checksum: same content produces same hash" {
    local f1="${TEST_TMPDIR}/ck1.txt"
    local f2="${TEST_TMPDIR}/ck2.txt"
    printf 'identical content' > "${f1}"
    printf 'identical content' > "${f2}"
    local h1 h2
    h1="$(security_file_checksum "${f1}")"
    h2="$(security_file_checksum "${f2}")"
    [ "${h1}" = "${h2}" ]
}

@test "security_file_checksum: different content produces different hash" {
    local f1="${TEST_TMPDIR}/ckd1.txt"
    local f2="${TEST_TMPDIR}/ckd2.txt"
    printf 'content A' > "${f1}"
    printf 'content B' > "${f2}"
    local h1 h2
    h1="$(security_file_checksum "${f1}")"
    h2="$(security_file_checksum "${f2}")"
    [ "${h1}" != "${h2}" ]
}

@test "security_file_checksum: fails on nonexistent file" {
    run security_file_checksum "/nonexistent/path/file.txt"
    [ "$status" -ne 0 ]
}

@test "security_verify_checksum: passes for matching checksum" {
    local testfile="${TEST_TMPDIR}/verify_ok.txt"
    printf 'verify me' > "${testfile}"
    local checksum
    checksum="$(security_file_checksum "${testfile}")"
    security_verify_checksum "${testfile}" "${checksum}" && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

@test "security_verify_checksum: fails for wrong checksum" {
    local testfile="${TEST_TMPDIR}/verify_bad.txt"
    printf 'verify me' > "${testfile}"
    security_verify_checksum "${testfile}" "0000000000000000000000000000000000000000000000000000000000000000" && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

# ==============================================================================
# Temporary File Management
# ==============================================================================

@test "security_create_temp_file: creates a file" {
    local tmpf
    tmpf="$(security_create_temp_file "test")"
    [ -f "${tmpf}" ]
    rm -f "${tmpf}" 2>/dev/null || true
}

@test "security_create_temp_file: file has 600 permissions" {
    local tmpf
    tmpf="$(security_create_temp_file "permtest")"
    local perms
    perms="$(stat -c '%a' "${tmpf}" 2>/dev/null)" || perms="unknown"
    [ "${perms}" = "600" ]
    rm -f "${tmpf}" 2>/dev/null || true
}

@test "security_create_temp_dir: creates a directory" {
    local tmpd
    tmpd="$(security_create_temp_dir "test")"
    [ -d "${tmpd}" ]
    rm -rf "${tmpd}" 2>/dev/null || true
}

@test "security_create_temp_dir: directory has 700 permissions" {
    local tmpd
    tmpd="$(security_create_temp_dir "permtest")"
    local perms
    perms="$(stat -c '%a' "${tmpd}" 2>/dev/null)" || perms="unknown"
    [ "${perms}" = "700" ]
    rm -rf "${tmpd}" 2>/dev/null || true
}

# ==============================================================================
# Advisory Locking
# ==============================================================================

@test "security_acquire_lock: acquires a fresh lock" {
    local lockfile="${TEST_TMPDIR}/test.lock"
    security_acquire_lock "${lockfile}" 5 && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    [ -f "${lockfile}" ]
    # Lock file should contain our PID
    local lock_pid
    lock_pid="$(cat "${lockfile}")"
    [ "${lock_pid}" = "$$" ]
    # Cleanup
    security_release_lock "${lockfile}"
}

@test "security_release_lock: removes the lock file" {
    local lockfile="${TEST_TMPDIR}/release_test.lock"
    security_acquire_lock "${lockfile}" 5
    security_release_lock "${lockfile}"
    [ ! -f "${lockfile}" ]
}

@test "security_acquire_lock: detects stale lock from dead PID" {
    local lockfile="${TEST_TMPDIR}/stale.lock"
    # Write a PID that doesn't exist
    echo "99999999" > "${lockfile}"
    security_acquire_lock "${lockfile}" 5 && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    security_release_lock "${lockfile}"
}

# ==============================================================================
# Binary Validation
# ==============================================================================

@test "security_validate_binary: finds bash" {
    security_validate_binary "bash" && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

@test "security_validate_binary: rejects nonexistent binary" {
    security_validate_binary "definitely_not_a_real_binary_xyz" && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

@test "security_validate_binary: accepts absolute path to real binary" {
    local bash_path
    bash_path="$(command -v bash)"
    security_validate_binary "${bash_path}" && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

# ==============================================================================
# Sensitive Variable Scrubbing
# ==============================================================================

@test "security_register_sensitive_var: registers without error" {
    MY_SECRET_VAR="supersecret"
    security_register_sensitive_var "MY_SECRET_VAR" && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    unset MY_SECRET_VAR 2>/dev/null || true
}

@test "security_scrub_vars: clears registered variables" {
    MY_SCRUB_TEST="sensitive_data"
    security_register_sensitive_var "MY_SCRUB_TEST"
    security_scrub_vars
    # Variable should be unset
    [ -z "${MY_SCRUB_TEST+x}" ]
}

# ==============================================================================
# Secure Directory/File Functions
# ==============================================================================

@test "security_secure_dir: creates directory with 700 perms" {
    local dir="${TEST_TMPDIR}/secure_dir_test"
    security_secure_dir "${dir}" && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    [ -d "${dir}" ]
    local perms
    perms="$(stat -c '%a' "${dir}" 2>/dev/null)"
    [ "${perms}" = "700" ]
}

@test "security_secure_file: sets 600 permissions" {
    local file="${TEST_TMPDIR}/secure_file_test.txt"
    touch "${file}"
    chmod 644 "${file}"
    security_secure_file "${file}" && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    local perms
    perms="$(stat -c '%a' "${file}" 2>/dev/null)"
    [ "${perms}" = "600" ]
}
