#!/usr/bin/env bats
# ==============================================================================
# File:         tests/security/injection.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Security-focused tests for injection prevention, path traversal,
#               metacharacter rejection, and input boundary enforcement.
#               Maps to CWE-20 (Input Validation), CWE-22 (Path Traversal),
#               CWE-78 (OS Command Injection), CWE-117 (Log Injection),
#               CWE-200 (Information Disclosure), CWE-377 (Insecure Temp File),
#               CWE-532 (Sensitive Data in Logs), CWE-732 (Insecure Permissions).
# ==============================================================================

load '../helpers/test_helper'

# ==============================================================================
# CWE-78: OS Command Injection — Shell Metacharacter Rejection
# ==============================================================================

@test "CWE-78: sanitize_input strips semicolons" {
    run sanitize_input "safe;whoami"
    [[ "$output" != *";"* ]]
}

@test "CWE-78: sanitize_input strips backticks" {
    run sanitize_input 'safe`id`text'
    [[ "$output" != *'`'* ]]
}

@test "CWE-78: sanitize_input strips dollar signs" {
    run sanitize_input 'safe$USER'
    [[ "$output" != *'$'* ]]
}

@test "CWE-78: sanitize_input strips pipe characters" {
    run sanitize_input "safe|cat /etc/passwd"
    [[ "$output" != *"|"* ]]
}

@test "CWE-78: sanitize_input strips ampersands" {
    run sanitize_input "safe&background"
    [[ "$output" != *"&"* ]]
}

@test "CWE-78: sanitize_input strips parentheses" {
    run sanitize_input "safe(subshell)"
    [[ "$output" != *"("* ]]
    [[ "$output" != *")"* ]]
}

@test "CWE-78: sanitize_input strips braces" {
    run sanitize_input "safe{expansion}"
    [[ "$output" != *"{"* ]]
    [[ "$output" != *"}"* ]]
}

@test "CWE-78: sanitize_input strips redirects" {
    run sanitize_input "safe>/tmp/evil"
    [[ "$output" != *">"* ]]
}

@test "CWE-78: _contains_shell_meta detects all metacharacters" {
    local -a dangerous=(
        "has;semicolon"
        "has|pipe"
        "has&amp"
        'has`backtick'
        'has$dollar'
        "has(paren"
        "has)paren"
        "has{brace"
        "has}brace"
        'has\backslash'
        "has<redirect"
        "has>redirect"
        "has!bang"
        "has#hash"
    )
    local s
    for s in "${dangerous[@]}"; do
        _contains_shell_meta "${s}" || {
            echo "MISSED: ${s}"
            return 1
        }
    done
}

@test "CWE-78: _contains_shell_meta passes clean strings" {
    local -a safe=(
        "normal-text"
        "file_name.conf"
        "/path/to/file"
        "192.168.1.0/24"
        "hello world"
        "rule-description-2026"
        "user@host"
    )
    local s
    for s in "${safe[@]}"; do
        ! _contains_shell_meta "${s}" || {
            echo "FALSE POSITIVE: ${s}"
            return 1
        }
    done
}

# ==============================================================================
# CWE-22: Path Traversal
# ==============================================================================

@test "CWE-22: validate_file_path rejects ../" {
    run validate_file_path "/etc/../../../tmp/evil"
    [ "$status" -eq 1 ]
}

@test "CWE-22: validate_file_path rejects embedded .." {
    run validate_file_path "/var/log/../../etc/shadow"
    [ "$status" -eq 1 ]
}

@test "CWE-22: validate_file_path rejects double-dot directory" {
    run validate_file_path "/tmp/../tmp/test"
    [ "$status" -eq 1 ]
}

@test "CWE-22: validate_file_path allows single dots in filenames" {
    run validate_file_path "/tmp/file.conf"
    [ "$status" -eq 0 ]
}

@test "CWE-22: validate_file_path allows multiple extensions" {
    run validate_file_path "/tmp/backup.tar.gz"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# CWE-20: Improper Input Validation — Boundary Tests
# ==============================================================================

@test "CWE-20: sanitize_input enforces MAX_INPUT_LENGTH" {
    local long_input
    long_input="$(printf 'A%.0s' $(seq 1 5000))"
    run sanitize_input "${long_input}"
    [ "${#output}" -le "${MAX_INPUT_LENGTH}" ]
}

@test "CWE-20: validate_port rejects port 0" {
    run validate_port "0"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_port rejects port 65536" {
    run validate_port "65536"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_port rejects negative numbers" {
    run validate_port "-1"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_port rejects non-numeric" {
    run validate_port "abc"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_ipv4 rejects octet > 255" {
    run validate_ipv4 "256.1.1.1"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_ipv4 rejects injection in IP" {
    run validate_ipv4 "127.0.0.1;whoami"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_cidr rejects prefix > 32 for IPv4" {
    run validate_cidr "10.0.0.0/33"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_protocol rejects arbitrary strings" {
    run validate_protocol "http"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_rule_id rejects non-UUID format" {
    run validate_rule_id "not-a-uuid"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_rule_id rejects empty input" {
    run validate_rule_id ""
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_rule_action rejects unknown actions" {
    run validate_rule_action "execute"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_rule_action rejects 2 terminal actions" {
    run validate_rule_action "drop,accept"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_conn_state rejects invalid states" {
    run validate_conn_state "bogus"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_log_prefix rejects > 29 chars" {
    run validate_log_prefix "$(printf 'A%.0s' $(seq 1 35))"
    [ "$status" -eq 1 ]
}

@test "CWE-20: validate_rate_limit rejects bad format" {
    run validate_rate_limit "fast"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# CWE-117: Log Injection — Sensitive Data Masking
# ==============================================================================

@test "CWE-117/532: log sanitize masks password fields" {
    local msg="user=admin password=secret123 token=abc"
    local sanitized
    sanitized="$(_log_sanitize_message "${msg}")"
    [[ "${sanitized}" != *"secret123"* ]]
}

@test "CWE-117/532: log sanitize masks token fields" {
    local msg="api_token=xyz789secret"
    local sanitized
    sanitized="$(_log_sanitize_message "${msg}")"
    [[ "${sanitized}" != *"xyz789secret"* ]]
}

@test "CWE-117/532: log sanitize preserves non-sensitive data" {
    local msg="user=admin host=server01 port=443"
    local sanitized
    sanitized="$(_log_sanitize_message "${msg}")"
    [[ "${sanitized}" == *"server01"* ]]
    [[ "${sanitized}" == *"443"* ]]
}

@test "CWE-117/532: log sanitize masks quoted password values" {
    local msg='config password="my secret pass" done'
    local sanitized
    sanitized="$(_log_sanitize_message "${msg}")"
    [[ "${sanitized}" != *"my secret pass"* ]]
}

@test "CWE-117/532: log sanitize masks JSON secret patterns" {
    local msg='{"password": "hunter2", "user": "admin"}'
    local sanitized
    sanitized="$(_log_sanitize_message "${msg}")"
    [[ "${sanitized}" != *"hunter2"* ]]
    [[ "${sanitized}" == *"admin"* ]]
}

@test "CWE-117/532: log sanitize masks Authorization headers" {
    local msg="Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.secret"
    local sanitized
    sanitized="$(_log_sanitize_message "${msg}")"
    [[ "${sanitized}" != *"eyJhbGciOiJIUzI1NiJ9"* ]]
    [[ "${sanitized}" == *"MASKED"* ]]
}

# ==============================================================================
# CWE-732: Insecure File Permissions
# ==============================================================================

@test "CWE-732: security_create_temp_file has 600 permissions" {
    local tmpf
    tmpf="$(security_create_temp_file "sec_test")"
    local perms
    perms="$(stat -c '%a' "${tmpf}" 2>/dev/null)"
    [ "${perms}" = "600" ]
    rm -f "${tmpf}" 2>/dev/null || true
}

@test "CWE-732: security_create_temp_dir has 700 permissions" {
    local tmpd
    tmpd="$(security_create_temp_dir "sec_test")"
    local perms
    perms="$(stat -c '%a' "${tmpd}" 2>/dev/null)"
    [ "${perms}" = "700" ]
    rm -rf "${tmpd}" 2>/dev/null || true
}

@test "CWE-732: security_secure_file sets 600" {
    local f="${TEST_TMPDIR}/permtest.txt"
    touch "${f}"
    chmod 644 "${f}"
    security_secure_file "${f}"
    local perms
    perms="$(stat -c '%a' "${f}" 2>/dev/null)"
    [ "${perms}" = "600" ]
}

@test "CWE-732: security_secure_dir sets 700" {
    local d="${TEST_TMPDIR}/permtest_dir"
    mkdir -p "${d}"
    chmod 755 "${d}"
    security_secure_dir "${d}"
    local perms
    perms="$(stat -c '%a' "${d}" 2>/dev/null)"
    [ "${perms}" = "700" ]
}

# ==============================================================================
# CWE-377: Insecure Temporary File
# ==============================================================================

@test "CWE-377: security_create_temp_file creates unique files" {
    local f1 f2
    f1="$(security_create_temp_file "uniq1")"
    f2="$(security_create_temp_file "uniq2")"
    [ "${f1}" != "${f2}" ]
    rm -f "${f1}" "${f2}" 2>/dev/null || true
}

@test "CWE-377: security_create_temp_file is not predictable" {
    local f
    f="$(security_create_temp_file "pred_test")"
    # Should contain random characters in the path
    [[ "${f}" =~ [a-zA-Z0-9]{6,} ]]
    rm -f "${f}" 2>/dev/null || true
}

# ==============================================================================
# CWE-200: Information Disclosure — Error Message Safety
# ==============================================================================

@test "CWE-200: validate_file_path does not leak system paths" {
    local output
    output="$(validate_file_path "/etc/../../../etc/shadow" 2>&1)"
    [[ "${output}" != *"/etc/shadow"* ]]
}

# ==============================================================================
# Cryptographic Integrity
# ==============================================================================

@test "integrity: SHA-256 checksum is 64 hex characters" {
    local f="${TEST_TMPDIR}/integ_test.txt"
    printf 'test data for checksum' > "${f}"
    local checksum
    checksum="$(security_file_checksum "${f}")"
    [ "${#checksum}" -eq 64 ]
    [[ "${checksum}" =~ ^[a-f0-9]{64}$ ]]
}

@test "integrity: verify_checksum detects tampering" {
    local f="${TEST_TMPDIR}/tamper_test.txt"
    printf 'original content' > "${f}"
    local checksum
    checksum="$(security_file_checksum "${f}")"
    printf 'tampered' >> "${f}"
    security_verify_checksum "${f}" "${checksum}" && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

# ==============================================================================
# Advisory Locking
# ==============================================================================

@test "locking: stale lock from dead PID is cleaned up" {
    local lockfile="${TEST_TMPDIR}/stale_sec.lock"
    echo "99999999" > "${lockfile}"
    security_acquire_lock "${lockfile}" 5 && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    security_release_lock "${lockfile}"
}

@test "locking: lock file contains current PID" {
    local lockfile="${TEST_TMPDIR}/pid_test.lock"
    security_acquire_lock "${lockfile}" 5
    local lock_pid
    lock_pid="$(cat "${lockfile}")"
    [ "${lock_pid}" = "$$" ]
    security_release_lock "${lockfile}"
}
