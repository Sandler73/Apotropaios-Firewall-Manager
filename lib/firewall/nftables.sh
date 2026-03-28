#!/usr/bin/env bash
# ==============================================================================
# File:         lib/firewall/nftables.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     nftables firewall backend implementation
# Description:  Implements the firewall backend interface for nftables.
#               Provides rule management using the nft command-line tool.
#               Supports table/chain/rule operations with full validation.
#               Uses nft's native syntax for rule construction.
# Notes:        - Requires root privileges for all operations
#               - nftables uses table families: ip, ip6, inet, arp, bridge
#               - All input validated before command construction
#               - Uses programmatic argument arrays, never string interpolation
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_FW_NFTABLES_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_FW_NFTABLES_LOADED=1

# ==============================================================================
# fw_nftables_add_rule()
# Description:  Add an nftables rule.
# Parameters:   Associative array name (nameref) with rule parameters:
#               direction, protocol, src_ip, dst_ip, src_port, dst_port,
#               action, chain, table, table_family, interface, comment
# Returns:      0 on success, E_RULE_APPLY_FAIL on failure
# ==============================================================================
fw_nftables_add_rule() {
    local -n _rule="${1:?fw_nftables_add_rule requires rule array name}"

    local direction="${_rule[direction]:-inbound}"
    local protocol="${_rule[protocol]:-}"
    local src_ip="${_rule[src_ip]:-}"
    local dst_ip="${_rule[dst_ip]:-}"
    local src_port="${_rule[src_port]:-}"
    local dst_port="${_rule[dst_port]:-}"
    local action="${_rule[action]:-accept}"
    local chain="${_rule[chain]:-}"
    local table="${_rule[table]:-apotropaios}"
    local table_family="${_rule[table_family]:-inet}"
    local interface="${_rule[interface]:-}"
    local comment="${_rule[comment]:-}"

    # Validate table and chain names
    validate_table "${table}" || return "${E_RULE_APPLY_FAIL}"
    validate_table_family "${table_family}" || {
        log_error "nftables" "Invalid table family: ${table_family} (must be inet, ip, ip6, arp, bridge, or netdev)"
        return "${E_RULE_APPLY_FAIL}"
    }

    # Determine chain from direction if not explicitly set
    if [[ -z "${chain}" ]]; then
        case "${direction}" in
            inbound)  chain="input" ;;
            outbound) chain="output" ;;
            forward)  chain="forward" ;;
        esac
    fi
    validate_chain "${chain}" || return "${E_RULE_APPLY_FAIL}"

    # Ensure the table and chain exist
    _nft_ensure_table "${table_family}" "${table}" || return "${E_RULE_APPLY_FAIL}"
    _nft_ensure_chain "${table_family}" "${table}" "${chain}" "${direction}" || return "${E_RULE_APPLY_FAIL}"

    # Build nft rule expression
    local rule_expr=""

    # Protocol match
    if [[ -n "${protocol}" ]]; then
        protocol="$(validate_protocol "${protocol}")" || return "${E_RULE_APPLY_FAIL}"
        if [[ "${protocol}" != "all" ]]; then
            rule_expr="${rule_expr} ${protocol}"
        fi
    fi

    # Source IP
    if [[ -n "${src_ip}" ]]; then
        if validate_ip "${src_ip}" || validate_cidr "${src_ip}"; then
            rule_expr="${rule_expr} ip saddr ${src_ip}"
        else
            log_error "nftables" "Invalid source IP: ${src_ip}"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # Destination IP
    if [[ -n "${dst_ip}" ]]; then
        if validate_ip "${dst_ip}" || validate_cidr "${dst_ip}"; then
            rule_expr="${rule_expr} ip daddr ${dst_ip}"
        else
            log_error "nftables" "Invalid destination IP: ${dst_ip}"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # Interface
    if [[ -n "${interface}" ]]; then
        validate_interface "${interface}" || return "${E_RULE_APPLY_FAIL}"
        if [[ "${direction}" == "inbound" ]]; then
            rule_expr="${rule_expr} iifname \"${interface}\""
        else
            rule_expr="${rule_expr} oifname \"${interface}\""
        fi
    fi

    # Source port
    if [[ -n "${src_port}" ]] && [[ -n "${protocol}" ]]; then
        if validate_port "${src_port}" || validate_port_range "${src_port}"; then
            local nft_port="${src_port//-/-}"  # nft uses - for ranges
            rule_expr="${rule_expr} ${protocol} sport ${nft_port}"
        else
            log_error "nftables" "Invalid source port: ${src_port}"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # Destination port
    if [[ -n "${dst_port}" ]] && [[ -n "${protocol}" ]]; then
        if validate_port "${dst_port}" || validate_port_range "${dst_port}"; then
            local nft_port="${dst_port//-/-}"
            rule_expr="${rule_expr} ${protocol} dport ${nft_port}"
        else
            log_error "nftables" "Invalid destination port: ${dst_port}"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # Connection tracking state
    local conn_state="${_rule[conn_state]:-}"
    if [[ -n "${conn_state}" ]]; then
        local ct_state
        ct_state="$(printf '%s' "${conn_state}" | tr '[:upper:]' '[:lower:]')"
        rule_expr="${rule_expr} ct state ${ct_state}"
    fi

    # Rate limiting
    local limit="${_rule[limit]:-}"
    if [[ -n "${limit}" ]]; then
        # Convert "5/minute" to nft "limit rate 5/minute"
        rule_expr="${rule_expr} limit rate ${limit}"
        local limit_burst="${_rule[limit_burst]:-}"
        [[ -n "${limit_burst}" ]] && rule_expr="${rule_expr} burst ${limit_burst} packets"
    fi

    # Comment
    if [[ -n "${comment}" ]]; then
        comment="$(sanitize_input "${comment}")"
        rule_expr="${rule_expr} comment \"${comment}\""
    fi

    # Action (verdict) — supports compound actions in nftables
    # nftables can combine non-terminal and terminal in one rule: "log prefix ... drop"
    local log_prefix="${_rule[log_prefix]:-}"
    local log_level="${_rule[log_level]:-}"
    local action_lower
    action_lower="$(util_to_lower "${action}")"

    # Parse compound action
    local -a action_parts=()
    local IFS=','
    read -ra action_parts <<< "${action_lower}"

    local verdict_expr=""
    local apart
    for apart in "${action_parts[@]}"; do
        case "${apart}" in
            accept)     verdict_expr="${verdict_expr} accept" ;;
            drop)       verdict_expr="${verdict_expr} drop" ;;
            reject)     verdict_expr="${verdict_expr} reject" ;;
            log)
                verdict_expr="${verdict_expr} log"
                [[ -n "${log_prefix}" ]] && verdict_expr="${verdict_expr} prefix \"${log_prefix}\""
                [[ -n "${log_level}" ]] && verdict_expr="${verdict_expr} level ${log_level}"
                ;;
            masquerade) verdict_expr="${verdict_expr} masquerade" ;;
            return)     verdict_expr="${verdict_expr} return" ;;
            *)
                log_error "nftables" "Unsupported action: ${apart}"
                return "${E_RULE_APPLY_FAIL}"
                ;;
        esac
    done
    rule_expr="${rule_expr}${verdict_expr}"

    # Trim leading whitespace
    rule_expr="$(util_trim "${rule_expr}")"

    # Execute
    local nft_cmd="add rule ${table_family} ${table} ${chain} ${rule_expr}"
    # Execute via nft command arguments (NOT via nft -f file — C4 security fix)
    # Using direct nft command string is safe because all components are individually
    # validated. The nft -f fallback was removed because file mode interprets
    # semicolons and newlines as command separators, creating an injection vector.
    log_info "nftables" "Adding rule: nft ${nft_cmd}"

    # shellcheck disable=SC2086 — intentional word splitting: nft requires
    # command string split into arguments; all components individually validated
    if ! nft ${nft_cmd} 2>/dev/null; then
        log_error "nftables" "Failed to add rule"
        return "${E_RULE_APPLY_FAIL}"
    fi

    log_info "nftables" "Rule added successfully"
    return "${E_SUCCESS}"
}

# ==============================================================================
# _nft_ensure_table() [INTERNAL]
# Description:  Ensure an nftables table exists, create if not.
# Parameters:   $1 - Table family (inet, ip, ip6)
#               $2 - Table name
# ==============================================================================
_nft_ensure_table() {
    local family="$1"
    local table="$2"

    if ! nft list table "${family}" "${table}" &>/dev/null; then
        log_debug "nftables" "Creating table: ${family} ${table}"
        nft "add table ${family} ${table}" 2>/dev/null || {
            log_error "nftables" "Failed to create table: ${family} ${table}"
            return 1
        }
    fi
    return 0
}

# ==============================================================================
# _nft_ensure_chain() [INTERNAL]
# Description:  Ensure an nftables chain exists, create if not.
# Parameters:   $1 - Table family
#               $2 - Table name
#               $3 - Chain name
#               $4 - Direction (for hook and priority)
# ==============================================================================
_nft_ensure_chain() {
    local family="$1"
    local table="$2"
    local chain="$3"
    local direction="${4:-inbound}"

    if ! nft list chain "${family}" "${table}" "${chain}" &>/dev/null; then
        local hook priority
        case "${direction}" in
            inbound)  hook="input";   priority="0" ;;
            outbound) hook="output";  priority="0" ;;
            forward)  hook="forward"; priority="0" ;;
            *)        hook="input";   priority="0" ;;
        esac

        log_debug "nftables" "Creating chain: ${family} ${table} ${chain} (hook=${hook})"
        nft "add chain ${family} ${table} ${chain} { type filter hook ${hook} priority ${priority}; policy accept; }" 2>/dev/null || {
            log_error "nftables" "Failed to create chain"
            return 1
        }
    fi
    return 0
}

# ==============================================================================
# fw_nftables_remove_rule()
# Description:  Remove an nftables rule by handle number or matching.
# Parameters:   Associative array name with rule parameters
#               If _rule[handle] is set, removes by handle number
# ==============================================================================
fw_nftables_remove_rule() {
    local -n _rule="${1:?fw_nftables_remove_rule requires rule array name}"

    local table="${_rule[table]:-apotropaios}"
    local table_family="${_rule[table_family]:-inet}"
    local chain="${_rule[chain]:-}"
    local direction="${_rule[direction]:-inbound}"
    local handle="${_rule[handle]:-}"
    local comment="${_rule[comment]:-}"

    if [[ -z "${chain}" ]]; then
        case "${direction}" in
            inbound)  chain="input" ;;
            outbound) chain="output" ;;
            forward)  chain="forward" ;;
        esac
    fi

    # If handle is provided, delete directly
    if [[ -n "${handle}" ]]; then
        validate_numeric "${handle}" || return "${E_RULE_REMOVE_FAIL}"
        log_info "nftables" "Removing rule by handle: ${handle} from ${table_family} ${table} ${chain}"
        if ! nft "delete rule ${table_family} ${table} ${chain} handle ${handle}" 2>/dev/null; then
            log_error "nftables" "Failed to remove rule handle ${handle}"
            return "${E_RULE_REMOVE_FAIL}"
        fi
        return "${E_SUCCESS}"
    fi

    # Otherwise, find by comment and remove
    if [[ -n "${comment}" ]]; then
        comment="$(sanitize_input "${comment}")"
        local rule_handle
        rule_handle="$(nft -a list chain "${table_family}" "${table}" "${chain}" 2>/dev/null | \
            grep "comment \"${comment}\"" | grep -oE 'handle [0-9]+' | awk '{print $2}' | head -1)" || true

        if [[ -n "${rule_handle}" ]]; then
            nft "delete rule ${table_family} ${table} ${chain} handle ${rule_handle}" 2>/dev/null || {
                log_error "nftables" "Failed to remove rule by comment match"
                return "${E_RULE_REMOVE_FAIL}"
            }
            log_info "nftables" "Rule removed (handle ${rule_handle})"
            return "${E_SUCCESS}"
        fi
    fi

    log_warning "nftables" "Could not identify rule to remove"
    return "${E_RULE_NOT_FOUND}"
}

# ==============================================================================
# fw_nftables_list_rules()
# Description:  List current nftables ruleset.
# Parameters:   $1 - Table family (optional)
#               $2 - Table name (optional)
# ==============================================================================
fw_nftables_list_rules() {
    local family="${1:-}"
    local table="${2:-}"
    local output

    if [[ -n "${family}" ]] && [[ -n "${table}" ]]; then
        output="$(nft list table "${family}" "${table}" 2>&1)" || true
    elif [[ -n "${family}" ]]; then
        output="$(nft list tables "${family}" 2>&1)" || true
    else
        output="$(nft list ruleset 2>&1)" || true
    fi

    if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
        printf '  %bRoot privileges required to list nftables rules%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return "${E_PERMISSION}"
    fi
    printf '%s\n' "${output}"
}

# ==============================================================================
# fw_nftables_enable()
# ==============================================================================
fw_nftables_enable() {
    if util_is_command_available systemctl; then
        systemctl start nftables 2>/dev/null || true
        systemctl enable nftables 2>/dev/null || true
    fi
    log_info "nftables" "nftables enabled"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_nftables_disable()
# ==============================================================================
fw_nftables_disable() {
    if util_is_command_available systemctl; then
        systemctl stop nftables 2>/dev/null || true
    fi
    log_info "nftables" "nftables disabled"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_nftables_status()
# ==============================================================================
fw_nftables_status() {
    printf '%bNftables Status:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    local output
    output="$(nft list ruleset 2>&1)" || true
    if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
        printf '  %bRoot privileges required to view nftables status%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        printf '  Run with: sudo apotropaios.sh\n'
    elif [[ -z "${output}" ]]; then
        printf '  No nftables rules currently configured\n'
    else
        printf '%s\n' "${output}"
    fi
}

# ==============================================================================
# fw_nftables_block_all()
# ==============================================================================
fw_nftables_block_all() {
    log_warning "nftables" "Blocking ALL traffic"

    _nft_ensure_table "inet" "apotropaios" || return "${E_RULE_APPLY_FAIL}"

    # Flush existing chains
    nft "flush table inet apotropaios" 2>/dev/null || true

    # Create chains with drop policy
    nft "add chain inet apotropaios input { type filter hook input priority 0; policy drop; }" 2>/dev/null || true
    nft "add chain inet apotropaios output { type filter hook output priority 0; policy drop; }" 2>/dev/null || true
    nft "add chain inet apotropaios forward { type filter hook forward priority 0; policy drop; }" 2>/dev/null || true

    # Allow loopback
    nft "add rule inet apotropaios input iifname lo accept" 2>/dev/null || true
    nft "add rule inet apotropaios output oifname lo accept" 2>/dev/null || true

    log_info "nftables" "All traffic blocked (loopback preserved)"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_nftables_allow_all()
# ==============================================================================
fw_nftables_allow_all() {
    log_warning "nftables" "Allowing ALL traffic"

    if nft list table inet apotropaios &>/dev/null; then
        nft "flush table inet apotropaios" 2>/dev/null || true
        nft "delete table inet apotropaios" 2>/dev/null || true
    fi

    log_info "nftables" "All traffic allowed (apotropaios table removed)"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_nftables_reset()
# ==============================================================================
fw_nftables_reset() {
    log_warning "nftables" "Resetting nftables (flushing all rules)"
    nft flush ruleset 2>/dev/null || {
        log_error "nftables" "Failed to flush ruleset"
        return "${E_GENERAL}"
    }
    log_info "nftables" "nftables reset complete"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_nftables_save()
# ==============================================================================
fw_nftables_save() {
    local output="${1:-/etc/nftables.conf}"
    nft list ruleset > "${output}" 2>/dev/null || {
        log_error "nftables" "Failed to save ruleset to ${output}"
        return "${E_GENERAL}"
    }
    chmod "${SECURE_FILE_PERMS}" "${output}" 2>/dev/null || true
    log_info "nftables" "Ruleset saved to ${output}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_nftables_reload()
# ==============================================================================
fw_nftables_reload() {
    local input="${1:-/etc/nftables.conf}"
    [[ ! -f "${input}" ]] && { log_error "nftables" "Config not found: ${input}"; return "${E_GENERAL}"; }

    nft -f "${input}" 2>/dev/null || {
        log_error "nftables" "Failed to reload from ${input}"
        return "${E_GENERAL}"
    }
    log_info "nftables" "Ruleset reloaded from ${input}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_nftables_export_config()
# ==============================================================================
fw_nftables_export_config() {
    nft list ruleset 2>/dev/null
}
