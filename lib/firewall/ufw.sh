#!/usr/bin/env bash
# ==============================================================================
# File:         lib/firewall/ufw.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     ufw (Uncomplicated Firewall) backend implementation
# Description:  Implements the firewall backend interface for ufw.
#               Provides rule management using ufw command syntax.
#               Handles both simple and extended rule formats.
# Notes:        - Requires root privileges for all operations
#               - ufw is frontend to iptables/nftables
#               - Supports allow/deny/reject/limit actions
#               - All input validated before command construction
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_FW_UFW_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_FW_UFW_LOADED=1

# ==============================================================================
# fw_ufw_add_rule()
# Description:  Add a ufw rule.
# Parameters:   Associative array name (nameref) with rule parameters
# Returns:      0 on success, E_RULE_APPLY_FAIL on failure
# ==============================================================================
fw_ufw_add_rule() {
    local -n _rule="${1:?fw_ufw_add_rule requires rule array name}"

    local direction="${_rule[direction]:-inbound}"
    local protocol="${_rule[protocol]:-}"
    local src_ip="${_rule[src_ip]:-}"
    local dst_ip="${_rule[dst_ip]:-}"
    local src_port="${_rule[src_port]:-}"
    local dst_port="${_rule[dst_port]:-}"
    local action="${_rule[action]:-allow}"
    local interface="${_rule[interface]:-}"
    local comment="${_rule[comment]:-}"

    # Build ufw command arguments array
    local -a cmd_args=()

    # Map action to ufw verbs — handle compound actions
    # UFW doesn't support compound actions natively, so we extract the
    # terminal action and handle log separately if needed.
    local ufw_action
    local action_lower
    action_lower="$(util_to_lower "${action}")"
    local has_log=0

    # Parse compound action
    if [[ "${action_lower}" == *","* ]]; then
        local -a action_parts=()
        local IFS=','
        read -ra action_parts <<< "${action_lower}"
        local terminal_found=""
        local apart
        for apart in "${action_parts[@]}"; do
            case "${apart}" in
                log) has_log=1 ;;
                accept|allow) terminal_found="allow" ;;
                drop|deny)    terminal_found="deny" ;;
                reject)       terminal_found="reject" ;;
                limit)        terminal_found="limit" ;;
            esac
        done
        ufw_action="${terminal_found:-allow}"
    else
        case "${action_lower}" in
            accept|allow) ufw_action="allow" ;;
            drop|deny)    ufw_action="deny" ;;
            reject)       ufw_action="reject" ;;
            limit)        ufw_action="limit" ;;
            log)          ufw_action="allow"; has_log=1 ;;
            *)
                log_error "ufw" "Unsupported action: ${action}"
                return "${E_RULE_APPLY_FAIL}"
                ;;
        esac
    fi

    # If logging requested, enable logging for ufw before adding rule
    if [[ "${has_log}" -eq 1 ]]; then
        log_info "ufw" "Enabling logging for rule (ufw logging on)"
        ufw logging on 2>/dev/null || true
    fi

    # Determine if we need simple or extended syntax
    local use_extended=0
    [[ -n "${src_ip}" ]] && use_extended=1
    [[ -n "${dst_ip}" ]] && use_extended=1
    [[ -n "${src_port}" ]] && use_extended=1
    [[ "${direction}" == "outbound" ]] && use_extended=1

    if [[ "${use_extended}" -eq 1 ]]; then
        # Extended syntax: ufw [allow|deny] [in|out] [on IFACE] [proto PROTO]
        #                  [from SRC [port PORT]] [to DST [port PORT]]
        #                  [comment COMMENT]

        cmd_args+=("${ufw_action}")

        # Direction
        case "${direction}" in
            inbound)  cmd_args+=("in") ;;
            outbound) cmd_args+=("out") ;;
        esac

        # Interface
        if [[ -n "${interface}" ]]; then
            validate_interface "${interface}" || return "${E_RULE_APPLY_FAIL}"
            cmd_args+=("on" "${interface}")
        fi

        # Protocol
        if [[ -n "${protocol}" ]] && [[ "${protocol}" != "all" ]]; then
            protocol="$(validate_protocol "${protocol}")" || return "${E_RULE_APPLY_FAIL}"
            cmd_args+=("proto" "${protocol}")
        fi

        # Source
        if [[ -n "${src_ip}" ]]; then
            if validate_ip "${src_ip}" || validate_cidr "${src_ip}"; then
                cmd_args+=("from" "${src_ip}")
            else
                log_error "ufw" "Invalid source IP: ${src_ip}"
                return "${E_RULE_APPLY_FAIL}"
            fi
        else
            cmd_args+=("from" "any")
        fi

        # Source port
        if [[ -n "${src_port}" ]]; then
            if validate_port "${src_port}" || validate_port_range "${src_port}"; then
                local ufw_src_port="${src_port//-/:}"
                cmd_args+=("port" "${ufw_src_port}")
            else
                log_error "ufw" "Invalid source port: ${src_port}"
                return "${E_RULE_APPLY_FAIL}"
            fi
        fi

        # Destination
        if [[ -n "${dst_ip}" ]]; then
            if validate_ip "${dst_ip}" || validate_cidr "${dst_ip}"; then
                cmd_args+=("to" "${dst_ip}")
            else
                log_error "ufw" "Invalid destination IP: ${dst_ip}"
                return "${E_RULE_APPLY_FAIL}"
            fi
        else
            cmd_args+=("to" "any")
        fi

        # Destination port
        if [[ -n "${dst_port}" ]]; then
            if validate_port "${dst_port}" || validate_port_range "${dst_port}"; then
                local ufw_dst_port="${dst_port//-/:}"
                cmd_args+=("port" "${ufw_dst_port}")
            else
                log_error "ufw" "Invalid destination port: ${dst_port}"
                return "${E_RULE_APPLY_FAIL}"
            fi
        fi

        # Comment
        if [[ -n "${comment}" ]]; then
            comment="$(sanitize_input "${comment}")"
            cmd_args+=("comment" "${comment}")
        fi

    else
        # Simple syntax: ufw [allow|deny] [PORT[/PROTO]]
        cmd_args+=("${ufw_action}")

        if [[ -n "${dst_port}" ]]; then
            if validate_port "${dst_port}" || validate_port_range "${dst_port}"; then
                local port_spec="${dst_port}"
                # Add protocol if specified
                if [[ -n "${protocol}" ]] && [[ "${protocol}" != "all" ]]; then
                    protocol="$(validate_protocol "${protocol}")" || return "${E_RULE_APPLY_FAIL}"
                    port_spec="${port_spec}/${protocol}"
                fi
                cmd_args+=("${port_spec}")
            else
                log_error "ufw" "Invalid port: ${dst_port}"
                return "${E_RULE_APPLY_FAIL}"
            fi
        fi

        if [[ -n "${comment}" ]]; then
            comment="$(sanitize_input "${comment}")"
            cmd_args+=("comment" "${comment}")
        fi
    fi

    # Execute
    log_info "ufw" "Adding rule: ufw ${cmd_args[*]}"
    if ! ufw "${cmd_args[@]}" 2>/dev/null; then
        log_error "ufw" "Failed to add rule"
        return "${E_RULE_APPLY_FAIL}"
    fi

    log_info "ufw" "Rule added successfully"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ufw_remove_rule()
# Description:  Remove a ufw rule by rule number or matching specification.
# ==============================================================================
fw_ufw_remove_rule() {
    local -n _rule="${1:?fw_ufw_remove_rule requires rule array name}"

    local rule_number="${_rule[rule_number]:-}"
    local dst_port="${_rule[dst_port]:-}"
    local protocol="${_rule[protocol]:-}"
    local action="${_rule[action]:-allow}"

    # Remove by number (preferred — unambiguous)
    if [[ -n "${rule_number}" ]]; then
        validate_numeric "${rule_number}" || return "${E_RULE_REMOVE_FAIL}"
        log_info "ufw" "Removing rule #${rule_number}"
        # Use yes pipe to auto-confirm
        printf 'y\n' | ufw delete "${rule_number}" 2>/dev/null || {
            log_error "ufw" "Failed to remove rule #${rule_number}"
            return "${E_RULE_REMOVE_FAIL}"
        }
        return "${E_SUCCESS}"
    fi

    # Remove by matching specification
    if [[ -n "${dst_port}" ]]; then
        local ufw_action
        case "$(util_to_lower "${action}")" in
            accept|allow) ufw_action="allow" ;;
            drop|deny)    ufw_action="deny" ;;
            reject)       ufw_action="reject" ;;
            *)            ufw_action="allow" ;;
        esac

        local port_spec="${dst_port}"
        [[ -n "${protocol}" ]] && port_spec="${port_spec}/${protocol}"

        log_info "ufw" "Removing rule: ufw delete ${ufw_action} ${port_spec}"
        printf 'y\n' | ufw delete "${ufw_action}" "${port_spec}" 2>/dev/null || {
            log_error "ufw" "Failed to remove rule"
            return "${E_RULE_REMOVE_FAIL}"
        }
        return "${E_SUCCESS}"
    fi

    log_error "ufw" "Cannot determine rule to remove"
    return "${E_RULE_NOT_FOUND}"
}

# ==============================================================================
# fw_ufw_list_rules()
# ==============================================================================
fw_ufw_list_rules() {
    ufw status numbered verbose 2>/dev/null || ufw status verbose 2>/dev/null
}

# ==============================================================================
# fw_ufw_enable()
# ==============================================================================
fw_ufw_enable() {
    # Non-interactive enable
    printf 'y\n' | ufw enable 2>/dev/null || true
    log_info "ufw" "ufw enabled"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ufw_disable()
# ==============================================================================
fw_ufw_disable() {
    ufw disable 2>/dev/null || true
    log_info "ufw" "ufw disabled"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ufw_status()
# ==============================================================================
fw_ufw_status() {
    printf '%bUFW Status:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    ufw status verbose 2>/dev/null || printf 'Unable to retrieve ufw status\n'
}

# ==============================================================================
# fw_ufw_block_all()
# ==============================================================================
fw_ufw_block_all() {
    log_warning "ufw" "Blocking ALL traffic"
    ufw default deny incoming 2>/dev/null || true
    ufw default deny outgoing 2>/dev/null || true
    ufw default deny routed 2>/dev/null || true

    # Ensure ufw is enabled
    printf 'y\n' | ufw enable 2>/dev/null || true

    log_info "ufw" "All traffic blocked"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ufw_allow_all()
# ==============================================================================
fw_ufw_allow_all() {
    log_warning "ufw" "Allowing ALL traffic"
    ufw default allow incoming 2>/dev/null || true
    ufw default allow outgoing 2>/dev/null || true
    ufw default allow routed 2>/dev/null || true
    log_info "ufw" "All traffic allowed"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ufw_reset()
# ==============================================================================
fw_ufw_reset() {
    log_warning "ufw" "Resetting ufw to defaults"
    printf 'y\n' | ufw reset 2>/dev/null || true
    log_info "ufw" "ufw reset complete"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ufw_save()
# ==============================================================================
fw_ufw_save() {
    local output="${1:-}"
    if [[ -n "${output}" ]]; then
        ufw status numbered verbose > "${output}" 2>/dev/null || return "${E_GENERAL}"
        chmod "${SECURE_FILE_PERMS}" "${output}" 2>/dev/null || true
        log_info "ufw" "Status exported to ${output}"
    fi
    # ufw rules are auto-persistent
    log_info "ufw" "ufw rules are automatically persistent"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ufw_reload()
# ==============================================================================
fw_ufw_reload() {
    ufw reload 2>/dev/null || {
        log_error "ufw" "Failed to reload ufw"
        return "${E_GENERAL}"
    }
    log_info "ufw" "ufw reloaded"
    return "${E_SUCCESS}"
}

# ==============================================================================
# fw_ufw_export_config()
# ==============================================================================
fw_ufw_export_config() {
    ufw status numbered verbose 2>/dev/null
}
