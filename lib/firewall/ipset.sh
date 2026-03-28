#!/usr/bin/env bash
# ==============================================================================
# File:         lib/firewall/ipset.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     ipset firewall backend implementation
# Description:  Implements the firewall backend interface for ipset.
#               Manages IP sets for efficient bulk IP/network matching.
#               ipset works alongside iptables/nftables — it manages sets
#               of IPs/networks that can be referenced in firewall rules.
# Notes:        - Requires root privileges for all operations
#               - ipset operates on named sets containing IPs/networks/ports
#               - Sets are referenced by iptables/nftables rules for matching
#               - All input validated before command construction
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_FW_IPSET_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_FW_IPSET_LOADED=1

# ==============================================================================
# Supported ipset types
# ==============================================================================
readonly -a IPSET_TYPES=(
    "hash:ip"
    "hash:net"
    "hash:ip,port"
    "hash:net,port"
    "hash:ip,port,ip"
    "hash:net,port,net"
    "hash:ip,mark"
    "list:set"
)

# ==============================================================================
# fw_ipset_add_rule()
# Description:  Add an entry to an ipset, creating the set if needed.
#               Then optionally creates an iptables rule referencing the set.
# Parameters:   Associative array name (nameref) with:
#               set_name, set_type, entry (IP/network), timeout,
#               direction, action, chain, protocol, dst_port, comment
# Returns:      0 on success, E_RULE_APPLY_FAIL on failure
# ==============================================================================
fw_ipset_add_rule() {
    local -n _rule="${1:?fw_ipset_add_rule requires rule array name}"

    local set_name="${_rule[set_name]:-}"
    local set_type="${_rule[set_type]:-hash:net}"
    local entry="${_rule[entry]:-}"
    local timeout="${_rule[timeout]:-0}"
    local direction="${_rule[direction]:-inbound}"
    local action="${_rule[action]:-drop}"
    local chain="${_rule[chain]:-}"
    local protocol="${_rule[protocol]:-}"
    local dst_port="${_rule[dst_port]:-}"
    local comment="${_rule[comment]:-}"
    local create_fw_rule="${_rule[create_fw_rule]:-0}"

    # Validate set name
    if [[ -z "${set_name}" ]]; then
        log_error "ipset" "Set name is required"
        return "${E_RULE_APPLY_FAIL}"
    fi
    validate_ipset_name "${set_name}" || return "${E_RULE_APPLY_FAIL}"

    # Validate set type
    if ! util_array_contains "${set_type}" "${IPSET_TYPES[@]}"; then
        log_error "ipset" "Unsupported set type: ${set_type}"
        return "${E_RULE_APPLY_FAIL}"
    fi

    # Create the set if it doesn't exist
    if ! ipset list "${set_name}" &>/dev/null; then
        local -a create_args=("create" "${set_name}" "${set_type}")

        # Add timeout support if requested
        if [[ "${timeout}" -gt 0 ]]; then
            create_args+=("timeout" "${timeout}")
        fi

        # Add comment support
        create_args+=("comment")

        log_info "ipset" "Creating set: ${set_name} (type: ${set_type})"
        if ! ipset "${create_args[@]}" 2>/dev/null; then
            log_error "ipset" "Failed to create set: ${set_name}"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # Add entry to the set
    if [[ -n "${entry}" ]]; then
        # Validate entry based on set type
        case "${set_type}" in
            hash:ip)
                validate_ip "${entry}" || {
                    log_error "ipset" "Invalid IP for hash:ip set: ${entry}"
                    return "${E_RULE_APPLY_FAIL}"
                }
                ;;
            hash:net)
                if ! validate_ip "${entry}" && ! validate_cidr "${entry}"; then
                    log_error "ipset" "Invalid IP/CIDR for hash:net set: ${entry}"
                    return "${E_RULE_APPLY_FAIL}"
                fi
                ;;
            hash:ip,port|hash:net,port)
                # Entry format: IP,protocol:port — more complex validation
                if [[ ! "${entry}" =~ , ]]; then
                    log_error "ipset" "Invalid entry format for ${set_type}: ${entry}"
                    return "${E_RULE_APPLY_FAIL}"
                fi
                ;;
        esac

        local -a add_args=("add" "${set_name}" "${entry}")

        # Per-entry timeout
        if [[ "${timeout}" -gt 0 ]]; then
            add_args+=("timeout" "${timeout}")
        fi

        # Comment
        if [[ -n "${comment}" ]]; then
            comment="$(sanitize_input "${comment}")"
            add_args+=("comment" "${comment}")
        fi

        # Use -exist to avoid errors on duplicate entries
        add_args+=("-exist")

        log_info "ipset" "Adding entry to ${set_name}: ${entry}"
        if ! ipset "${add_args[@]}" 2>/dev/null; then
            log_error "ipset" "Failed to add entry to set ${set_name}"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # Optionally create an iptables rule referencing this set
    if [[ "${create_fw_rule}" -eq 1 ]]; then
        _ipset_create_iptables_rule "${set_name}" "${direction}" "${action}" \
            "${chain}" "${protocol}" "${dst_port}" || return "${E_RULE_APPLY_FAIL}"
    fi

    log_info "ipset" "Rule added successfully"
    return "${E_SUCCESS}"
}

# ==============================================================================
# _ipset_create_iptables_rule() [INTERNAL]
# Description:  Create an iptables rule that references an ipset.
# ==============================================================================
_ipset_create_iptables_rule() {
    local set_name="$1"
    local direction="${2:-inbound}"
    local action="${3:-drop}"
    local chain="${4:-}"
    local protocol="${5:-}"
    local dst_port="${6:-}"

    # Determine chain
    if [[ -z "${chain}" ]]; then
        case "${direction}" in
            inbound)  chain="INPUT" ;;
            outbound) chain="OUTPUT" ;;
            forward)  chain="FORWARD" ;;
        esac
    fi

    local -a cmd_args=("-A" "${chain}")

    # Match direction determines src/dst
    if [[ "${direction}" == "inbound" ]]; then
        cmd_args+=("-m" "set" "--match-set" "${set_name}" "src")
    else
        cmd_args+=("-m" "set" "--match-set" "${set_name}" "dst")
    fi

    # Protocol
    if [[ -n "${protocol}" ]] && [[ "${protocol}" != "all" ]]; then
        cmd_args+=("-p" "${protocol}")
    fi

    # Destination port
    if [[ -n "${dst_port}" ]]; then
        cmd_args+=("--dport" "${dst_port}")
    fi

    # Action
    local target
    case "$(util_to_upper "${action}")" in
        ACCEPT|ALLOW) target="ACCEPT" ;;
        DROP|DENY)    target="DROP" ;;
        REJECT)       target="REJECT" ;;
        LOG)          target="LOG" ;;
        *)            target="DROP" ;;
    esac
    cmd_args+=("-j" "${target}")

    log_info "ipset" "Creating iptables rule for set ${set_name}: iptables ${cmd_args[*]}"
    if ! iptables "${cmd_args[@]}" 2>/dev/null; then
        log_error "ipset" "Failed to create iptables rule for set ${set_name}"
        return 1
    fi
    return 0
}

# ==============================================================================
# fw_ipset_remove_rule()
# Description:  Remove an entry from an ipset, or destroy the set entirely.
# ==============================================================================
fw_ipset_remove_rule() {
    local -n _rule="${1:?fw_ipset_remove_rule requires rule array name}"

    local set_name="${_rule[set_name]:-}"
    local entry="${_rule[entry]:-}"
    local destroy_set="${_rule[destroy_set]:-0}"

    [[ -z "${set_name}" ]] && {
        log_error "ipset" "Set name required for removal"
        return "${E_RULE_REMOVE_FAIL}"
    }
    validate_ipset_name "${set_name}" || return "${E_RULE_REMOVE_FAIL}"

    if [[ "${destroy_set}" -eq 1 ]]; then
        # First, remove any iptables rules referencing this set
        _ipset_remove_iptables_refs "${set_name}"

        # Flush and destroy the set
        ipset flush "${set_name}" 2>/dev/null || true
        if ! ipset destroy "${set_name}" 2>/dev/null; then
            log_error "ipset" "Failed to destroy set: ${set_name}"
            return "${E_RULE_REMOVE_FAIL}"
        fi
        log_info "ipset" "Set destroyed: ${set_name}"
        return "${E_SUCCESS}"
    fi

    if [[ -n "${entry}" ]]; then
        log_info "ipset" "Removing entry from ${set_name}: ${entry}"
        if ! ipset del "${set_name}" "${entry}" 2>/dev/null; then
            log_error "ipset" "Failed to remove entry from set ${set_name}"
            return "${E_RULE_REMOVE_FAIL}"
        fi
        log_info "ipset" "Entry removed from ${set_name}"
        return "${E_SUCCESS}"
    fi

    log_error "ipset" "No entry or destroy flag specified"
    return "${E_RULE_REMOVE_FAIL}"
}

# ==============================================================================
# _ipset_remove_iptables_refs() [INTERNAL]
# Description:  Remove iptables rules that reference a specific ipset.
# ==============================================================================
_ipset_remove_iptables_refs() {
    local set_name="$1"

    # Find and remove iptables rules referencing this set
    local chain
    for chain in INPUT OUTPUT FORWARD; do
        local rule_nums
        rule_nums="$(iptables -L "${chain}" --line-numbers -n 2>/dev/null | \
            grep "match-set ${set_name}" | awk '{print $1}' | sort -rn)" || true
        local num
        for num in ${rule_nums}; do
            iptables -D "${chain}" "${num}" 2>/dev/null || true
        done
    done
}

# ==============================================================================
# fw_ipset_list_rules()
# ==============================================================================
fw_ipset_list_rules() {
    local set_name="${1:-}"

    if [[ -n "${set_name}" ]]; then
        ipset list "${set_name}" 2>/dev/null
    else
        ipset list 2>/dev/null
    fi
}

# ==============================================================================
# fw_ipset_enable()
# ==============================================================================
fw_ipset_enable() {
    # ipset is a kernel module tool — no service to enable
    log_info "ipset" "ipset is kernel-level; no service to enable"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ipset_disable()
# ==============================================================================
fw_ipset_disable() {
    log_info "ipset" "ipset is kernel-level; no service to disable"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ipset_status()
# ==============================================================================
fw_ipset_status() {
    printf '%bIPSet Status:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    local output
    output="$(ipset list -t 2>&1)" || true
    if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
        printf '  %bRoot privileges required to view ipset status%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return
    fi
    local set_count
    set_count="$(ipset list -n 2>/dev/null | wc -l)" || set_count=0
    printf '  Active sets: %d\n\n' "${set_count}"
    if [[ -n "${output}" ]]; then
        printf '%s\n' "${output}"
    else
        printf '  No ipsets configured\n'
    fi
}

# ==============================================================================
# fw_ipset_block_all()
# Description:  Create a blocklist set and iptables rules to drop all traffic.
# ==============================================================================
fw_ipset_block_all() {
    log_warning "ipset" "Blocking all traffic via ipset + iptables"

    # Create a set with the world
    ipset create apotropaios_block_all hash:net -exist 2>/dev/null || true
    ipset add apotropaios_block_all 0.0.0.0/0 -exist 2>/dev/null || true

    # Add iptables rules
    iptables -I INPUT -m set --match-set apotropaios_block_all src -j DROP 2>/dev/null || true
    iptables -I OUTPUT -m set --match-set apotropaios_block_all dst -j DROP 2>/dev/null || true

    # Preserve loopback
    iptables -I INPUT -i lo -j ACCEPT 2>/dev/null || true
    iptables -I OUTPUT -o lo -j ACCEPT 2>/dev/null || true

    log_info "ipset" "All traffic blocked via ipset"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ipset_allow_all()
# ==============================================================================
fw_ipset_allow_all() {
    log_warning "ipset" "Removing block-all ipset rules"
    _ipset_remove_iptables_refs "apotropaios_block_all"
    ipset flush apotropaios_block_all 2>/dev/null || true
    ipset destroy apotropaios_block_all 2>/dev/null || true
    log_info "ipset" "Block-all removed"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ipset_reset()
# ==============================================================================
fw_ipset_reset() {
    log_warning "ipset" "Flushing all ipsets"
    # Remove iptables references first
    local set_name
    while IFS= read -r set_name; do
        [[ -z "${set_name}" ]] && continue
        _ipset_remove_iptables_refs "${set_name}"
    done < <(ipset list -n 2>/dev/null)

    ipset flush 2>/dev/null || true
    ipset destroy 2>/dev/null || true
    log_info "ipset" "All ipsets destroyed"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ipset_save()
# ==============================================================================
fw_ipset_save() {
    local output="${1:-/etc/ipset.conf}"
    ipset save > "${output}" 2>/dev/null || {
        log_error "ipset" "Failed to save ipsets to ${output}"
        return "${E_GENERAL}"
    }
    chmod "${SECURE_FILE_PERMS}" "${output}" 2>/dev/null || true
    log_info "ipset" "Sets saved to ${output}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ipset_reload()
# ==============================================================================
fw_ipset_reload() {
    local input="${1:-/etc/ipset.conf}"
    [[ ! -f "${input}" ]] && { log_error "ipset" "Config not found: ${input}"; return "${E_GENERAL}"; }

    ipset restore < "${input}" 2>/dev/null || {
        log_error "ipset" "Failed to restore ipsets from ${input}"
        return "${E_GENERAL}"
    }
    log_info "ipset" "Sets restored from ${input}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ipset_export_config()
# ==============================================================================
fw_ipset_export_config() {
    ipset save 2>/dev/null
}
