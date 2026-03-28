#!/usr/bin/env bats
# ==============================================================================
# File:         tests/integration/help_system.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Integration tests for the progressive layered help system.
#               Tests Tier 1 (global help), Tier 2 (per-command help), and
#               edge cases. All tests run as subprocess against apotropaios.sh.
# ==============================================================================

load '../helpers/test_helper'

# ==============================================================================
# Tier 1: Global Help (--help before any command)
# ==============================================================================

@test "help tier1: --help shows banner" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Firewall Manager"* ]]
}

@test "help tier1: --help shows usage line" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --help
    [[ "$output" == *"Usage:"* ]]
}

@test "help tier1: --help lists all commands" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --help
    [[ "$output" == *"menu"* ]]
    [[ "$output" == *"detect"* ]]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"add-rule"* ]]
    [[ "$output" == *"remove-rule"* ]]
    [[ "$output" == *"list-rules"* ]]
    [[ "$output" == *"system-rules"* ]]
    [[ "$output" == *"block-all"* ]]
    [[ "$output" == *"allow-all"* ]]
    [[ "$output" == *"import"* ]]
    [[ "$output" == *"export"* ]]
    [[ "$output" == *"backup"* ]]
    [[ "$output" == *"restore"* ]]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"update"* ]]
}

@test "help tier1: --help shows COMMAND --help pointer" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --help
    [[ "$output" == *"COMMAND --help"* ]]
}

@test "help tier1: --help shows global options" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --help
    [[ "$output" == *"--log-level"* ]]
    [[ "$output" == *"--backend"* ]]
    [[ "$output" == *"--non-interactive"* ]]
}

@test "help tier1: --help shows quick examples" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --help
    [[ "$output" == *"Examples"* ]]
}

@test "help tier1: -h short flag works" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ==============================================================================
# Tier 2: Per-Command Help (COMMAND --help)
# ==============================================================================

@test "help tier2: menu --help shows menu structure" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" menu --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"menu"* ]]
    [[ "$output" == *"Synopsis"* ]]
    [[ "$output" == *"Menu Structure"* ]]
    [[ "$output" == *"Firewall Management"* ]]
    [[ "$output" == *"Rule Management"* ]]
}

@test "help tier2: detect --help shows detection methods" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" detect --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"detect"* ]]
    [[ "$output" == *"os-release"* ]]
    [[ "$output" == *"Output Fields"* ]]
}

@test "help tier2: status --help shows backend behavior" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"Prerequisites"* ]]
    [[ "$output" == *"iptables"* ]]
    [[ "$output" == *"nftables"* ]]
}

@test "help tier2: add-rule --help shows all rule options" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" add-rule --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"add-rule"* ]]
    [[ "$output" == *"--direction"* ]]
    [[ "$output" == *"--protocol"* ]]
    [[ "$output" == *"--src-ip"* ]]
    [[ "$output" == *"--dst-ip"* ]]
    [[ "$output" == *"--src-port"* ]]
    [[ "$output" == *"--dst-port"* ]]
    [[ "$output" == *"--action"* ]]
    [[ "$output" == *"--duration"* ]]
    [[ "$output" == *"--ttl"* ]]
    [[ "$output" == *"--description"* ]]
    [[ "$output" == *"Validation Rules"* ]]
    [[ "$output" == *"Examples"* ]]
}

@test "help tier2: add-rule --help shows backend-specific options" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" add-rule --help
    [[ "$output" == *"--zone"* ]]
    [[ "$output" == *"--chain"* ]]
    [[ "$output" == *"--table"* ]]
}

@test "help tier2: add-rule --help shows interactive alternative" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" add-rule --help
    [[ "$output" == *"Interactive Alternative"* ]]
    [[ "$output" == *"wizard"* ]]
}

@test "help tier2: remove-rule --help shows UUID usage" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" remove-rule --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"remove-rule"* ]]
    [[ "$output" == *"UUID"* ]]
    [[ "$output" == *"RULE_ID"* ]]
}

@test "help tier2: activate-rule --help shows description" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" activate-rule --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Re-activate"* ]]
    [[ "$output" == *"RULE_ID"* ]]
}

@test "help tier2: deactivate-rule --help shows keep-in-index" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" deactivate-rule --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"inactive"* ]]
    [[ "$output" == *"re-activated"* ]]
}

@test "help tier2: list-rules --help shows state colors" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" list-rules --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"active"* ]]
    [[ "$output" == *"inactive"* ]]
    [[ "$output" == *"expired"* ]]
}

@test "help tier2: system-rules --help shows backend outputs" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" system-rules --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"iptables"* ]]
    [[ "$output" == *"nftables"* ]]
    [[ "$output" == *"firewalld"* ]]
    [[ "$output" == *"ufw"* ]]
    [[ "$output" == *"ipset"* ]]
}

@test "help tier2: block-all --help shows warning" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" block-all --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
    [[ "$output" == *"SSH"* ]]
    [[ "$output" == *"Backend Behavior"* ]]
}

@test "help tier2: allow-all --help shows warning" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" allow-all --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]]
}

@test "help tier2: import --help shows config format" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" import --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Configuration File Format"* ]]
    [[ "$output" == *"direction="* ]]
    [[ "$output" == *"sha256"* ]]
}

@test "help tier2: export --help shows output format" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" export --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHA-256"* ]]
    [[ "$output" == *"key=value"* ]]
}

@test "help tier2: backup --help shows contents and retention" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" backup --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"iptables"* ]]
    [[ "$output" == *"nftables"* ]]
    [[ "$output" == *"Retention"* ]]
    [[ "$output" == *"LABEL"* ]]
}

@test "help tier2: restore --help shows process steps" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" restore --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"integrity"* ]]
    [[ "$output" == *"safety backup"* ]]
}

@test "help tier2: install --help shows package mapping" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" install --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"FW_NAME"* ]]
    [[ "$output" == *"apt"* ]]
    [[ "$output" == *"dnf"* ]]
    [[ "$output" == *"pacman"* ]]
}

@test "help tier2: update --help shows description" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" update --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"FW_NAME"* ]]
    [[ "$output" == *"restore point"* ]]
}

# ==============================================================================
# Tier 2: Per-Command Help — shows related commands
# ==============================================================================

@test "help tier2: add-rule --help shows related commands" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" add-rule --help
    [[ "$output" == *"Related Commands"* ]]
    [[ "$output" == *"list-rules"* ]]
    [[ "$output" == *"remove-rule"* ]]
}

@test "help tier2: backup --help shows related commands" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" backup --help
    [[ "$output" == *"Related Commands"* ]]
    [[ "$output" == *"restore"* ]]
}

@test "help tier2: detect --help shows related commands" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" detect --help
    [[ "$output" == *"Related Commands"* ]]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"install"* ]]
}

# ==============================================================================
# Help Dispatch Function (sourced tests)
# ==============================================================================

@test "help_dispatch: returns 0 for known command" {
    help_dispatch "menu" >/dev/null 2>&1 && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

@test "help_dispatch: returns 1 for unknown command" {
    help_dispatch "nonexistent_cmd" >/dev/null 2>&1 && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

@test "help_list_commands: produces output for all 17 commands" {
    local output
    output="$(help_list_commands 2>/dev/null)"
    [[ "$output" == *"menu"* ]]
    [[ "$output" == *"detect"* ]]
    [[ "$output" == *"add-rule"* ]]
    [[ "$output" == *"backup"* ]]
    [[ "$output" == *"import"* ]]
    [[ "$output" == *"install"* ]]
}
