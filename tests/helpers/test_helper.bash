#!/usr/bin/env bash
# ==============================================================================
# File:         tests/helpers/test_helper.bash
# Project:      Apotropaios - Firewall Manager
# Description:  Shared BATS test setup/teardown following CI/CD Lesson #6.
#               Libraries are sourced at FILE LEVEL (not inside setup) so that
#               'declare -A' creates global associative arrays. When sourced
#               inside a function, 'declare -A' creates locals that are lost
#               when the function returns, causing UUID-keyed lookups to fail
#               with "value too great for base" as bash falls back to indexed
#               array arithmetic evaluation.
# ==============================================================================

# Resolve project root
HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${HELPER_DIR}/../.." && pwd)"
SCRIPT_PATH="${PROJECT_ROOT}/apotropaios.sh"
STUBS_DIR="${HELPER_DIR}/../stubs"
FIXTURES_DIR="${HELPER_DIR}/../fixtures"
export STUBS_DIR PROJECT_ROOT

# ==============================================================================
# Source libraries at FILE LEVEL (critical for associative array inheritance)
# Disable strict mode before sourcing (CI/CD Lesson #6)
# ==============================================================================
set +e
set +u
set +o pipefail

source "${PROJECT_ROOT}/lib/core/constants.sh"
source "${PROJECT_ROOT}/lib/core/logging.sh"
source "${PROJECT_ROOT}/lib/core/errors.sh"
source "${PROJECT_ROOT}/lib/core/validation.sh"
source "${PROJECT_ROOT}/lib/core/security.sh"
source "${PROJECT_ROOT}/lib/core/utils.sh"
source "${PROJECT_ROOT}/lib/detection/os_detect.sh"
source "${PROJECT_ROOT}/lib/detection/fw_detect.sh"
source "${PROJECT_ROOT}/lib/firewall/common.sh"
source "${PROJECT_ROOT}/lib/firewall/iptables.sh"
source "${PROJECT_ROOT}/lib/firewall/nftables.sh"
source "${PROJECT_ROOT}/lib/firewall/firewalld.sh"
source "${PROJECT_ROOT}/lib/firewall/ufw.sh"
source "${PROJECT_ROOT}/lib/firewall/ipset.sh"
source "${PROJECT_ROOT}/lib/rules/rule_index.sh"
source "${PROJECT_ROOT}/lib/rules/rule_state.sh"
source "${PROJECT_ROOT}/lib/rules/rule_engine.sh"
source "${PROJECT_ROOT}/lib/rules/rule_import.sh"
source "${PROJECT_ROOT}/lib/backup/backup.sh"
source "${PROJECT_ROOT}/lib/backup/restore.sh"
source "${PROJECT_ROOT}/lib/backup/immutable.sh"
source "${PROJECT_ROOT}/lib/install/installer.sh"
source "${PROJECT_ROOT}/lib/menu/menu_main.sh"

# Run OS detection once at file level (inherited by all test subshells)
os_detect 2>/dev/null || true
fw_detect_all 2>/dev/null || true

# ==============================================================================
# Setup function — called before each @test in its subshell
# Only creates per-test temporary state; does NOT re-source libraries.
# ==============================================================================
helper_setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export TEST_TMPDIR

    # Create runtime directories in temp
    mkdir -p "${TEST_TMPDIR}/data/logs"
    mkdir -p "${TEST_TMPDIR}/data/rules"
    mkdir -p "${TEST_TMPDIR}/data/backups"

    # Stubs on PATH (works for exec'd commands in child processes)
    export PATH="${STUBS_DIR}:${PATH}"

    # Disable strict mode for test context
    set +e
    set +u
    set +o pipefail

    # Reset mutable state for test isolation
    # CRITICAL: Do NOT use 'VAR=()' on associative arrays — this strips the -A
    # attribute in bash subshells. Use unset + declare -A instead.

    # Rule index: clear in-memory data (each test starts fresh)
    _RULE_INDEX_IDS=()
    unset _RULE_INDEX_DATA 2>/dev/null || true
    declare -gA _RULE_INDEX_DATA=()
    _RULE_INDEX_FILE=""
    _RULE_INDEX_LOADED=0

    # Rule state: clear in-memory data
    unset _RULE_STATE_MAP 2>/dev/null || true
    unset _RULE_STATE_TYPE 2>/dev/null || true
    unset _RULE_STATE_TTL 2>/dev/null || true
    unset _RULE_STATE_CREATED 2>/dev/null || true
    unset _RULE_STATE_EXPIRES 2>/dev/null || true
    declare -gA _RULE_STATE_MAP=()
    declare -gA _RULE_STATE_TYPE=()
    declare -gA _RULE_STATE_TTL=()
    declare -gA _RULE_STATE_CREATED=()
    declare -gA _RULE_STATE_EXPIRES=()
    _RULE_STATE_FILE=""

    # Backup state
    _BACKUP_DIR=""
    _BACKUP_LAST_FILE=""

    # Logging: reset mutable state (don't touch FD — avoid issues)
    APOTROPAIOS_LOG_INITIALIZED=0
    APOTROPAIOS_LOG_FILE=""
    APOTROPAIOS_LOG_FD=""
    APOTROPAIOS_LOG_ENTRY_COUNT=0

    # Firewall backend state
    FW_ACTIVE_BACKEND=""
}

# Teardown function — called after each @test
helper_teardown() {
    # Kill any background processes spawned by tests
    jobs -p 2>/dev/null | xargs kill 2>/dev/null || true
    wait 2>/dev/null || true

    # Remove temp directory
    rm -rf "${TEST_TMPDIR}" 2>/dev/null || true
}

# Convenience: call these in your .bats files
setup() {
    helper_setup
}

teardown() {
    helper_teardown
}
