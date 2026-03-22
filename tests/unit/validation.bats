#!/usr/bin/env bats
# ==============================================================================
# File:         tests/unit/validation.bats
# Project:      Apotropaios - Firewall Manager
# Description:  Unit tests for input validation functions.
#               Tests the contract directly (CI/CD Lesson #2).
# ==============================================================================

load '../helpers/test_helper'

# ==============================================================================
# Port Validation
# ==============================================================================

@test "validate_port: accepts valid port 80" {
    run validate_port "80"
    [ "$status" -eq 0 ]
}

@test "validate_port: accepts valid port 1" {
    run validate_port "1"
    [ "$status" -eq 0 ]
}

@test "validate_port: accepts valid port 65535" {
    run validate_port "65535"
    [ "$status" -eq 0 ]
}

@test "validate_port: rejects port 0" {
    run validate_port "0"
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects port 65536" {
    run validate_port "65536"
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects non-numeric" {
    run validate_port "abc"
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects empty input" {
    run validate_port ""
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects negative number" {
    run validate_port "-1"
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects port with spaces" {
    run validate_port " 80 "
    [ "$status" -eq 1 ]
}

# ==============================================================================
# Port Range Validation
# ==============================================================================

@test "validate_port_range: accepts 8080-8090" {
    run validate_port_range "8080-8090"
    [ "$status" -eq 0 ]
}

@test "validate_port_range: accepts 8080:8090" {
    run validate_port_range "8080:8090"
    [ "$status" -eq 0 ]
}

@test "validate_port_range: rejects reversed range" {
    run validate_port_range "9000-8000"
    [ "$status" -eq 1 ]
}

@test "validate_port_range: rejects single port" {
    run validate_port_range "8080"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# IPv4 Validation
# ==============================================================================

@test "validate_ipv4: accepts 192.168.1.1" {
    run validate_ipv4 "192.168.1.1"
    [ "$status" -eq 0 ]
}

@test "validate_ipv4: accepts 0.0.0.0" {
    run validate_ipv4 "0.0.0.0"
    [ "$status" -eq 0 ]
}

@test "validate_ipv4: accepts 255.255.255.255" {
    run validate_ipv4 "255.255.255.255"
    [ "$status" -eq 0 ]
}

@test "validate_ipv4: rejects 256.1.1.1" {
    run validate_ipv4 "256.1.1.1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv4: rejects leading zeros in octet" {
    run validate_ipv4 "192.168.01.1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv4: rejects three octets" {
    run validate_ipv4 "192.168.1"
    [ "$status" -eq 1 ]
}

@test "validate_ipv4: rejects empty" {
    run validate_ipv4 ""
    [ "$status" -eq 1 ]
}

# ==============================================================================
# CIDR Validation
# ==============================================================================

@test "validate_cidr: accepts 192.168.1.0/24" {
    run validate_cidr "192.168.1.0/24"
    [ "$status" -eq 0 ]
}

@test "validate_cidr: accepts 10.0.0.0/8" {
    run validate_cidr "10.0.0.0/8"
    [ "$status" -eq 0 ]
}

@test "validate_cidr: rejects /33 prefix for IPv4" {
    run validate_cidr "10.0.0.0/33"
    [ "$status" -eq 1 ]
}

@test "validate_cidr: rejects missing prefix" {
    run validate_cidr "10.0.0.0"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# Protocol Validation
# ==============================================================================

@test "validate_protocol: accepts tcp" {
    run validate_protocol "tcp"
    [ "$status" -eq 0 ]
    [ "$output" = "tcp" ]
}

@test "validate_protocol: accepts UDP (normalizes to lowercase)" {
    run validate_protocol "UDP"
    [ "$status" -eq 0 ]
    [ "$output" = "udp" ]
}

@test "validate_protocol: accepts icmp" {
    run validate_protocol "icmp"
    [ "$status" -eq 0 ]
}

@test "validate_protocol: accepts all" {
    run validate_protocol "all"
    [ "$status" -eq 0 ]
}

@test "validate_protocol: rejects invalid protocol" {
    run validate_protocol "ftp"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# Hostname Validation
# ==============================================================================

@test "validate_hostname: accepts example.com" {
    run validate_hostname "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: accepts single-label host" {
    run validate_hostname "localhost"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: rejects shell metacharacters" {
    run validate_hostname "host;rm -rf /"
    [ "$status" -eq 1 ]
}

@test "validate_hostname: rejects pipe characters" {
    run validate_hostname "host|whoami"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# File Path Validation
# ==============================================================================

@test "validate_file_path: accepts normal path" {
    run validate_file_path "/etc/firewall/rules.conf"
    [ "$status" -eq 0 ]
}

@test "validate_file_path: rejects path traversal" {
    run validate_file_path "/etc/../../../tmp/evil"
    [ "$status" -eq 1 ]
}

@test "validate_file_path: rejects shell metacharacters" {
    run validate_file_path "/tmp/file;rm -rf /"
    [ "$status" -eq 1 ]
}

@test "validate_file_path: rejects backticks" {
    run validate_file_path '/tmp/$(whoami)'
    [ "$status" -eq 1 ]
}

# ==============================================================================
# Rule Action/Direction Validation
# ==============================================================================

@test "validate_rule_action: accepts accept" {
    run validate_rule_action "accept"
    [ "$status" -eq 0 ]
}

@test "validate_rule_action: accepts drop" {
    run validate_rule_action "drop"
    [ "$status" -eq 0 ]
}

@test "validate_rule_action: rejects invalid action" {
    run validate_rule_action "delete"
    [ "$status" -eq 1 ]
}

@test "validate_rule_direction: accepts inbound" {
    run validate_rule_direction "inbound"
    [ "$status" -eq 0 ]
}

@test "validate_rule_direction: accepts outbound" {
    run validate_rule_direction "outbound"
    [ "$status" -eq 0 ]
}

@test "validate_rule_direction: rejects invalid direction" {
    run validate_rule_direction "sideways"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# Sanitize Input
# ==============================================================================

@test "sanitize_input: removes semicolons" {
    run sanitize_input "hello;world"
    [ "$output" = "helloworld" ]
}

@test "sanitize_input: removes backticks" {
    run sanitize_input 'hello`whoami`world'
    [ "$output" = "hellowhoamiworld" ]
}

@test "sanitize_input: trims whitespace" {
    run sanitize_input "  hello world  "
    [ "$output" = "hello world" ]
}

@test "sanitize_input: enforces max length" {
    local long_input
    long_input="$(printf 'A%.0s' $(seq 1 5000))"
    run sanitize_input "${long_input}"
    [ "${#output}" -le 4096 ]
}
