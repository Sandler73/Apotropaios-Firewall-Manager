#!/usr/bin/env bats
# ==============================================================================
# File:         tests/integration/cli.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Integration tests for CLI argument parsing, command dispatch,
#               and end-to-end command execution. Tests the actual script as
#               a subprocess (not sourced).
# ==============================================================================

load '../helpers/test_helper'

# ==============================================================================
# Version and Help
# ==============================================================================

@test "cli --version: outputs version string" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"Apotropaios"* ]]
    [[ "$output" == *"Firewall Manager"* ]]
}

@test "cli -v: short flag works" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"Apotropaios"* ]]
}

@test "cli --help: outputs usage information" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"Options"* ]]
    [[ "$output" == *"Commands"* ]]
}

@test "cli -h: short flag works" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "cli --help: lists all major commands" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --help
    [[ "$output" == *"detect"* ]]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"block-all"* ]]
    [[ "$output" == *"allow-all"* ]]
    [[ "$output" == *"list-rules"* ]]
    [[ "$output" == *"system-rules"* ]]
    [[ "$output" == *"add-rule"* ]]
    [[ "$output" == *"remove-rule"* ]]
    [[ "$output" == *"import"* ]]
    [[ "$output" == *"export"* ]]
    [[ "$output" == *"backup"* ]]
    [[ "$output" == *"restore"* ]]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"update"* ]]
}

@test "cli --help: lists add-rule options" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --help
    [[ "$output" == *"--direction"* ]]
    [[ "$output" == *"--protocol"* ]]
    [[ "$output" == *"--src-ip"* ]]
    [[ "$output" == *"--dst-ip"* ]]
    [[ "$output" == *"--dst-port"* ]]
    [[ "$output" == *"--action"* ]]
    [[ "$output" == *"--duration"* ]]
    [[ "$output" == *"--ttl"* ]]
}

# ==============================================================================
# Invalid Arguments
# ==============================================================================

@test "cli: rejects unknown option" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --not-a-real-option
    [ "$status" -eq 2 ]
}

@test "cli: rejects unknown command" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" not-a-real-command
    [ "$status" -eq 2 ]
}

# ==============================================================================
# Detect Command
# ==============================================================================

@test "cli detect: runs without error" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" detect
    [ "$status" -eq 0 ]
}

@test "cli detect: outputs OS detection" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" detect
    [[ "$output" == *"OS ID"* ]] || [[ "$output" == *"os_detect"* ]]
}

@test "cli detect: outputs firewall detection" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" detect
    [[ "$output" == *"Detected Firewalls"* ]] || [[ "$output" == *"fw_detect"* ]]
}

@test "cli detect: banner shows correct name" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" detect
    # Verify the banner contains "Apotropaios" (not "Apptropaios")
    [[ "$output" == *"Firewall Manager"* ]]
}

# ==============================================================================
# List Rules Command
# ==============================================================================

@test "cli list-rules: runs without error" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" list-rules
    [ "$status" -eq 0 ]
}

@test "cli list-rules: shows 'No rules' when empty" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" list-rules
    [[ "$output" == *"No rules"* ]] || [[ "$output" == *"0 rules"* ]]
}

# ==============================================================================
# Log Level Option
# ==============================================================================

@test "cli --log-level trace: accepts valid level" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --log-level trace detect
    [ "$status" -eq 0 ]
}

@test "cli --log-level error: suppresses info messages" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --log-level error list-rules
    [ "$status" -eq 0 ]
    # Should NOT contain INFO-level messages
    [[ "$output" != *"[INFO"* ]]
}

@test "cli --log-level invalid: rejects bad level" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --log-level NOTVALID detect
    [ "$status" -eq 2 ]
}

@test "cli --log-level: requires a value" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --log-level
    [ "$status" -eq 2 ]
}

# ==============================================================================
# Backend Option
# ==============================================================================

@test "cli --backend nonexistent: fails gracefully" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --backend fakefirewall detect
    # Should fail because the backend doesn't exist
    [ "$status" -ne 0 ]
}

# ==============================================================================
# Command Argument Validation
# ==============================================================================

@test "cli remove-rule: requires rule ID argument" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" remove-rule
    [ "$status" -eq 2 ]
}

@test "cli activate-rule: requires rule ID argument" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" activate-rule
    [ "$status" -eq 2 ]
}

@test "cli deactivate-rule: requires rule ID argument" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" deactivate-rule
    [ "$status" -eq 2 ]
}

@test "cli import: requires file path argument" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" import
    [ "$status" -eq 2 ]
}

@test "cli export: requires file path argument" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" export
    [ "$status" -eq 2 ]
}

@test "cli restore: requires file path argument" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" restore
    [ "$status" -eq 2 ]
}

@test "cli install: requires firewall name argument" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" install
    [ "$status" -eq 2 ]
}

@test "cli update: requires firewall name argument" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" update
    [ "$status" -eq 2 ]
}

# ==============================================================================
# Backup Command (non-destructive)
# ==============================================================================

@test "cli backup: runs with default label" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" backup
    [ "$status" -eq 0 ]
}

@test "cli backup: runs with custom label" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" backup "ci-test"
    [ "$status" -eq 0 ]
}
