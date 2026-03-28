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

@test "validate_rule_action: accepts log" {
    run validate_rule_action "log"
    [ "$status" -eq 0 ]
}

@test "validate_rule_action: accepts compound log,drop" {
    run validate_rule_action "log,drop"
    [ "$status" -eq 0 ]
}

@test "validate_rule_action: accepts compound log,accept" {
    run validate_rule_action "log,accept"
    [ "$status" -eq 0 ]
}

@test "validate_rule_action: accepts compound log,reject" {
    run validate_rule_action "log,reject"
    [ "$status" -eq 0 ]
}

@test "validate_rule_action: rejects two terminal actions" {
    run validate_rule_action "drop,accept"
    [ "$status" -eq 1 ]
}

@test "validate_rule_action: rejects invalid action" {
    run validate_rule_action "delete"
    [ "$status" -eq 1 ]
}

@test "validate_rule_action: rejects invalid compound component" {
    run validate_rule_action "log,nuke"
    [ "$status" -eq 1 ]
}

@test "validate_rule_action: accepts return" {
    run validate_rule_action "return"
    [ "$status" -eq 0 ]
}

@test "validate_rule_action: accepts masquerade" {
    run validate_rule_action "masquerade"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# Connection State Validation
# ==============================================================================

@test "validate_conn_state: accepts new" {
    run validate_conn_state "new"
    [ "$status" -eq 0 ]
}

@test "validate_conn_state: accepts established" {
    run validate_conn_state "established"
    [ "$status" -eq 0 ]
}

@test "validate_conn_state: accepts compound new,established,related" {
    run validate_conn_state "new,established,related"
    [ "$status" -eq 0 ]
}

@test "validate_conn_state: accepts invalid state name" {
    run validate_conn_state "bogus"
    [ "$status" -eq 1 ]
}

@test "validate_conn_state: rejects empty" {
    run validate_conn_state ""
    [ "$status" -eq 1 ]
}

@test "validate_conn_state: accepts UPPERCASE (normalizes)" {
    run validate_conn_state "ESTABLISHED,RELATED"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# Log Prefix Validation
# ==============================================================================

@test "validate_log_prefix: accepts valid prefix" {
    run validate_log_prefix "FIREWALL: "
    [ "$status" -eq 0 ]
}

@test "validate_log_prefix: rejects over 29 chars" {
    run validate_log_prefix "this_prefix_is_way_too_long_for_netfilter_to_accept"
    [ "$status" -eq 1 ]
}

@test "validate_log_prefix: rejects empty" {
    run validate_log_prefix ""
    [ "$status" -eq 1 ]
}

# ==============================================================================
# Rate Limit Validation
# ==============================================================================

@test "validate_rate_limit: accepts 5/minute" {
    run validate_rate_limit "5/minute"
    [ "$status" -eq 0 ]
}

@test "validate_rate_limit: accepts 10/second" {
    run validate_rate_limit "10/second"
    [ "$status" -eq 0 ]
}

@test "validate_rate_limit: accepts 100/hour" {
    run validate_rate_limit "100/hour"
    [ "$status" -eq 0 ]
}

@test "validate_rate_limit: rejects invalid format" {
    run validate_rate_limit "5perminute"
    [ "$status" -eq 1 ]
}

@test "validate_rate_limit: rejects empty" {
    run validate_rate_limit ""
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

# ==============================================================================
# Table Family Validation (nftables)
# ==============================================================================

@test "validate_table_family: accepts inet" {
    run validate_table_family "inet"
    [ "$status" -eq 0 ]
}

@test "validate_table_family: accepts ip" {
    run validate_table_family "ip"
    [ "$status" -eq 0 ]
}

@test "validate_table_family: accepts ip6" {
    run validate_table_family "ip6"
    [ "$status" -eq 0 ]
}

@test "validate_table_family: accepts bridge" {
    run validate_table_family "bridge"
    [ "$status" -eq 0 ]
}

@test "validate_table_family: accepts netdev" {
    run validate_table_family "netdev"
    [ "$status" -eq 0 ]
}

@test "validate_table_family: accepts arp" {
    run validate_table_family "arp"
    [ "$status" -eq 0 ]
}

@test "validate_table_family: rejects invalid family" {
    run validate_table_family "ipv4"
    [ "$status" -eq 1 ]
}

@test "validate_table_family: rejects empty" {
    run validate_table_family ""
    [ "$status" -eq 1 ]
}

@test "validate_table_family: normalizes uppercase" {
    run validate_table_family "INET"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# Sanitize Input — Whitelist Preservation
# Verify valid characters survive the whitelist tr -cd
# ==============================================================================

@test "sanitize_input: preserves compound actions" {
    run sanitize_input "log,drop"
    [ "$output" = "log,drop" ]
}

@test "sanitize_input: preserves IP addresses" {
    run sanitize_input "192.168.1.0/24"
    [ "$output" = "192.168.1.0/24" ]
}

@test "sanitize_input: preserves rate limits" {
    run sanitize_input "5/minute"
    [ "$output" = "5/minute" ]
}

@test "sanitize_input: preserves connection states" {
    run sanitize_input "new,established,related"
    [ "$output" = "new,established,related" ]
}

@test "sanitize_input: preserves file paths" {
    run sanitize_input "/opt/apotropaios/data/rules/export.conf"
    [ "$output" = "/opt/apotropaios/data/rules/export.conf" ]
}

@test "sanitize_input: preserves descriptions with spaces" {
    run sanitize_input "Block SSH from external network"
    [ "$output" = "Block SSH from external network" ]
}

@test "sanitize_input: preserves hyphenated names" {
    run sanitize_input "my-rule-name_v2"
    [ "$output" = "my-rule-name_v2" ]
}

@test "sanitize_input: preserves port ranges" {
    run sanitize_input "8080-8090"
    [ "$output" = "8080-8090" ]
}

@test "sanitize_input: preserves email-style identifiers" {
    run sanitize_input "user@host.example.com"
    [ "$output" = "user@host.example.com" ]
}

@test "sanitize_input: strips all shell metacharacters" {
    run sanitize_input 'safe;|&`$(){}<>!#text'
    [ "$output" = "safetext" ]
}
