#!/usr/bin/env bats
# ==============================================================================
# File:         tests/unit/logging.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Unit tests for logging and core utility functions.
# ==============================================================================

load '../helpers/test_helper'

# ==============================================================================
# Log Level Validation
# ==============================================================================

@test "validate_log_level: accepts DEBUG" {
    run validate_log_level "DEBUG"
    [ "$status" -eq 0 ]
}

@test "validate_log_level: accepts debug (lowercase)" {
    run validate_log_level "debug"
    [ "$status" -eq 0 ]
}

@test "validate_log_level: accepts numeric level 2" {
    run validate_log_level "2"
    [ "$status" -eq 0 ]
}

@test "validate_log_level: rejects invalid level" {
    run validate_log_level "VERBOSE"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# Logging Initialization
# ==============================================================================

@test "log_init: creates log file" {
    run log_init "${TEST_TMPDIR}/data/logs" "${LOG_LEVEL_INFO}"
    [ "$status" -eq 0 ]
    [ -n "$(ls "${TEST_TMPDIR}/data/logs/"apotropaios-*.log 2>/dev/null)" ]
}

@test "log_init: rejects path traversal in log dir" {
    run log_init "/tmp/../../../evil" "${LOG_LEVEL_INFO}"
    [ "$status" -ne 0 ]
}

@test "log_set_level: changes log level" {
    # Test the contract directly: log_set_level modifies APOTROPAIOS_LOG_LEVEL
    # Avoid log_init FD operations in BATS subshell (CI/CD Lesson #2)
    APOTROPAIOS_LOG_LEVEL="${LOG_LEVEL_INFO}"
    APOTROPAIOS_LOG_INITIALIZED=0
    log_set_level "WARNING" 2>/dev/null && _rc=0 || _rc=$?
    [ "${APOTROPAIOS_LOG_LEVEL}" -eq "${LOG_LEVEL_WARNING}" ]
}

# ==============================================================================
# Log Sanitization (test contract directly — CI/CD Lesson #2)
# ==============================================================================

@test "log sanitize: masks password fields" {
    local raw="user=admin password=secret123 action=login"
    local sanitized
    sanitized="$(_log_sanitize_message "${raw}")"
    [[ "${sanitized}" != *"secret123"* ]]
    [[ "${sanitized}" == *"***MASKED***"* ]]
}

@test "log sanitize: masks token fields" {
    local raw="token=abc123xyz"
    local sanitized
    sanitized="$(_log_sanitize_message "${raw}")"
    [[ "${sanitized}" != *"abc123xyz"* ]]
}

@test "log sanitize: preserves non-sensitive data" {
    local raw="port=8080 protocol=tcp direction=inbound"
    local sanitized
    sanitized="$(_log_sanitize_message "${raw}")"
    [[ "${sanitized}" == *"port=8080"* ]]
    [[ "${sanitized}" == *"protocol=tcp"* ]]
}

# ==============================================================================
# Correlation ID Generation
# ==============================================================================

@test "log_generate_correlation_id: produces non-empty string" {
    local cid
    cid="$(log_generate_correlation_id)"
    [ -n "${cid}" ]
    [ "${#cid}" -ge 8 ]
}

@test "log_generate_correlation_id: produces unique IDs" {
    local cid1 cid2
    cid1="$(log_generate_correlation_id)"
    cid2="$(log_generate_correlation_id)"
    [ "${cid1}" != "${cid2}" ]
}

# ==============================================================================
# Utility Functions
# ==============================================================================

@test "util_to_lower: converts uppercase" {
    run util_to_lower "HELLO"
    [ "$output" = "hello" ]
}

@test "util_to_upper: converts lowercase" {
    run util_to_upper "hello"
    [ "$output" = "HELLO" ]
}

@test "util_trim: removes surrounding whitespace" {
    run util_trim "  hello  "
    [ "$output" = "hello" ]
}

@test "util_is_command_available: finds bash" {
    run util_is_command_available "bash"
    [ "$status" -eq 0 ]
}

@test "util_is_command_available: rejects nonexistent command" {
    run util_is_command_available "definitely_not_a_real_command_xyz"
    [ "$status" -eq 1 ]
}

@test "util_array_contains: finds existing element" {
    local -a arr=("one" "two" "three")
    run util_array_contains "two" "${arr[@]}"
    [ "$status" -eq 0 ]
}

@test "util_array_contains: rejects missing element" {
    local -a arr=("one" "two" "three")
    run util_array_contains "four" "${arr[@]}"
    [ "$status" -eq 1 ]
}

@test "util_human_duration: formats seconds correctly" {
    run util_human_duration "3661"
    [[ "$output" == *"1h"* ]]
    [[ "$output" == *"1m"* ]]
    [[ "$output" == *"1s"* ]]
}

@test "util_timestamp: produces ISO 8601 format" {
    local ts
    ts="$(util_timestamp)"
    [[ "${ts}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# ==============================================================================
# Security Functions
# ==============================================================================

@test "security_generate_uuid: produces valid UUID format" {
    local uuid
    uuid="$(security_generate_uuid)"
    [[ "${uuid}" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[a-f0-9]{4}-[a-f0-9]{12}$ ]]
}

@test "security_generate_uuid: produces unique UUIDs" {
    local uuid1 uuid2
    uuid1="$(security_generate_uuid)"
    uuid2="$(security_generate_uuid)"
    [ "${uuid1}" != "${uuid2}" ]
}

@test "security_file_checksum: produces SHA-256 of known file" {
    local testfile="${TEST_TMPDIR}/checksum_test.txt"
    printf 'test content' > "${testfile}"
    local checksum
    checksum="$(security_file_checksum "${testfile}")"
    [ -n "${checksum}" ]
    [ "${#checksum}" -eq 64 ]
}

@test "security_verify_checksum: validates matching checksum" {
    local testfile="${TEST_TMPDIR}/verify_test.txt"
    printf 'test content' > "${testfile}"
    local checksum
    checksum="$(security_file_checksum "${testfile}")"
    run security_verify_checksum "${testfile}" "${checksum}"
    [ "$status" -eq 0 ]
}

@test "security_verify_checksum: rejects wrong checksum" {
    local testfile="${TEST_TMPDIR}/verify_fail.txt"
    printf 'test content' > "${testfile}"
    run security_verify_checksum "${testfile}" "0000000000000000000000000000000000000000000000000000000000000000"
    [ "$status" -ne 0 ]
}

# ==============================================================================
# Error Handling
# ==============================================================================

@test "error_retry: succeeds on first try" {
    run error_retry 3 1 true
    [ "$status" -eq 0 ]
}

@test "error_retry: fails after max retries" {
    run error_retry 2 0 false
    [ "$status" -ne 0 ]
}
