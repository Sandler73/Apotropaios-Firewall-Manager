#!/usr/bin/env bash
# ==============================================================================
# File:         lib/firewall/firewalld.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     firewalld firewall backend implementation
# Description:  Implements the firewall backend interface for firewalld.
#               Provides zone-based rule management using firewall-cmd.
#               Supports rich rules, service management, and zone operations.
# Notes:        - Requires root privileges for all operations
#               - firewalld operates on zones (default: public)
#               - Supports both permanent and runtime configurations
#               - All input validated before command construction
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_FW_FIREWALLD_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_FW_FIREWALLD_LOADED=1

# ==============================================================================
# fw_firewalld_add_rule()
# Description:  Add a firewalld rule using rich rules or direct port/service.
# Parameters:   Associative array name (nameref) with rule parameters
# Returns:      0 on success, E_RULE_APPLY_FAIL on failure
# ==============================================================================
fw_firewalld_add_rule() {
    local -n _rule="${1:?fw_firewalld_add_rule requires rule array name}"

    local direction="${_rule[direction]:-inbound}"
    local protocol="${_rule[protocol]:-tcp}"
    local src_ip="${_rule[src_ip]:-}"
    local dst_ip="${_rule[dst_ip]:-}"
    local src_port="${_rule[src_port]:-}"
    local dst_port="${_rule[dst_port]:-}"
    local action="${_rule[action]:-accept}"
    local zone="${_rule[zone]:-public}"
    local permanent="${_rule[permanent]:-1}"
    local comment="${_rule[comment]:-}"

    # Validate zone
    validate_zone "${zone}" || return "${E_RULE_APPLY_FAIL}"

    # Validate protocol if provided
    if [[ -n "${protocol}" ]]; then
        protocol="$(validate_protocol "${protocol}")" || return "${E_RULE_APPLY_FAIL}"
    fi

    # Determine if we need a rich rule or simple port add
    local use_rich_rule=0
    [[ -n "${src_ip}" ]] && use_rich_rule=1
    [[ -n "${dst_ip}" ]] && use_rich_rule=1
    [[ "${direction}" == "outbound" ]] && use_rich_rule=1
    [[ "${action}" != "accept" ]] && use_rich_rule=1
    [[ "${action}" == *","* ]] && use_rich_rule=1
    [[ -n "${_rule[conn_state]:-}" ]] && use_rich_rule=1
    [[ -n "${_rule[log_prefix]:-}" ]] && use_rich_rule=1
    [[ -n "${_rule[limit]:-}" ]] && use_rich_rule=1

    local -a cmd_args=("--zone=${zone}")
    [[ "${permanent}" -eq 1 ]] && cmd_args+=("--permanent")

    if [[ "${use_rich_rule}" -eq 1 ]]; then
        # Build rich rule
        local rich_rule=""
        rich_rule="$(_firewalld_build_rich_rule \
            "${direction}" "${protocol}" "${src_ip}" "${dst_ip}" \
            "${src_port}" "${dst_port}" "${action}" "${comment}" \
            "${_rule[conn_state]:-}" "${_rule[log_prefix]:-}" \
            "${_rule[log_level]:-}" "${_rule[limit]:-}")" || return "${E_RULE_APPLY_FAIL}"

        cmd_args+=("--add-rich-rule=${rich_rule}")

        log_info "firewalld" "Adding rich rule to zone ${zone}: ${rich_rule}"
        if ! firewall-cmd "${cmd_args[@]}" 2>/dev/null; then
            log_error "firewalld" "Failed to add rich rule"
            return "${E_RULE_APPLY_FAIL}"
        fi
    else
        # Simple port addition
        if [[ -n "${dst_port}" ]]; then
            if validate_port "${dst_port}"; then
                cmd_args+=("--add-port=${dst_port}/${protocol}")
            elif validate_port_range "${dst_port}"; then
                local range_formatted="${dst_port//:/-}"
                cmd_args+=("--add-port=${range_formatted}/${protocol}")
            else
                log_error "firewalld" "Invalid port: ${dst_port}"
                return "${E_RULE_APPLY_FAIL}"
            fi

            log_info "firewalld" "Adding port ${dst_port}/${protocol} to zone ${zone}"
            if ! firewall-cmd "${cmd_args[@]}" 2>/dev/null; then
                log_error "firewalld" "Failed to add port"
                return "${E_RULE_APPLY_FAIL}"
            fi
        fi
    fi

    # Reload if permanent
    if [[ "${permanent}" -eq 1 ]]; then
        firewall-cmd --reload 2>/dev/null || true
    fi

    log_info "firewalld" "Rule added successfully"
    return "${E_SUCCESS}"
}

# ==============================================================================
# _firewalld_build_rich_rule() [INTERNAL]
# Description:  Construct a firewalld rich rule string from parameters.
#               Supports compound actions (log+accept/drop/reject), log
#               prefix/level, and rate limiting. Firewalld rich rules
#               natively support log combined with a terminal action.
# Returns:      Rich rule string on stdout
# ==============================================================================
_firewalld_build_rich_rule() {
    local direction="$1"
    local protocol="$2"
    local src_ip="$3"
    local dst_ip="$4"
    local src_port="$5"
    local dst_port="$6"
    local action="$7"
    local comment="${8:-}"
    local conn_state="${9:-}"
    local log_prefix="${10:-}"
    local log_level="${11:-}"
    local limit="${12:-}"

    local rule="rule"

    # Family (default: ipv4)
    rule="${rule} family=\"ipv4\""

    # Source
    if [[ -n "${src_ip}" ]]; then
        if validate_ip "${src_ip}" || validate_cidr "${src_ip}"; then
            rule="${rule} source address=\"${src_ip}\""
        else
            return 1
        fi
    fi

    # Destination
    if [[ -n "${dst_ip}" ]]; then
        if validate_ip "${dst_ip}" || validate_cidr "${dst_ip}"; then
            rule="${rule} destination address=\"${dst_ip}\""
        else
            return 1
        fi
    fi

    # Port
    if [[ -n "${dst_port}" ]]; then
        if validate_port "${dst_port}" || validate_port_range "${dst_port}"; then
            local port_formatted="${dst_port//:/-}"
            rule="${rule} port port=\"${port_formatted}\" protocol=\"${protocol:-tcp}\""
        else
            return 1
        fi
    elif [[ -n "${protocol}" ]] && [[ "${protocol}" != "all" ]]; then
        # Protocol-only rule (e.g., ICMP)
        if [[ "${protocol}" == "icmp" ]] || [[ "${protocol}" == "icmpv6" ]]; then
            rule="${rule} icmp-block-inversion"
        fi
    fi

    # Parse compound action (e.g., "log,drop")
    local action_lower
    action_lower="$(util_to_lower "${action}")"
    local -a action_parts=()
    local IFS=','
    read -ra action_parts <<< "${action_lower}"

    local has_log=0
    local terminal_action=""
    local apart
    for apart in "${action_parts[@]}"; do
        case "${apart}" in
            log)    has_log=1 ;;
            accept|drop|reject) terminal_action="${apart}" ;;
        esac
    done

    # Log clause (firewalld rich rules: log before terminal action)
    if [[ "${has_log}" -eq 1 ]]; then
        rule="${rule} log"
        [[ -n "${log_prefix}" ]] && rule="${rule} prefix=\"${log_prefix}\""
        [[ -n "${log_level}" ]] && rule="${rule} level=\"${log_level}\""
        # Log rate limit
        [[ -n "${limit}" ]] && rule="${rule} limit value=\"${limit}\""
    fi

    # Terminal action
    if [[ -n "${terminal_action}" ]]; then
        rule="${rule} ${terminal_action}"
    elif [[ "${has_log}" -eq 0 ]]; then
        # Default to accept if no action parsed
        rule="${rule} accept"
    fi

    printf '%s' "${rule}"
}

# ==============================================================================
# fw_firewalld_remove_rule()
# Description:  Remove a firewalld rule.
# ==============================================================================
fw_firewalld_remove_rule() {
    local -n _rule="${1:?fw_firewalld_remove_rule requires rule array name}"

    local zone="${_rule[zone]:-public}"
    local permanent="${_rule[permanent]:-1}"
    local dst_port="${_rule[dst_port]:-}"
    local protocol="${_rule[protocol]:-tcp}"
    local rich_rule="${_rule[rich_rule]:-}"

    local -a cmd_args=("--zone=${zone}")
    [[ "${permanent}" -eq 1 ]] && cmd_args+=("--permanent")

    if [[ -n "${rich_rule}" ]]; then
        cmd_args+=("--remove-rich-rule=${rich_rule}")
    elif [[ -n "${dst_port}" ]]; then
        protocol="$(validate_protocol "${protocol}")" || protocol="tcp"
        cmd_args+=("--remove-port=${dst_port}/${protocol}")
    else
        log_error "firewalld" "Cannot determine rule to remove (no port or rich rule specified)"
        return "${E_RULE_REMOVE_FAIL}"
    fi

    log_info "firewalld" "Removing rule from zone ${zone}"
    if ! firewall-cmd "${cmd_args[@]}" 2>/dev/null; then
        log_error "firewalld" "Failed to remove rule"
        return "${E_RULE_REMOVE_FAIL}"
    fi

    if [[ "${permanent}" -eq 1 ]]; then
        firewall-cmd --reload 2>/dev/null || true
    fi

    log_info "firewalld" "Rule removed successfully"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_firewalld_list_rules()
# ==============================================================================
fw_firewalld_list_rules() {
    local zone="${1:-}"

    if [[ -n "${zone}" ]]; then
        printf '%bZone: %s%b\n' "${COLOR_BOLD}" "${zone}" "${COLOR_RESET}"
        firewall-cmd --zone="${zone}" --list-all 2>/dev/null
    else
        firewall-cmd --list-all-zones 2>/dev/null
    fi
}

# ==============================================================================
# fw_firewalld_enable()
# ==============================================================================
fw_firewalld_enable() {
    if util_is_command_available systemctl; then
        systemctl start firewalld 2>/dev/null || true
        systemctl enable firewalld 2>/dev/null || true
    fi
    log_info "firewalld" "firewalld enabled"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_firewalld_disable()
# ==============================================================================
fw_firewalld_disable() {
    if util_is_command_available systemctl; then
        systemctl stop firewalld 2>/dev/null || true
    fi
    log_info "firewalld" "firewalld disabled"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_firewalld_status()
# ==============================================================================
fw_firewalld_status() {
    printf '%bFirewalld Status:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    firewall-cmd --state 2>/dev/null || printf 'firewalld is not running\n'
    printf '\n'
    firewall-cmd --list-all 2>/dev/null || true
}

# ==============================================================================
# fw_firewalld_block_all()
# ==============================================================================
fw_firewalld_block_all() {
    log_warning "firewalld" "Blocking ALL traffic via panic mode"
    firewall-cmd --panic-on 2>/dev/null || {
        # Fallback: set drop zone as default
        firewall-cmd --set-default-zone=drop 2>/dev/null || true
    }
    log_info "firewalld" "All traffic blocked"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_firewalld_allow_all()
# ==============================================================================
fw_firewalld_allow_all() {
    log_warning "firewalld" "Allowing ALL traffic (disabling panic mode)"
    firewall-cmd --panic-off 2>/dev/null || true
    firewall-cmd --set-default-zone=public 2>/dev/null || true
    log_info "firewalld" "All traffic allowed"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_firewalld_reset()
# ==============================================================================
fw_firewalld_reset() {
    log_warning "firewalld" "Resetting firewalld to defaults"
    # Remove all added ports and rich rules from public zone
    local zone="public"
    local ports
    ports="$(firewall-cmd --zone="${zone}" --list-ports 2>/dev/null)" || true
    local port
    for port in ${ports}; do
        firewall-cmd --zone="${zone}" --permanent --remove-port="${port}" 2>/dev/null || true
    done

    local rules
    rules="$(firewall-cmd --zone="${zone}" --list-rich-rules 2>/dev/null)" || true
    while IFS= read -r rule_line; do
        [[ -z "${rule_line}" ]] && continue
        firewall-cmd --zone="${zone}" --permanent --remove-rich-rule="${rule_line}" 2>/dev/null || true
    done <<< "${rules}"

    firewall-cmd --reload 2>/dev/null || true
    log_info "firewalld" "firewalld reset complete"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_firewalld_save()
# ==============================================================================
fw_firewalld_save() {
    local output="${1:-}"
    # firewalld auto-saves permanent rules; export if output specified
    if [[ -n "${output}" ]]; then
        firewall-cmd --list-all-zones > "${output}" 2>/dev/null || return "${E_GENERAL}"
        chmod "${SECURE_FILE_PERMS}" "${output}" 2>/dev/null || true
        log_info "firewalld" "Configuration exported to ${output}"
    fi
    firewall-cmd --runtime-to-permanent 2>/dev/null || true
    log_info "firewalld" "Runtime configuration saved to permanent"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_firewalld_reload()
# ==============================================================================
fw_firewalld_reload() {
    firewall-cmd --reload 2>/dev/null || {
        log_error "firewalld" "Failed to reload firewalld"
        return "${E_GENERAL}"
    }
    log_info "firewalld" "firewalld reloaded"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_firewalld_export_config()
# ==============================================================================
fw_firewalld_export_config() {
    firewall-cmd --list-all-zones 2>/dev/null
}
