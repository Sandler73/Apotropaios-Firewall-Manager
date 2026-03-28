#!/usr/bin/env bats
# ==============================================================================
# File:         tests/unit/os_detect.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Unit tests for OS detection module.
#               Tests detection result population, family mapping, package
#               manager mapping, and supported OS validation.
# ==============================================================================

load '../helpers/test_helper'

# ==============================================================================
# Detection Result Population
# ==============================================================================

@test "os_detect: sets OS_DETECTED_ID to non-empty string" {
    [ -n "${OS_DETECTED_ID}" ]
}

@test "os_detect: sets OS_DETECTED_NAME to non-empty string" {
    [ -n "${OS_DETECTED_NAME}" ]
}

@test "os_detect: sets OS_DETECTED_VERSION to non-empty string" {
    [ -n "${OS_DETECTED_VERSION}" ]
}

@test "os_detect: sets OS_DETECTED_FAMILY to known category" {
    [[ "${OS_DETECTED_FAMILY}" == "debian" ]] || \
    [[ "${OS_DETECTED_FAMILY}" == "rhel" ]] || \
    [[ "${OS_DETECTED_FAMILY}" == "arch" ]] || \
    [[ "${OS_DETECTED_FAMILY}" == "unknown" ]]
}

@test "os_detect: sets OS_DETECTED_PKG_MANAGER to known manager" {
    [[ "${OS_DETECTED_PKG_MANAGER}" == "apt" ]] || \
    [[ "${OS_DETECTED_PKG_MANAGER}" == "dnf" ]] || \
    [[ "${OS_DETECTED_PKG_MANAGER}" == "pacman" ]] || \
    [[ "${OS_DETECTED_PKG_MANAGER}" == "unknown" ]]
}

@test "os_detect: OS_DETECTED_SUPPORTED is 0 or 1" {
    [[ "${OS_DETECTED_SUPPORTED}" -eq 0 ]] || [[ "${OS_DETECTED_SUPPORTED}" -eq 1 ]]
}

# ==============================================================================
# OS Family to Package Manager Mapping
# ==============================================================================

@test "os_detect: debian family uses apt" {
    if [[ "${OS_DETECTED_FAMILY}" == "debian" ]]; then
        [ "${OS_DETECTED_PKG_MANAGER}" = "apt" ]
    else
        skip "Not a Debian-family system"
    fi
}

@test "os_detect: rhel family uses dnf" {
    if [[ "${OS_DETECTED_FAMILY}" == "rhel" ]]; then
        [ "${OS_DETECTED_PKG_MANAGER}" = "dnf" ]
    else
        skip "Not a RHEL-family system"
    fi
}

@test "os_detect: arch family uses pacman" {
    if [[ "${OS_DETECTED_FAMILY}" == "arch" ]]; then
        [ "${OS_DETECTED_PKG_MANAGER}" = "pacman" ]
    else
        skip "Not an Arch-family system"
    fi
}

# ==============================================================================
# os_get_info Output
# ==============================================================================

@test "os_get_info: produces output containing OS ID" {
    local output
    output="$(os_get_info 2>/dev/null)"
    [[ "${output}" == *"${OS_DETECTED_ID}"* ]]
}

@test "os_get_info: produces output containing package manager" {
    local output
    output="$(os_get_info 2>/dev/null)"
    [[ "${output}" == *"${OS_DETECTED_PKG_MANAGER}"* ]]
}

# ==============================================================================
# Supported OS List Consistency
# ==============================================================================

@test "SUPPORTED_OS_LIST: contains ubuntu" {
    util_array_contains "ubuntu" "${SUPPORTED_OS_LIST[@]}"
}

@test "SUPPORTED_OS_LIST: contains kali" {
    util_array_contains "kali" "${SUPPORTED_OS_LIST[@]}"
}

@test "SUPPORTED_OS_LIST: contains debian" {
    util_array_contains "debian" "${SUPPORTED_OS_LIST[@]}"
}

@test "SUPPORTED_OS_LIST: contains rocky" {
    util_array_contains "rocky" "${SUPPORTED_OS_LIST[@]}"
}

@test "SUPPORTED_OS_LIST: contains almalinux" {
    util_array_contains "almalinux" "${SUPPORTED_OS_LIST[@]}"
}

@test "SUPPORTED_OS_LIST: contains arch" {
    util_array_contains "arch" "${SUPPORTED_OS_LIST[@]}"
}

@test "SUPPORTED_OS_LIST: has 6 entries" {
    [ "${#SUPPORTED_OS_LIST[@]}" -eq 6 ]
}

@test "SUPPORTED_OS_NAMES: matches SUPPORTED_OS_LIST length" {
    [ "${#SUPPORTED_OS_NAMES[@]}" -eq "${#SUPPORTED_OS_LIST[@]}" ]
}

@test "SUPPORTED_OS_PKG_MANAGERS: matches SUPPORTED_OS_LIST length" {
    [ "${#SUPPORTED_OS_PKG_MANAGERS[@]}" -eq "${#SUPPORTED_OS_LIST[@]}" ]
}
