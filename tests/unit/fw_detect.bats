#!/usr/bin/env bats
# ==============================================================================
# File:         tests/unit/fw_detect.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Unit tests for firewall detection module.
#               Tests detection array population, helper functions, and
#               supported firewall list consistency.
# ==============================================================================

load '../helpers/test_helper'

# ==============================================================================
# Detection Array Population
# ==============================================================================

@test "fw_detect_all: completes without error" {
    run fw_detect_all
    [ "$status" -eq 0 ]
}

@test "fw_detect_all: populates FW_DETECTED_INSTALLED for all backends" {
    fw_detect_all 2>/dev/null
    local fw
    for fw in "${SUPPORTED_FW_LIST[@]}"; do
        local val="${FW_DETECTED_INSTALLED[${fw}]:-unset}"
        [[ "${val}" == "0" ]] || [[ "${val}" == "1" ]]
    done
}

@test "fw_detect_all: populates FW_DETECTED_RUNNING for all backends" {
    fw_detect_all 2>/dev/null
    local fw
    for fw in "${SUPPORTED_FW_LIST[@]}"; do
        local val="${FW_DETECTED_RUNNING[${fw}]:-unset}"
        [[ "${val}" == "0" ]] || [[ "${val}" == "1" ]]
    done
}

@test "fw_detect_all: sets FW_DETECTED_COUNT to non-negative integer" {
    fw_detect_all 2>/dev/null
    [[ "${FW_DETECTED_COUNT}" =~ ^[0-9]+$ ]]
}

@test "fw_detect_all: installed count matches FW_DETECTED_COUNT" {
    fw_detect_all 2>/dev/null
    local count=0
    local fw
    for fw in "${SUPPORTED_FW_LIST[@]}"; do
        [[ "${FW_DETECTED_INSTALLED[${fw}]:-0}" -eq 1 ]] && ((count++)) || true
    done
    [ "${count}" -eq "${FW_DETECTED_COUNT}" ]
}

# ==============================================================================
# Helper Functions
# ==============================================================================

@test "fw_get_installed: returns only installed firewalls" {
    fw_detect_all 2>/dev/null
    local installed
    installed="$(fw_get_installed)"
    local fw
    for fw in ${installed}; do
        [ "${FW_DETECTED_INSTALLED[${fw}]:-0}" -eq 1 ]
    done
}

@test "fw_is_installed: returns 0 for installed firewall" {
    fw_detect_all 2>/dev/null
    local installed
    installed="$(fw_get_installed)"
    if [ -n "${installed}" ]; then
        local first="${installed%% *}"
        fw_is_installed "${first}"
    else
        skip "No firewalls installed on this system"
    fi
}

@test "fw_is_installed: returns 1 for non-installed firewall" {
    fw_detect_all 2>/dev/null
    # Find a firewall that is NOT installed
    local fw found_missing=0
    for fw in "${SUPPORTED_FW_LIST[@]}"; do
        if [[ "${FW_DETECTED_INSTALLED[${fw}]:-0}" -eq 0 ]]; then
            ! fw_is_installed "${fw}"
            found_missing=1
            break
        fi
    done
    if [ "${found_missing}" -eq 0 ]; then
        skip "All firewalls are installed on this system"
    fi
}

@test "fw_detect_single: detects a known firewall by name" {
    # Test with a real firewall if available, else verify it handles missing
    local fw="${SUPPORTED_FW_LIST[0]}"
    fw_detect_single "${fw}" 2>/dev/null && _rc=0 || _rc=$?
    # Either success (found) or E_FW_NOT_FOUND (11) — both are valid
    [[ "${_rc}" -eq 0 ]] || [[ "${_rc}" -eq "${E_FW_NOT_FOUND}" ]]
}

@test "fw_detect_single: returns E_FW_NOT_FOUND for unknown name" {
    run fw_detect_single "totally_fake_firewall"
    [ "$status" -eq "${E_FW_NOT_FOUND}" ]
}

# ==============================================================================
# fw_get_info Display
# ==============================================================================

@test "fw_get_info: produces output" {
    fw_detect_all 2>/dev/null
    local output
    output="$(fw_get_info 2>/dev/null)"
    [ -n "${output}" ]
}

@test "fw_get_info: output contains 'Detected Firewalls'" {
    fw_detect_all 2>/dev/null
    local output
    output="$(fw_get_info 2>/dev/null)"
    [[ "${output}" == *"Detected Firewalls"* ]]
}

@test "fw_get_info: lists all 5 supported backends" {
    fw_detect_all 2>/dev/null
    local output
    output="$(fw_get_info 2>/dev/null)"
    local fw
    for fw in "${SUPPORTED_FW_LIST[@]}"; do
        [[ "${output}" == *"${fw}"* ]]
    done
}

# ==============================================================================
# Supported Firewall List Consistency
# ==============================================================================

@test "SUPPORTED_FW_LIST: has 5 entries" {
    [ "${#SUPPORTED_FW_LIST[@]}" -eq 5 ]
}

@test "SUPPORTED_FW_BINARIES: matches SUPPORTED_FW_LIST length" {
    [ "${#SUPPORTED_FW_BINARIES[@]}" -eq "${#SUPPORTED_FW_LIST[@]}" ]
}

@test "SUPPORTED_FW_SERVICES: matches SUPPORTED_FW_LIST length" {
    [ "${#SUPPORTED_FW_SERVICES[@]}" -eq "${#SUPPORTED_FW_LIST[@]}" ]
}

@test "SUPPORTED_FW_PACKAGES: matches SUPPORTED_FW_LIST length" {
    [ "${#SUPPORTED_FW_PACKAGES[@]}" -eq "${#SUPPORTED_FW_LIST[@]}" ]
}

@test "SUPPORTED_FW_LIST: contains all required backends" {
    util_array_contains "firewalld" "${SUPPORTED_FW_LIST[@]}"
    util_array_contains "ipset" "${SUPPORTED_FW_LIST[@]}"
    util_array_contains "iptables" "${SUPPORTED_FW_LIST[@]}"
    util_array_contains "nftables" "${SUPPORTED_FW_LIST[@]}"
    util_array_contains "ufw" "${SUPPORTED_FW_LIST[@]}"
}
