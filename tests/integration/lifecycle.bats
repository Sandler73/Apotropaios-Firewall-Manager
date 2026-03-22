#!/usr/bin/env bats
# ==============================================================================
# File:         tests/integration/lifecycle.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Integration tests for rule lifecycle, detection flow, and
#               backup operations. Tests multi-function flows without requiring
#               actual firewall backends (uses index/state tracking only).
# Notes:        - Uses declare -A (not local -A) for arrays passed via nameref
#                 to avoid BATS subshell nameref resolution issues
#               - Tests the contract directly (CI/CD Lesson #2)
# ==============================================================================

load '../helpers/test_helper'

# ==============================================================================
# OS Detection Flow
# ==============================================================================

@test "os_detect: detects an operating system" {
    [ -n "${OS_DETECTED_ID}" ]
    [ -n "${OS_DETECTED_FAMILY}" ]
    [ -n "${OS_DETECTED_PKG_MANAGER}" ]
}

@test "os_detect: family matches known categories" {
    local family="${OS_DETECTED_FAMILY}"
    [[ "${family}" == "debian" ]] || [[ "${family}" == "rhel" ]] || \
    [[ "${family}" == "arch" ]] || [[ "${family}" == "unknown" ]]
}

@test "os_detect: package manager is valid" {
    local pkg="${OS_DETECTED_PKG_MANAGER}"
    [[ "${pkg}" == "apt" ]] || [[ "${pkg}" == "dnf" ]] || \
    [[ "${pkg}" == "pacman" ]] || [[ "${pkg}" == "unknown" ]]
}

# ==============================================================================
# Firewall Detection Flow
# ==============================================================================

@test "fw_detect_all: completes without error" {
    run fw_detect_all
    [ "$status" -eq 0 ]
}

@test "fw_detect_all: populates detection arrays" {
    fw_detect_all 2>/dev/null
    local fw_name
    for fw_name in "${SUPPORTED_FW_LIST[@]}"; do
        local installed="${FW_DETECTED_INSTALLED[${fw_name}]:-unset}"
        [[ "${installed}" == "0" ]] || [[ "${installed}" == "1" ]]
    done
}

@test "fw_get_installed: returns space-separated list" {
    fw_detect_all 2>/dev/null
    local installed
    installed="$(fw_get_installed)"
    if [ -n "${installed}" ]; then
        local fw
        for fw in ${installed}; do
            util_array_contains "${fw}" "${SUPPORTED_FW_LIST[@]}"
        done
    fi
}

# ==============================================================================
# Rule Index Lifecycle
# Note: Arrays passed via nameref use 'declare -A' (not 'local -A')
# because BATS @test blocks are subshell functions where local namerefs
# may not resolve properly.
# ==============================================================================

@test "rule_index_init: initializes empty index" {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    run rule_index_init "${rules_dir}"
    [ "$status" -eq 0 ]
}

@test "rule_index_add: adds a rule record" {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    rule_index_init "${rules_dir}" 2>/dev/null

    local test_id
    test_id="$(security_generate_uuid)"

    declare -A record=()
    record[rule_id]="${test_id}"
    record[backend]="iptables"
    record[direction]="inbound"
    record[action]="accept"
    record[protocol]="tcp"
    record[src_ip]="any"
    record[dst_ip]="any"
    record[src_port]="any"
    record[dst_port]="443"
    record[duration_type]="permanent"
    record[ttl]="0"
    record[description]="test rule"
    record[state]="active"
    record[created_at]="now"
    record[activated_at]="now"
    record[expires_at]=""
    record[interface]=""
    record[chain]=""
    record[table]=""
    record[zone]=""
    record[set_name]=""

    run rule_index_add "record"
    [ "$status" -eq 0 ]
}

@test "rule_index_get: retrieves added rule" {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    rule_index_init "${rules_dir}" 2>/dev/null

    local test_id
    test_id="$(security_generate_uuid)"

    declare -A record=()
    record[rule_id]="${test_id}"
    record[backend]="iptables"
    record[direction]="inbound"
    record[action]="drop"
    record[protocol]="tcp"
    record[src_ip]="10.0.0.1"
    record[dst_ip]="any"
    record[src_port]="any"
    record[dst_port]="22"
    record[duration_type]="permanent"
    record[ttl]="0"
    record[description]="block ssh"
    record[state]="active"
    record[created_at]="now"
    record[activated_at]="now"
    record[expires_at]=""
    record[interface]=""
    record[chain]=""
    record[table]=""
    record[zone]=""
    record[set_name]=""

    rule_index_add "record"

    declare -A retrieved=()
    rule_index_get "${test_id}" "retrieved"
    [ "${retrieved[rule_id]}" = "${test_id}" ]
    [ "${retrieved[action]}" = "drop" ]
    [ "${retrieved[dst_port]}" = "22" ]
    [ "${retrieved[src_ip]}" = "10.0.0.1" ]
}

@test "rule_index_remove: removes a rule" {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    rule_index_init "${rules_dir}" 2>/dev/null

    local test_id
    test_id="$(security_generate_uuid)"

    declare -A record=()
    record[rule_id]="${test_id}"
    record[backend]="nftables"
    record[direction]="outbound"
    record[action]="accept"
    record[protocol]="udp"
    record[src_ip]="any"
    record[dst_ip]="any"
    record[src_port]="any"
    record[dst_port]="53"
    record[duration_type]="permanent"
    record[ttl]="0"
    record[description]="allow dns"
    record[state]="active"
    record[created_at]="now"
    record[activated_at]="now"
    record[expires_at]=""
    record[interface]=""
    record[chain]=""
    record[table]=""
    record[zone]=""
    record[set_name]=""

    rule_index_add "record"
    rule_index_remove "${test_id}" && _rc=0 || _rc=$?
    [ "$_rc" -eq 0 ]

    # Verify it's gone
    declare -A check=()
    rule_index_get "${test_id}" "check" && _found=1 || _found=0
    [ "$_found" -eq 0 ]
}

@test "rule_index_count: returns correct count" {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    rule_index_init "${rules_dir}" 2>/dev/null

    local count_before
    count_before="$(rule_index_count)"

    local test_id
    test_id="$(security_generate_uuid)"

    declare -A record=()
    record[rule_id]="${test_id}"
    record[backend]="ufw"
    record[direction]="inbound"
    record[action]="accept"
    record[protocol]="tcp"
    record[dst_port]="80"
    record[duration_type]="permanent"
    record[ttl]="0"
    record[state]="active"
    record[created_at]="now"
    record[activated_at]="now"
    record[expires_at]=""
    record[src_ip]=""
    record[dst_ip]=""
    record[src_port]=""
    record[interface]=""
    record[chain]=""
    record[table]=""
    record[zone]=""
    record[set_name]=""
    record[description]=""

    rule_index_add "record"

    local count_after
    count_after="$(rule_index_count)"
    [ "$count_after" -eq "$((count_before + 1))" ]
}

# ==============================================================================
# Rule Index Persistence (save/load cycle)
# ==============================================================================

@test "rule_index: survives save/load cycle" {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    rule_index_init "${rules_dir}" 2>/dev/null

    local id1 id2
    id1="$(security_generate_uuid)"
    id2="$(security_generate_uuid)"

    declare -A r1=()
    r1[rule_id]="${id1}"
    r1[backend]="iptables"
    r1[direction]="inbound"
    r1[action]="accept"
    r1[protocol]="tcp"
    r1[dst_port]="443"
    r1[duration_type]="permanent"
    r1[ttl]="0"
    r1[description]="https"
    r1[state]="active"
    r1[created_at]="now"
    r1[activated_at]="now"
    r1[expires_at]=""
    r1[src_ip]=""
    r1[dst_ip]=""
    r1[src_port]=""
    r1[interface]=""
    r1[chain]=""
    r1[table]=""
    r1[zone]=""
    r1[set_name]=""

    declare -A r2=()
    r2[rule_id]="${id2}"
    r2[backend]="nftables"
    r2[direction]="outbound"
    r2[action]="drop"
    r2[protocol]="udp"
    r2[dst_port]="5353"
    r2[duration_type]="temporary"
    r2[ttl]="3600"
    r2[description]="mdns block"
    r2[state]="active"
    r2[created_at]="now"
    r2[activated_at]="now"
    r2[expires_at]=""
    r2[src_ip]=""
    r2[dst_ip]=""
    r2[src_port]=""
    r2[interface]=""
    r2[chain]=""
    r2[table]=""
    r2[zone]=""
    r2[set_name]=""

    rule_index_add "r1"
    rule_index_add "r2"

    # Verify the file exists
    [ -f "${rules_dir}/${APOTROPAIOS_RULE_INDEX_FILE}" ]

    # Clear in-memory and reload
    _RULE_INDEX_IDS=()
    _RULE_INDEX_DATA=()

    rule_index_load

    # Verify data survived
    declare -A check1=()
    rule_index_get "${id1}" "check1"
    [ "${check1[dst_port]}" = "443" ]

    declare -A check2=()
    rule_index_get "${id2}" "check2"
    [ "${check2[action]}" = "drop" ]
    [ "${check2[duration_type]}" = "temporary" ]
}

# ==============================================================================
# Rule State Tracking
# ==============================================================================

@test "rule_state: tracks active state" {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    rule_state_init "${rules_dir}" 2>/dev/null

    local test_id
    test_id="$(security_generate_uuid)"

    rule_state_set "${test_id}" "active" "permanent" "0"

    local state
    state="$(rule_state_get "${test_id}")"
    [ "${state}" = "active" ]
}

@test "rule_state: tracks temporary rule with TTL" {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    rule_state_init "${rules_dir}" 2>/dev/null

    local test_id
    test_id="$(security_generate_uuid)"

    rule_state_set "${test_id}" "active" "temporary" "3600"

    # Should not be expired (3600s in the future)
    rule_state_is_expired "${test_id}" && _expired=1 || _expired=0
    [ "$_expired" -eq 0 ]

    # Should have remaining time
    local remaining
    remaining="$(rule_state_time_remaining "${test_id}")"
    [ "${remaining}" -gt 0 ]
}

@test "rule_state: detects expired rule" {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    rule_state_init "${rules_dir}" 2>/dev/null

    local test_id
    test_id="$(security_generate_uuid)"

    # Set via the function first (this creates all needed entries)
    rule_state_set "${test_id}" "active" "temporary" "1"

    # Now manually override the expiry to the past
    local past_epoch
    past_epoch="$(( $(util_timestamp_epoch) - 100 ))"
    _RULE_STATE_EXPIRES["${test_id}"]="${past_epoch}"

    rule_state_is_expired "${test_id}" && _expired=1 || _expired=0
    [ "$_expired" -eq 1 ]
}

# ==============================================================================
# Backup Creation
# ==============================================================================

@test "backup_init: initializes backup directory" {
    local backup_dir="${TEST_TMPDIR}/data/backups"
    run backup_init "${backup_dir}"
    [ "$status" -eq 0 ]
    [ -d "${backup_dir}" ]
}

@test "backup_create: creates backup archive" {
    local backup_dir="${TEST_TMPDIR}/data/backups"
    backup_init "${backup_dir}" 2>/dev/null

    run backup_create "test_backup"
    [ "$status" -eq 0 ]

    local backup_count
    backup_count="$(find "${backup_dir}" -name "*.tar.gz" -type f 2>/dev/null | wc -l)"
    [ "${backup_count}" -ge 1 ]
}

@test "backup_create: generates checksum file" {
    local backup_dir="${TEST_TMPDIR}/data/backups"
    backup_init "${backup_dir}" 2>/dev/null
    backup_create "checksum_test" 2>/dev/null

    local sha_count
    sha_count="$(find "${backup_dir}" -name "*.sha256" -type f 2>/dev/null | wc -l)"
    [ "${sha_count}" -ge 1 ]
}

# ==============================================================================
# Import/Export Cycle
# ==============================================================================

@test "rule_export_file: creates export file" {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    rule_index_init "${rules_dir}" 2>/dev/null

    local test_id
    test_id="$(security_generate_uuid)"

    declare -A record=()
    record[rule_id]="${test_id}"
    record[backend]="iptables"
    record[direction]="inbound"
    record[action]="accept"
    record[protocol]="tcp"
    record[dst_port]="80"
    record[duration_type]="permanent"
    record[ttl]="0"
    record[description]="web"
    record[state]="active"
    record[created_at]="now"
    record[activated_at]="now"
    record[expires_at]=""
    record[src_ip]=""
    record[dst_ip]=""
    record[src_port]=""
    record[interface]=""
    record[chain]=""
    record[table]=""
    record[zone]=""
    record[set_name]=""

    rule_index_add "record"

    local export_file="${TEST_TMPDIR}/exported_rules.conf"
    rule_export_file "${export_file}" && _rc=0 || _rc=$?
    [ "$_rc" -eq 0 ]
    [ -f "${export_file}" ]

    grep -q "direction=inbound" "${export_file}"
    grep -q "dst_port=80" "${export_file}"
}

# ==============================================================================
# CLI Argument Parsing
# ==============================================================================

@test "parse_args: handles --version flag" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"Apotropaios"* ]]
    [[ "$output" == *"1.1.0"* ]]
}

@test "parse_args: handles --help flag" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"Options"* ]]
}

@test "parse_args: rejects unknown option" {
    run bash "${PROJECT_ROOT}/apotropaios.sh" --totally-fake-option
    [ "$status" -eq 2 ]
}
