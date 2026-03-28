#!/usr/bin/env bats
# ==============================================================================
# File:         tests/integration/import_export.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Integration tests for rule import/export round-trip and
#               configuration file validation.
# ==============================================================================

load '../helpers/test_helper'

_init_all() {
    local rules_dir="${TEST_TMPDIR}/data/rules"
    local backup_dir="${TEST_TMPDIR}/data/backups"
    mkdir -p "${rules_dir}" "${backup_dir}"
    rule_index_init "${rules_dir}" 2>/dev/null
    rule_state_init "${rules_dir}" 2>/dev/null
    backup_init "${backup_dir}" 2>/dev/null
}

# ==============================================================================
# Export Tests
# ==============================================================================

@test "rule_export_file: creates file on disk" {
    _init_all
    local id
    id="$(security_generate_uuid)"
    declare -A rec=()
    rec[rule_id]="${id}" rec[backend]="iptables" rec[direction]="inbound"
    rec[action]="accept" rec[protocol]="tcp" rec[dst_port]="443"
    rec[duration_type]="permanent" rec[ttl]="0" rec[description]="HTTPS"
    rec[state]="active" rec[created_at]="now" rec[activated_at]="now"
    rec[expires_at]="" rec[src_ip]="" rec[dst_ip]="" rec[src_port]=""
    rec[interface]="" rec[chain]="" rec[table]="" rec[zone]="" rec[set_name]=""
    rule_index_add "rec"

    local export_path="${TEST_TMPDIR}/export_test.conf"
    rule_export_file "${export_path}" 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
    [ -f "${export_path}" ]
}

@test "rule_export_file: output contains rule parameters" {
    _init_all
    local id
    id="$(security_generate_uuid)"
    declare -A rec=()
    rec[rule_id]="${id}" rec[backend]="nftables" rec[direction]="outbound"
    rec[action]="drop" rec[protocol]="udp" rec[dst_port]="5353"
    rec[duration_type]="temporary" rec[ttl]="3600" rec[description]="mDNS block"
    rec[state]="active" rec[created_at]="now" rec[activated_at]="now"
    rec[expires_at]="" rec[src_ip]="" rec[dst_ip]="" rec[src_port]=""
    rec[interface]="" rec[chain]="" rec[table]="" rec[zone]="" rec[set_name]=""
    rule_index_add "rec"

    local export_path="${TEST_TMPDIR}/content_test.conf"
    rule_export_file "${export_path}" 2>/dev/null

    grep -q "direction=outbound" "${export_path}"
    grep -q "action=drop" "${export_path}"
    grep -q "protocol=udp" "${export_path}"
    grep -q "dst_port=5353" "${export_path}"
    grep -q "duration_type=temporary" "${export_path}"
}

@test "rule_export_file: creates SHA-256 sidecar" {
    _init_all
    local id
    id="$(security_generate_uuid)"
    declare -A rec=()
    rec[rule_id]="${id}" rec[backend]="iptables" rec[direction]="inbound"
    rec[action]="accept" rec[protocol]="tcp" rec[dst_port]="80"
    rec[duration_type]="permanent" rec[ttl]="0" rec[description]="HTTP"
    rec[state]="active" rec[created_at]="now" rec[activated_at]="now"
    rec[expires_at]="" rec[src_ip]="" rec[dst_ip]="" rec[src_port]=""
    rec[interface]="" rec[chain]="" rec[table]="" rec[zone]="" rec[set_name]=""
    rule_index_add "rec"

    local export_path="${TEST_TMPDIR}/sha_test.conf"
    rule_export_file "${export_path}" 2>/dev/null
    [ -f "${export_path}.sha256" ]
}

@test "rule_export_file: exports multiple rules" {
    _init_all
    local i
    for i in 1 2 3; do
        local id
        id="$(security_generate_uuid)"
        declare -A rec=()
        rec[rule_id]="${id}" rec[backend]="iptables" rec[direction]="inbound"
        rec[action]="accept" rec[protocol]="tcp" rec[dst_port]="80${i}"
        rec[duration_type]="permanent" rec[ttl]="0" rec[description]="rule ${i}"
        rec[state]="active" rec[created_at]="now" rec[activated_at]="now"
        rec[expires_at]="" rec[src_ip]="" rec[dst_ip]="" rec[src_port]=""
        rec[interface]="" rec[chain]="" rec[table]="" rec[zone]="" rec[set_name]=""
        rule_index_add "rec"
    done

    local export_path="${TEST_TMPDIR}/multi_export.conf"
    rule_export_file "${export_path}" 2>/dev/null

    # Should have 3 non-comment lines
    local rule_lines
    rule_lines="$(grep -v '^#' "${export_path}" | grep -c 'direction=')"
    [ "${rule_lines}" -eq 3 ]
}

# ==============================================================================
# Import Tests — Dry Run
# ==============================================================================

@test "rule_import_file: dry run validates good config" {
    _init_all
    local fixture="${FIXTURES_DIR}/sample_rules.conf"
    # Copy fixture to temp (fixture is read-only)
    cp "${fixture}" "${TEST_TMPDIR}/import_test.conf"
    rule_import_file "${TEST_TMPDIR}/import_test.conf" 1 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}

@test "rule_import_file: dry run does not add rules to index" {
    _init_all
    local before
    before="$(rule_index_count)"
    cp "${FIXTURES_DIR}/sample_rules.conf" "${TEST_TMPDIR}/dry_test.conf"
    rule_import_file "${TEST_TMPDIR}/dry_test.conf" 1 2>/dev/null
    local after
    after="$(rule_index_count)"
    [ "${before}" -eq "${after}" ]
}

@test "rule_import_file: dry run catches invalid entries" {
    _init_all
    cp "${FIXTURES_DIR}/invalid_rules.conf" "${TEST_TMPDIR}/invalid_test.conf"
    rule_import_file "${TEST_TMPDIR}/invalid_test.conf" 1 2>/dev/null && _rc=0 || _rc=$?
    # Should fail because entries are invalid
    [ "${_rc}" -ne 0 ]
}

# ==============================================================================
# Import Tests — Rejection
# ==============================================================================

@test "rule_import_file: rejects nonexistent file" {
    _init_all
    rule_import_file "/nonexistent/path/rules.conf" 0 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

@test "rule_import_file: rejects oversized file" {
    _init_all
    local big_file="${TEST_TMPDIR}/big_rules.conf"
    # Create a file larger than 10MB
    dd if=/dev/zero of="${big_file}" bs=1M count=11 2>/dev/null
    rule_import_file "${big_file}" 0 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -ne 0 ]
}

# ==============================================================================
# Export/Import Round-Trip
# ==============================================================================

@test "round-trip: exported rules can be parsed by import dry-run" {
    _init_all
    local id
    id="$(security_generate_uuid)"
    declare -A rec=()
    rec[rule_id]="${id}" rec[backend]="iptables" rec[direction]="inbound"
    rec[action]="accept" rec[protocol]="tcp" rec[dst_port]="443"
    rec[duration_type]="permanent" rec[ttl]="0" rec[description]="round trip"
    rec[state]="active" rec[created_at]="now" rec[activated_at]="now"
    rec[expires_at]="" rec[src_ip]="" rec[dst_ip]="" rec[src_port]=""
    rec[interface]="" rec[chain]="" rec[table]="" rec[zone]="" rec[set_name]=""
    rule_index_add "rec"

    # Export
    local export_path="${TEST_TMPDIR}/roundtrip.conf"
    rule_export_file "${export_path}" 2>/dev/null

    # Clear index
    _RULE_INDEX_IDS=()
    unset _RULE_INDEX_DATA 2>/dev/null || true
    declare -gA _RULE_INDEX_DATA=()

    # Dry-run import to validate format
    rule_import_file "${export_path}" 1 2>/dev/null && _rc=0 || _rc=$?
    [ "${_rc}" -eq 0 ]
}
