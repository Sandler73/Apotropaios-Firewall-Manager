#!/usr/bin/env bash
# ==============================================================================
# File:         lib/firewall/iptables.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     iptables firewall backend implementation
# Description:  Implements the firewall backend interface for iptables.
#               Provides rule management, chain operations, and configuration
#               persistence using iptables-save/iptables-restore.
# Notes:        - Requires root privileges for all operations
#               - All user input is validated before constructing commands
#               - Commands are built programmatically, never via string interpolation
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_FW_IPTABLES_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_FW_IPTABLES_LOADED=1

# ==============================================================================
# fw_iptables_add_rule()
# Description:  Add iptables rule(s). Supports compound actions (e.g., log,drop)
#               by creating separate rules for non-terminal and terminal actions.
#               Supports connection tracking states, log prefix/level, and rate limits.
# Parameters:   Associative array name (nameref) with rule parameters:
#               direction, protocol, src_ip, dst_ip, src_port, dst_port,
#               action, chain, table, interface, comment, conn_state,
#               log_prefix, log_level, limit, limit_burst
# Returns:      0 on success, E_RULE_APPLY_FAIL on failure
# ==============================================================================
fw_iptables_add_rule() {
    local -n _rule="${1:?fw_iptables_add_rule requires rule array name}"

    local direction="${_rule[direction]:-inbound}"
    local protocol="${_rule[protocol]:-}"
    local src_ip="${_rule[src_ip]:-}"
    local dst_ip="${_rule[dst_ip]:-}"
    local src_port="${_rule[src_port]:-}"
    local dst_port="${_rule[dst_port]:-}"
    local action="${_rule[action]:-accept}"
    local chain="${_rule[chain]:-}"
    local table="${_rule[table]:-filter}"
    local interface="${_rule[interface]:-}"
    local comment="${_rule[comment]:-}"
    local conn_state="${_rule[conn_state]:-}"
    local log_prefix="${_rule[log_prefix]:-}"
    local log_level="${_rule[log_level]:-}"
    local limit="${_rule[limit]:-}"
    local limit_burst="${_rule[limit_burst]:-}"

    # Build base match arguments (shared across compound action rules)
    local -a base_args=()

    # Table
    if [[ -n "${table}" ]]; then
        validate_table "${table}" || return "${E_RULE_APPLY_FAIL}"
        base_args+=("-t" "${table}")
    fi

    # Determine chain from direction if not explicitly set
    if [[ -z "${chain}" ]]; then
        case "${direction}" in
            inbound)  chain="INPUT" ;;
            outbound) chain="OUTPUT" ;;
            forward)  chain="FORWARD" ;;
        esac
    fi
    validate_chain "${chain}" || return "${E_RULE_APPLY_FAIL}"

    # Protocol
    if [[ -n "${protocol}" ]]; then
        protocol="$(validate_protocol "${protocol}")" || return "${E_RULE_APPLY_FAIL}"
        [[ "${protocol}" != "all" ]] && base_args+=("-p" "${protocol}")
    fi

    # Source IP
    if [[ -n "${src_ip}" ]]; then
        if validate_ip "${src_ip}" || validate_cidr "${src_ip}"; then
            base_args+=("-s" "${src_ip}")
        else
            log_error "iptables" "Invalid source IP: ${src_ip}"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # Destination IP
    if [[ -n "${dst_ip}" ]]; then
        if validate_ip "${dst_ip}" || validate_cidr "${dst_ip}"; then
            base_args+=("-d" "${dst_ip}")
        else
            log_error "iptables" "Invalid destination IP: ${dst_ip}"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # Interface (inbound = -i, outbound = -o)
    if [[ -n "${interface}" ]]; then
        validate_interface "${interface}" || return "${E_RULE_APPLY_FAIL}"
        if [[ "${direction}" == "inbound" ]] || [[ "${chain}" == "INPUT" ]]; then
            base_args+=("-i" "${interface}")
        else
            base_args+=("-o" "${interface}")
        fi
    fi

    # Source port (requires protocol)
    if [[ -n "${src_port}" ]]; then
        if validate_port "${src_port}" || validate_port_range "${src_port}"; then
            base_args+=("--sport" "${src_port}")
        else
            log_error "iptables" "Invalid source port: ${src_port}"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # Destination port (requires protocol)
    if [[ -n "${dst_port}" ]]; then
        if validate_port "${dst_port}" || validate_port_range "${dst_port}"; then
            base_args+=("--dport" "${dst_port}")
        else
            log_error "iptables" "Invalid destination port: ${dst_port}"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # Connection tracking state (conntrack module)
    if [[ -n "${conn_state}" ]]; then
        local ct_state
        ct_state="$(printf '%s' "${conn_state}" | tr '[:lower:]' '[:upper:]')"
        base_args+=("-m" "conntrack" "--ctstate" "${ct_state}")
    fi

    # Rate limiting (limit module)
    if [[ -n "${limit}" ]]; then
        base_args+=("-m" "limit" "--limit" "${limit}")
        [[ -n "${limit_burst}" ]] && base_args+=("--limit-burst" "${limit_burst}")
    fi

    # Comment (for rule tracking)
    if [[ -n "${comment}" ]]; then
        comment="$(sanitize_input "${comment}")"
        base_args+=("-m" "comment" "--comment" "${comment}")
    fi

    # Parse compound action (e.g., "log,drop" → LOG rule then DROP rule)
    local -a action_parts=()
    local IFS=','
    read -ra action_parts <<< "${action}"

    # Separate non-terminal actions (log) from terminal action
    local -a non_terminal=()
    local terminal_action=""
    local apart
    for apart in "${action_parts[@]}"; do
        apart="$(util_to_lower "${apart}")"
        case "${apart}" in
            log) non_terminal+=("${apart}") ;;
            *)   terminal_action="${apart}" ;;
        esac
    done

    # Apply non-terminal actions first (each as separate rule)
    local nt_action
    for nt_action in "${non_terminal[@]}"; do
        local -a nt_cmd=()
        nt_cmd+=("${base_args[@]}")
        nt_cmd+=("-A" "${chain}")
        # Insert chain after table args — rebuild properly
        # Actually, build the full command fresh for clarity
        local -a log_cmd=()
        [[ -n "${table}" ]] && log_cmd+=("-t" "${table}")
        log_cmd+=("-A" "${chain}")
        # Copy match args (everything after table and before chain in base_args)
        local skip_table=0
        local barg
        for barg in "${base_args[@]}"; do
            [[ "${barg}" == "-t" ]] && { skip_table=1; continue; }
            [[ "${skip_table}" -eq 1 ]] && { skip_table=0; continue; }
            log_cmd+=("${barg}")
        done
        log_cmd+=("-j" "LOG")
        # Log options
        if [[ -n "${log_prefix}" ]]; then
            log_cmd+=("--log-prefix" "${log_prefix}")
        elif [[ -n "${comment}" ]]; then
            # Auto-generate prefix from comment if not specified
            log_cmd+=("--log-prefix" "[${comment}] ")
        fi
        [[ -n "${log_level}" ]] && log_cmd+=("--log-level" "${log_level}")

        log_info "iptables" "Adding LOG rule: iptables ${log_cmd[*]}"
        if ! iptables "${log_cmd[@]}" 2>/dev/null; then
            log_error "iptables" "Failed to add LOG rule"
            return "${E_RULE_APPLY_FAIL}"
        fi
    done

    # Apply terminal action (if present)
    if [[ -n "${terminal_action}" ]]; then
        local target
        case "$(util_to_upper "${terminal_action}")" in
            ACCEPT)     target="ACCEPT" ;;
            DROP)       target="DROP" ;;
            REJECT)     target="REJECT" ;;
            MASQUERADE) target="MASQUERADE" ;;
            SNAT)       target="SNAT" ;;
            DNAT)       target="DNAT" ;;
            RETURN)     target="RETURN" ;;
            *)
                log_error "iptables" "Unsupported terminal action: ${terminal_action}"
                return "${E_RULE_APPLY_FAIL}"
                ;;
        esac

        local -a term_cmd=()
        [[ -n "${table}" ]] && term_cmd+=("-t" "${table}")
        term_cmd+=("-A" "${chain}")
        local skip_table=0
        local barg
        for barg in "${base_args[@]}"; do
            [[ "${barg}" == "-t" ]] && { skip_table=1; continue; }
            [[ "${skip_table}" -eq 1 ]] && { skip_table=0; continue; }
            term_cmd+=("${barg}")
        done
        term_cmd+=("-j" "${target}")

        log_info "iptables" "Adding rule: iptables ${term_cmd[*]}"
        if ! iptables "${term_cmd[@]}" 2>/dev/null; then
            log_error "iptables" "Failed to add rule"
            return "${E_RULE_APPLY_FAIL}"
        fi
    fi

    # If action was purely non-terminal (just "log" alone), apply only the LOG rule
    if [[ -z "${terminal_action}" ]] && [[ "${#non_terminal[@]}" -eq 0 ]]; then
        log_error "iptables" "No valid action to apply"
        return "${E_RULE_APPLY_FAIL}"
    fi

    log_info "iptables" "Rule(s) added successfully"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_iptables_remove_rule()
# Description:  Remove iptables rule(s). For compound actions (e.g., log,drop),
#               removes both the LOG rule and the terminal rule, mirroring the
#               add logic to prevent orphaned rules in the kernel netfilter table.
#               Re-validates all parameters from the rule index before use (H4).
# Parameters:   Same as add_rule (rule will be matched and removed)
# Returns:      0 on success, E_RULE_REMOVE_FAIL on failure
# ==============================================================================
fw_iptables_remove_rule() {
    local -n _rule="${1:?fw_iptables_remove_rule requires rule array name}"

    local direction="${_rule[direction]:-inbound}"
    local protocol="${_rule[protocol]:-}"
    local src_ip="${_rule[src_ip]:-}"
    local dst_ip="${_rule[dst_ip]:-}"
    local src_port="${_rule[src_port]:-}"
    local dst_port="${_rule[dst_port]:-}"
    local action="${_rule[action]:-accept}"
    local chain="${_rule[chain]:-}"
    local table="${_rule[table]:-filter}"
    local comment="${_rule[comment]:-}"
    local conn_state="${_rule[conn_state]:-}"
    local log_prefix="${_rule[log_prefix]:-}"
    local log_level="${_rule[log_level]:-}"
    local limit="${_rule[limit]:-}"
    local limit_burst="${_rule[limit_burst]:-}"

    # H4 FIX: Re-validate parameters from index before constructing -D command
    if [[ -n "${protocol}" ]]; then
        protocol="$(validate_protocol "${protocol}" 2>/dev/null)" || {
            log_error "iptables" "Invalid protocol in stored rule: ${protocol}"
            return "${E_RULE_REMOVE_FAIL}"
        }
    fi
    [[ -n "${src_ip}" ]] && { validate_ip "${src_ip}" || validate_cidr "${src_ip}" || {
        log_error "iptables" "Invalid source IP in stored rule: ${src_ip}"
        return "${E_RULE_REMOVE_FAIL}"
    }; }
    [[ -n "${dst_ip}" ]] && { validate_ip "${dst_ip}" || validate_cidr "${dst_ip}" || {
        log_error "iptables" "Invalid destination IP in stored rule: ${dst_ip}"
        return "${E_RULE_REMOVE_FAIL}"
    }; }
    [[ -n "${src_port}" ]] && { validate_port "${src_port}" || validate_port_range "${src_port}" || {
        log_error "iptables" "Invalid source port in stored rule: ${src_port}"
        return "${E_RULE_REMOVE_FAIL}"
    }; }
    [[ -n "${dst_port}" ]] && { validate_port "${dst_port}" || validate_port_range "${dst_port}" || {
        log_error "iptables" "Invalid destination port in stored rule: ${dst_port}"
        return "${E_RULE_REMOVE_FAIL}"
    }; }

    # Build base match arguments (shared across compound action rules)
    local -a base_args=()

    [[ -n "${table}" ]] && base_args+=("-t" "${table}")

    if [[ -z "${chain}" ]]; then
        case "${direction}" in
            inbound)  chain="INPUT" ;;
            outbound) chain="OUTPUT" ;;
            forward)  chain="FORWARD" ;;
        esac
    fi

    [[ -n "${protocol}" ]] && [[ "${protocol}" != "all" ]] && base_args+=("-p" "${protocol}")
    [[ -n "${src_ip}" ]] && base_args+=("-s" "${src_ip}")
    [[ -n "${dst_ip}" ]] && base_args+=("-d" "${dst_ip}")
    [[ -n "${src_port}" ]] && base_args+=("--sport" "${src_port}")
    [[ -n "${dst_port}" ]] && base_args+=("--dport" "${dst_port}")

    # Connection tracking match (if originally applied)
    if [[ -n "${conn_state}" ]]; then
        local ct_state
        ct_state="$(printf '%s' "${conn_state}" | tr '[:lower:]' '[:upper:]')"
        base_args+=("-m" "conntrack" "--ctstate" "${ct_state}")
    fi

    # Rate limit match (if originally applied)
    if [[ -n "${limit}" ]]; then
        base_args+=("-m" "limit" "--limit" "${limit}")
        [[ -n "${limit_burst}" ]] && base_args+=("--limit-burst" "${limit_burst}")
    fi

    # Comment match
    if [[ -n "${comment}" ]]; then
        comment="$(sanitize_input "${comment}")"
        base_args+=("-m" "comment" "--comment" "${comment}")
    fi

    # Helper: extract table args and match args from base_args
    # (base_args contains -t table followed by match args)
    _iptables_build_delete_cmd() {
        local target_action="$1"
        local -a del_cmd=()
        local skip_table=0
        local barg

        # Table args
        [[ -n "${table}" ]] && del_cmd+=("-t" "${table}")
        # Chain
        del_cmd+=("-D" "${chain}")
        # Match args (everything in base_args except -t and its value)
        for barg in "${base_args[@]}"; do
            [[ "${barg}" == "-t" ]] && { skip_table=1; continue; }
            [[ "${skip_table}" -eq 1 ]] && { skip_table=0; continue; }
            del_cmd+=("${barg}")
        done
        # Target
        del_cmd+=("-j" "${target_action}")

        printf '%s\n' "${del_cmd[@]}"
    }

    # Parse compound action to determine which rules to remove
    local action_lower
    action_lower="$(printf '%s' "${action}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
    local -a action_parts=()
    local IFS=','
    read -ra action_parts <<< "${action_lower}"

    local -a non_terminal=()
    local terminal_action=""
    local apart
    for apart in "${action_parts[@]}"; do
        case "${apart}" in
            log) non_terminal+=("${apart}") ;;
            *)   terminal_action="${apart}" ;;
        esac
    done

    local remove_failed=0

    # Remove terminal action rule first (order: terminal before non-terminal
    # so LOG rule isn't matching traffic with no terminal to follow)
    if [[ -n "${terminal_action}" ]]; then
        local target
        case "$(util_to_upper "${terminal_action}")" in
            ACCEPT) target="ACCEPT" ;; DROP) target="DROP" ;; REJECT) target="REJECT" ;;
            MASQUERADE) target="MASQUERADE" ;; SNAT) target="SNAT" ;; DNAT) target="DNAT" ;;
            RETURN) target="RETURN" ;; *) target="$(util_to_upper "${terminal_action}")" ;;
        esac

        local -a term_cmd=()
        [[ -n "${table}" ]] && term_cmd+=("-t" "${table}")
        term_cmd+=("-D" "${chain}")
        local skip_table=0
        local barg
        for barg in "${base_args[@]}"; do
            [[ "${barg}" == "-t" ]] && { skip_table=1; continue; }
            [[ "${skip_table}" -eq 1 ]] && { skip_table=0; continue; }
            term_cmd+=("${barg}")
        done
        term_cmd+=("-j" "${target}")

        log_info "iptables" "Removing terminal rule: iptables ${term_cmd[*]}"
        if ! iptables "${term_cmd[@]}" 2>/dev/null; then
            log_warning "iptables" "Failed to remove terminal rule (may have been manually removed)"
            remove_failed=1
        fi
    fi

    # Remove non-terminal (LOG) rules
    local nt_action
    for nt_action in "${non_terminal[@]}"; do
        local -a log_cmd=()
        [[ -n "${table}" ]] && log_cmd+=("-t" "${table}")
        log_cmd+=("-D" "${chain}")
        local skip_table=0
        local barg
        for barg in "${base_args[@]}"; do
            [[ "${barg}" == "-t" ]] && { skip_table=1; continue; }
            [[ "${skip_table}" -eq 1 ]] && { skip_table=0; continue; }
            log_cmd+=("${barg}")
        done
        log_cmd+=("-j" "LOG")
        # Log options that were on the original rule
        if [[ -n "${log_prefix}" ]]; then
            log_cmd+=("--log-prefix" "${log_prefix}")
        elif [[ -n "${comment}" ]]; then
            log_cmd+=("--log-prefix" "[${comment}] ")
        fi
        [[ -n "${log_level}" ]] && log_cmd+=("--log-level" "${log_level}")

        log_info "iptables" "Removing LOG rule: iptables ${log_cmd[*]}"
        if ! iptables "${log_cmd[@]}" 2>/dev/null; then
            log_warning "iptables" "Failed to remove LOG rule (may have been manually removed)"
            remove_failed=1
        fi
    done

    # If action was a single action (not compound), handle the simple case
    if [[ -z "${terminal_action}" ]] && [[ "${#non_terminal[@]}" -eq 0 ]]; then
        # Single non-compound action — legacy path
        local -a simple_cmd=()
        [[ -n "${table}" ]] && simple_cmd+=("-t" "${table}")
        simple_cmd+=("-D" "${chain}")
        local skip_table=0
        local barg
        for barg in "${base_args[@]}"; do
            [[ "${barg}" == "-t" ]] && { skip_table=1; continue; }
            [[ "${skip_table}" -eq 1 ]] && { skip_table=0; continue; }
            simple_cmd+=("${barg}")
        done
        simple_cmd+=("-j" "$(util_to_upper "${action}")")

        log_info "iptables" "Removing rule: iptables ${simple_cmd[*]}"
        if ! iptables "${simple_cmd[@]}" 2>/dev/null; then
            log_error "iptables" "Failed to remove rule"
            return "${E_RULE_REMOVE_FAIL}"
        fi
    fi

    if [[ "${remove_failed}" -eq 1 ]]; then
        log_warning "iptables" "Rule removal partially completed (some rules may have been manually removed)"
    else
        log_info "iptables" "Rule(s) removed successfully"
    fi
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_iptables_list_rules()
# Description:  List current iptables rules.
# Parameters:   $1 - Table (optional, default: filter)
#               $2 - Chain (optional, list all if not specified)
# Returns:      0 on success, rule listing on stdout
# ==============================================================================
fw_iptables_list_rules() {
    local table="${1:-filter}"
    local chain="${2:-}"
    local -a cmd_args=("-t" "${table}" "-L" "-n" "-v" "--line-numbers")

    [[ -n "${chain}" ]] && cmd_args+=("${chain}")

    local output
    output="$(iptables "${cmd_args[@]}" 2>&1)" || true
    if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"you must be root"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
        printf '  %bRoot privileges required to list iptables rules%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return "${E_PERMISSION}"
    fi
    printf '%s\n' "${output}"
}

# ==============================================================================
# fw_iptables_enable()
# Description:  Start/enable iptables service.
# ==============================================================================
fw_iptables_enable() {
    if util_is_command_available systemctl; then
        systemctl start iptables 2>/dev/null || true
        systemctl enable iptables 2>/dev/null || true
    fi
    log_info "iptables" "iptables enabled"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_iptables_disable()
# Description:  Stop/disable iptables service.
# ==============================================================================
fw_iptables_disable() {
    if util_is_command_available systemctl; then
        systemctl stop iptables 2>/dev/null || true
    fi
    log_info "iptables" "iptables disabled"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_iptables_status()
# Description:  Get iptables status.
# ==============================================================================
fw_iptables_status() {
    printf '%biptables Status:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    local output
    output="$(iptables -L -n --line-numbers 2>&1)" || true
    if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"you must be root"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
        printf '  %bRoot privileges required to view iptables status%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        printf '  Run with: sudo apotropaios.sh\n'
    elif [[ -z "${output}" ]]; then
        printf '  No iptables rules currently configured\n'
    else
        printf '%s\n' "${output}"
    fi
}

# ==============================================================================
# fw_iptables_block_all()
# Description:  Block all inbound and outbound traffic.
# ==============================================================================
fw_iptables_block_all() {
    log_warning "iptables" "Blocking ALL traffic (inbound + outbound)"

    # Set default policies to DROP
    iptables -P INPUT DROP 2>/dev/null || true
    iptables -P OUTPUT DROP 2>/dev/null || true
    iptables -P FORWARD DROP 2>/dev/null || true

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
    iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true

    log_info "iptables" "All traffic blocked (loopback preserved)"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_iptables_allow_all()
# Description:  Allow all inbound and outbound traffic.
# ==============================================================================
fw_iptables_allow_all() {
    log_warning "iptables" "Allowing ALL traffic (inbound + outbound)"

    iptables -P INPUT ACCEPT 2>/dev/null || true
    iptables -P OUTPUT ACCEPT 2>/dev/null || true
    iptables -P FORWARD ACCEPT 2>/dev/null || true

    log_info "iptables" "All traffic allowed"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_iptables_reset()
# Description:  Flush all rules and reset to defaults.
# ==============================================================================
fw_iptables_reset() {
    log_warning "iptables" "Resetting iptables to defaults (flushing all rules)"

    # Flush all chains in all tables
    local tbl
    for tbl in filter nat mangle raw security; do
        iptables -t "${tbl}" -F 2>/dev/null || true
        iptables -t "${tbl}" -X 2>/dev/null || true
        iptables -t "${tbl}" -Z 2>/dev/null || true
    done

    # Reset default policies
    iptables -P INPUT ACCEPT 2>/dev/null || true
    iptables -P OUTPUT ACCEPT 2>/dev/null || true
    iptables -P FORWARD ACCEPT 2>/dev/null || true

    log_info "iptables" "iptables reset complete"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_iptables_save()
# Description:  Save current iptables rules to file.
# Parameters:   $1 - Output file path (optional, defaults to standard location)
# ==============================================================================
fw_iptables_save() {
    local output="${1:-/etc/iptables/rules.v4}"
    local dir
    dir="$(dirname "${output}")"
    mkdir -p "${dir}" 2>/dev/null || true

    if util_is_command_available iptables-save; then
        iptables-save > "${output}" 2>/dev/null || {
            log_error "iptables" "Failed to save rules to ${output}"
            return "${E_GENERAL}"
        }
        chmod "${SECURE_FILE_PERMS}" "${output}" 2>/dev/null || true
        log_info "iptables" "Rules saved to ${output}"
    else
        log_error "iptables" "iptables-save command not available"
        return "${E_GENERAL}"
    fi
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_iptables_reload()
# Description:  Reload iptables rules from file.
# Parameters:   $1 - Input file path
# ==============================================================================
fw_iptables_reload() {
    local input="${1:-/etc/iptables/rules.v4}"

    [[ ! -f "${input}" ]] && {
        log_error "iptables" "Rules file not found: ${input}"
        return "${E_GENERAL}"
    }

    if util_is_command_available iptables-restore; then
        iptables-restore < "${input}" 2>/dev/null || {
            log_error "iptables" "Failed to reload rules from ${input}"
            return "${E_GENERAL}"
        }
        log_info "iptables" "Rules reloaded from ${input}"
    else
        log_error "iptables" "iptables-restore command not available"
        return "${E_GENERAL}"
    fi
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_iptables_export_config()
# Description:  Export current iptables configuration as text.
# Returns:      Configuration text on stdout
# ==============================================================================
fw_iptables_export_config() {
    if util_is_command_available iptables-save; then
        iptables-save 2>/dev/null
    else
        iptables -L -n -v 2>/dev/null
    fi
}
