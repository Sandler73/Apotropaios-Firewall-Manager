#!/usr/bin/env bats
# ==============================================================================
# File:         tests/unit/rule_engine.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Unit tests for the rule engine module — rule index CRUD,
#               state management, persistence, and field updates.
#               Tested without actual firewall backends (index-only).
# ==============================================================================

load '../helpers/test_helper'

# Helper: initialize rule subsystems for each test
_init_rules() {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    mkdir -p "${rules_dir}"
    rule_index_init "${rules_dir}" 2>/dev/null
    rule_state_init "${rules_dir}" 2>/dev/null
}

# Helper: add a test rule to the index (no backend dispatch)
_add_test_rule() {
    local rule_id="$1"
    local action="${2:-accept}"
    local port="${3:-443}"
    local duration="${4:-permanent}"
    local ttl="${5:-0}"

    declare -A rec=()
    rec[rule_id]="${rule_id}"
    rec[backend]="iptables"
    rec[direction]="inbound"
    rec[action]="${action}"
    rec[protocol]="tcp"
    rec[src_ip]=""
    rec[dst_ip]=""
    rec[src_port]=""
    rec[dst_port]="${port}"
    rec[interface]=""
    rec[chain]=""
    rec[table]=""
    rec[zone]=""
    rec[set_name]=""
    rec[duration_type]="${duration}"
    rec[ttl]="${ttl}"
    rec[description]="test rule ${port}"
    rec[state]="active"
    rec[created_at]="$(util_timestamp)"
    rec[activated_at]="$(util_timestamp)"
    rec[expires_at]=""

    rule_index_add "rec"
}

# ==============================================================================
# Rule Index CRUD
# ==============================================================================

@test "rule_index: add and retrieve a rule" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    _add_test_rule "${id}" "drop" "22"

    declare -A got=()
    rule_index_get "${id}" "got"
    [ "${got[rule_id]}" = "${id}" ]
    [ "${got[action]}" = "drop" ]
    [ "${got[dst_port]}" = "22" ]
}

@test "rule_index: count increments on add" {
    _init_rules
    local before
    before="$(rule_index_count)"
    _add_test_rule "$(security_generate_uuid)" "accept" "80"
    _add_test_rule "$(security_generate_uuid)" "drop" "22"
    local after
    after="$(rule_index_count)"
    [ "${after}" -eq "$((before + 2))" ]
}

@test "rule_index: remove decrements count" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    _add_test_rule "${id}" "accept" "443"
    local before
    before="$(rule_index_count)"
    rule_index_remove "${id}"
    local after
    after="$(rule_index_count)"
    [ "${after}" -eq "$((before - 1))" ]
}

@test "rule_index: get returns E_RULE_NOT_FOUND for missing ID" {
    _init_rules
    declare -A tmp=()
    rule_index_get "00000000-0000-4000-0000-000000000000" "tmp" && _rc=0 || _rc=$?
    [ "${_rc}" -eq "${E_RULE_NOT_FOUND}" ]
}

@test "rule_index: update_field changes a value" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    _add_test_rule "${id}" "accept" "443"
    rule_index_update_field "${id}" "state" "inactive"

    declare -A got=()
    rule_index_get "${id}" "got"
    [ "${got[state]}" = "inactive" ]
}

@test "rule_index: list_ids returns all added IDs" {
    _init_rules
    local id1 id2 id3
    id1="$(security_generate_uuid)"
    id2="$(security_generate_uuid)"
    id3="$(security_generate_uuid)"
    _add_test_rule "${id1}" "accept" "80"
    _add_test_rule "${id2}" "drop" "22"
    _add_test_rule "${id3}" "reject" "25"

    local ids
    ids="$(rule_index_list_ids)"
    [[ "${ids}" == *"${id1}"* ]]
    [[ "${ids}" == *"${id2}"* ]]
    [[ "${ids}" == *"${id3}"* ]]
}

# ==============================================================================
# Rule Index Persistence
# ==============================================================================

@test "rule_index: save creates file on disk" {
    _init_rules
    _add_test_rule "$(security_generate_uuid)" "accept" "443"
    [ -f "${TEST_TMPDIR}/data/rules/${APOTROPAIOS_RULE_INDEX_FILE}" ]
}

@test "rule_index: load restores data after clear" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    _add_test_rule "${id}" "drop" "8080"

    # Clear memory
    _RULE_INDEX_IDS=()
    unset _RULE_INDEX_DATA 2>/dev/null || true
    declare -gA _RULE_INDEX_DATA=()

    # Reload
    rule_index_load

    declare -A got=()
    rule_index_get "${id}" "got"
    [ "${got[dst_port]}" = "8080" ]
    [ "${got[action]}" = "drop" ]
}

@test "rule_index: handles multiple save/load cycles" {
    _init_rules
    local i id
    for i in 1 2 3 4 5; do
        id="$(security_generate_uuid)"
        _add_test_rule "${id}" "accept" "800${i}"
    done

    local count_before
    count_before="$(rule_index_count)"

    _RULE_INDEX_IDS=()
    unset _RULE_INDEX_DATA 2>/dev/null || true
    declare -gA _RULE_INDEX_DATA=()

    rule_index_load
    local count_after
    count_after="$(rule_index_count)"
    [ "${count_before}" -eq "${count_after}" ]
}

# ==============================================================================
# Rule State Management
# ==============================================================================

@test "rule_state: set and get active state" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    rule_state_set "${id}" "active" "permanent" "0"
    local state
    state="$(rule_state_get "${id}")"
    [ "${state}" = "active" ]
}

@test "rule_state: set and get inactive state" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    rule_state_set "${id}" "inactive" "permanent" "0"
    local state
    state="$(rule_state_get "${id}")"
    [ "${state}" = "inactive" ]
}

@test "rule_state: temporary rule is not expired when TTL is future" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    rule_state_set "${id}" "active" "temporary" "3600"
    rule_state_is_expired "${id}" && _expired=1 || _expired=0
    [ "${_expired}" -eq 0 ]
}

@test "rule_state: temporary rule is expired when TTL is past" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    rule_state_set "${id}" "active" "temporary" "1"
    local past
    past="$(( $(util_timestamp_epoch) - 100 ))"
    _RULE_STATE_EXPIRES["${id}"]="${past}"
    rule_state_is_expired "${id}" && _expired=1 || _expired=0
    [ "${_expired}" -eq 1 ]
}

@test "rule_state: time_remaining is positive for future expiry" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    rule_state_set "${id}" "active" "temporary" "7200"
    local remaining
    remaining="$(rule_state_time_remaining "${id}")"
    [ "${remaining}" -gt 0 ]
}

@test "rule_state: time_remaining is 0 for expired rule" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    rule_state_set "${id}" "active" "temporary" "1"
    _RULE_STATE_EXPIRES["${id}"]="$(( $(util_timestamp_epoch) - 100 ))"
    local remaining
    remaining="$(rule_state_time_remaining "${id}")"
    [ "${remaining}" -eq 0 ]
}

@test "rule_state: permanent rule is never expired" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    rule_state_set "${id}" "active" "permanent" "0"
    rule_state_is_expired "${id}" && _expired=1 || _expired=0
    [ "${_expired}" -eq 0 ]
}

@test "rule_state: remove clears state" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    rule_state_set "${id}" "active" "permanent" "0"
    rule_state_remove "${id}"
    rule_state_get "${id}" && _found=1 || _found=0
    [ "${_found}" -eq 0 ]
}

# ==============================================================================
# Rule Index Formatted Output
# ==============================================================================

@test "rule_index_list_formatted: shows 'No rules' when empty" {
    _init_rules
    local output
    output="$(rule_index_list_formatted 2>/dev/null)"
    [[ "${output}" == *"No rules"* ]]
}

@test "rule_index_list_formatted: shows rule ID when rules exist" {
    _init_rules
    local id
    id="$(security_generate_uuid)"
    _add_test_rule "${id}" "accept" "443"
    local output
    output="$(rule_index_list_formatted 2>/dev/null)"
    [[ "${output}" == *"${id}"* ]]
}
