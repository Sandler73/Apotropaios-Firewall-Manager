#!/usr/bin/env bats
# ==============================================================================
# File:         tests/unit/errors.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Unit tests for error handling module — retry logic, fallback,
#               cleanup registration, assertion, safe_exec, error context.
# ==============================================================================

load '../helpers/test_helper'

# ==============================================================================
# Retry Logic
# ==============================================================================

@test "error_retry: succeeds on first attempt" {
    run error_retry 3 0 true
    [ "$status" -eq 0 ]
}

@test "error_retry: fails after exhausting retries" {
    run error_retry 2 0 false
    [ "$status" -ne 0 ]
}

@test "error_retry: retries correct number of times" {
    local counter_file="${TEST_TMPDIR}/retry_count"
    printf '0' > "${counter_file}"

    _test_retry_counter() {
        local c
        c="$(cat "${counter_file}")"
        c=$((c + 1))
        printf '%d' "${c}" > "${counter_file}"
        return 1  # Always fail
    }

    error_retry 3 0 _test_retry_counter 2>/dev/null && _rc=0 || _rc=$?
    local final_count
    final_count="$(cat "${counter_file}")"
    [ "${final_count}" -eq 3 ]
}

@test "error_retry: succeeds on Nth attempt" {
    local counter_file="${TEST_TMPDIR}/retry_succeed"
    printf '0' > "${counter_file}"

    _test_retry_succeed_on_3() {
        local c
        c="$(cat "${counter_file}")"
        c=$((c + 1))
        printf '%d' "${c}" > "${counter_file}"
        [ "${c}" -ge 3 ]
    }

    error_retry 5 0 _test_retry_succeed_on_3 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    local final_count
    final_count="$(cat "${counter_file}")"
    [ "${final_count}" -eq 3 ]
}

# ==============================================================================
# Fallback Logic
# ==============================================================================

@test "error_with_fallback: returns 0 when primary succeeds" {
    error_with_fallback "true" "false" "test" 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

@test "error_with_fallback: uses fallback when primary fails" {
    local marker="${TEST_TMPDIR}/fallback_marker"
    error_with_fallback "false" "touch '${marker}'" "test" 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    [ -f "${marker}" ]
}

@test "error_with_fallback: returns error when both fail" {
    error_with_fallback "false" "false" "test" 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

# ==============================================================================
# Cleanup Registration
# ==============================================================================

@test "error_register_cleanup: accepts a function name" {
    _test_cleanup() { true; }
    error_register_cleanup "_test_cleanup" 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

@test "error_register_cleanup: grows the cleanup stack" {
    local initial_size="${#_CLEANUP_STACK[@]}"
    _test_cleanup_a() { true; }
    _test_cleanup_b() { true; }
    error_register_cleanup "_test_cleanup_a" 2>/dev/null
    error_register_cleanup "_test_cleanup_b" 2>/dev/null
    local new_size="${#_CLEANUP_STACK[@]}"
    [ "${new_size}" -ge "$((initial_size + 2))" ]
}

@test "error_unregister_cleanup: removes a registered function" {
    _test_cleanup_unreg() { true; }
    error_register_cleanup "_test_cleanup_unreg" 2>/dev/null
    error_unregister_cleanup "_test_cleanup_unreg" 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

@test "error_unregister_cleanup: returns 1 for non-registered function" {
    error_unregister_cleanup "never_registered_func" && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

# ==============================================================================
# Assertions
# ==============================================================================

@test "error_assert: passes for true condition" {
    error_assert "true is true" true 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

@test "error_assert: fails for false condition" {
    error_assert "false is false" false 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

@test "error_assert: passes for command that succeeds" {
    error_assert "test -d /tmp" test -d /tmp 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

@test "error_assert: fails for command that fails" {
    error_assert "test nonexistent" test -f /nonexistent 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

# ==============================================================================
# Safe Execution
# ==============================================================================

@test "error_safe_exec: captures exit code 0 for success" {
    local rc_var=99
    error_safe_exec rc_var true
    [ "${rc_var}" -eq 0 ]
}

@test "error_safe_exec: captures non-zero exit code for failure" {
    local rc_var=0
    error_safe_exec rc_var false
    [ "${rc_var}" -ne 0 ]
}

@test "error_safe_exec: always returns 0 itself" {
    error_safe_exec _dummy false && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

# ==============================================================================
# Error Context
# ==============================================================================

@test "error_get_context: returns formatted string" {
    local ctx
    ctx="$(error_get_context)"
    [[ "${ctx}" == *"function="* ]]
    [[ "${ctx}" == *"line="* ]]
    [[ "${ctx}" == *"command="* ]]
}

# ==============================================================================
# Exit Code Constants
# ==============================================================================

@test "exit codes: E_SUCCESS is 0" {
    [ "${E_SUCCESS}" -eq 0 ]
}

@test "exit codes: E_GENERAL is 1" {
    [ "${E_GENERAL}" -eq 1 ]
}

@test "exit codes: E_USAGE is 2" {
    [ "${E_USAGE}" -eq 2 ]
}

@test "exit codes: E_PERMISSION is 3" {
    [ "${E_PERMISSION}" -eq 3 ]
}

@test "exit codes: all error codes are unique" {
    local -a codes=("${E_SUCCESS}" "${E_GENERAL}" "${E_USAGE}" "${E_PERMISSION}"
        "${E_OS_UNSUPPORTED}" "${E_FW_NOT_FOUND}" "${E_FW_NOT_RUNNING}" "${E_FW_INSTALL_FAIL}"
        "${E_RULE_INVALID}" "${E_RULE_EXISTS}" "${E_RULE_NOT_FOUND}" "${E_RULE_APPLY_FAIL}"
        "${E_RULE_REMOVE_FAIL}" "${E_RULE_IMPORT_FAIL}" "${E_BACKUP_FAIL}" "${E_RESTORE_FAIL}"
        "${E_VALIDATION_FAIL}" "${E_LOG_FAIL}" "${E_LOG_HANDLE_LOST}" "${E_LOCK_FAIL}"
        "${E_INTEGRITY_FAIL}" "${E_SIGNAL_RECEIVED}")
    local unique_count
    unique_count="$(printf '%s\n' "${codes[@]}" | sort -u | wc -l)"
    [ "${unique_count}" -eq "${#codes[@]}" ]
}
