#!/usr/bin/env bash
# ==============================================================================
# File:         lib/rules/rule_engine.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Rule creation, application, removal, and lifecycle management
# Description:  Orchestrates firewall rule lifecycle: validates parameters,
#               generates unique rule IDs, dispatches to the appropriate backend,
#               and updates the rule index and state tracking. Supports both
#               interactive and batch rule creation.
# Notes:        - Requires core libs + firewall backends + rule_index + rule_state
#               - Rules are assigned UUIDs for tracking across sessions
#               - All parameters validated before rule creation
#               - Rule application is atomic — rollback on partial failure
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_RULE_ENGINE_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_RULE_ENGINE_LOADED=1

# ==============================================================================
# rule_create()
# Description:  Create and apply a firewall rule. Validates all parameters,
#               generates a UUID, applies via the active backend, and records
#               in the rule index.
# Parameters:   Associative array name (nameref) with rule parameters
# Returns:      0 on success, sets RULE_CREATE_ID to the new rule UUID
# ==============================================================================
RULE_CREATE_ID=""

rule_create() {
    local -n _params="${1:?rule_create requires parameter array name}"

    log_info "rule_engine" "Creating new firewall rule"

    # Validate required parameters
    local direction="${_params[direction]:-inbound}"
    local action="${_params[action]:-accept}"
    local backend="${_params[backend]:-${FW_ACTIVE_BACKEND}}"
    local duration_type="${_params[duration_type]:-permanent}"
    local ttl="${_params[ttl]:-0}"
    local description="${_params[description]:-}"

    # Normalize action: lowercase, strip spaces
    action="$(printf '%s' "${action}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
    _params[action]="${action}"

    # Validate direction
    validate_rule_direction "${direction}" || {
        log_error "rule_engine" "Invalid direction: ${direction}"
        return "${E_RULE_INVALID}"
    }

    # Validate action (supports compound: "log,drop")
    validate_rule_action "${action}" || {
        log_error "rule_engine" "Invalid action: ${action}"
        return "${E_RULE_INVALID}"
    }

    # Validate duration type
    validate_duration_type "${duration_type}" || {
        log_error "rule_engine" "Invalid duration type: ${duration_type}"
        return "${E_RULE_INVALID}"
    }

    # Validate TTL for temporary rules
    if [[ "${duration_type}" == "temporary" ]]; then
        validate_ttl "${ttl}" || {
            log_error "rule_engine" "Invalid TTL: ${ttl}"
            return "${E_RULE_INVALID}"
        }
    fi

    # Validate connection state if provided
    if [[ -n "${_params[conn_state]:-}" ]]; then
        validate_conn_state "${_params[conn_state]}" || {
            log_error "rule_engine" "Invalid connection state: ${_params[conn_state]}"
            return "${E_RULE_INVALID}"
        }
    fi

    # Validate log prefix if provided
    if [[ -n "${_params[log_prefix]:-}" ]]; then
        validate_log_prefix "${_params[log_prefix]}" || {
            log_error "rule_engine" "Invalid log prefix: ${_params[log_prefix]}"
            return "${E_RULE_INVALID}"
        }
    fi

    # Validate rate limit if provided
    if [[ -n "${_params[limit]:-}" ]]; then
        validate_rate_limit "${_params[limit]}" || {
            log_error "rule_engine" "Invalid rate limit: ${_params[limit]}"
            return "${E_RULE_INVALID}"
        }
    fi

    # Validate optional parameters if present
    [[ -n "${_params[protocol]:-}" ]] && {
        validate_protocol "${_params[protocol]}" >/dev/null || {
            log_error "rule_engine" "Invalid protocol: ${_params[protocol]}"
            return "${E_RULE_INVALID}"
        }
    }
    [[ -n "${_params[src_ip]:-}" ]] && {
        validate_ip "${_params[src_ip]}" || validate_cidr "${_params[src_ip]}" || {
            log_error "rule_engine" "Invalid source IP: ${_params[src_ip]}"
            return "${E_RULE_INVALID}"
        }
    }
    [[ -n "${_params[dst_ip]:-}" ]] && {
        validate_ip "${_params[dst_ip]}" || validate_cidr "${_params[dst_ip]}" || {
            log_error "rule_engine" "Invalid destination IP: ${_params[dst_ip]}"
            return "${E_RULE_INVALID}"
        }
    }
    [[ -n "${_params[src_port]:-}" ]] && {
        validate_port "${_params[src_port]}" || validate_port_range "${_params[src_port]}" || {
            log_error "rule_engine" "Invalid source port: ${_params[src_port]}"
            return "${E_RULE_INVALID}"
        }
    }
    [[ -n "${_params[dst_port]:-}" ]] && {
        validate_port "${_params[dst_port]}" || validate_port_range "${_params[dst_port]}" || {
            log_error "rule_engine" "Invalid destination port: ${_params[dst_port]}"
            return "${E_RULE_INVALID}"
        }
    }
    [[ -n "${description}" ]] && validate_description "${description}"

    # Generate unique rule ID
    local rule_id
    rule_id="$(security_generate_uuid)"
    log_debug "rule_engine" "Generated rule ID: ${rule_id}"

    # Add tracking comment to rule parameters
    _params[comment]="apotropaios:${rule_id}"

    # Set backend if specified
    if [[ -n "${backend}" ]] && [[ "${backend}" != "${FW_ACTIVE_BACKEND}" ]]; then
        fw_set_backend "${backend}" || return "${E_FW_NOT_FOUND}"
    fi

    # Apply the rule via the active backend
    # The backend handles compound actions natively (e.g., iptables creates
    # separate LOG + terminal rules; nftables combines in one expression)
    log_info "rule_engine" "Applying rule ${rule_id} via ${FW_ACTIVE_BACKEND}" \
        "action=${action} direction=${direction}"
    if ! fw_add_rule "_params"; then
        log_error "rule_engine" "Failed to apply rule ${rule_id}"
        return "${E_RULE_APPLY_FAIL}"
    fi

    # Record in rule index
    local timestamp
    timestamp="$(util_timestamp)"

    local -A rule_record=(
        [rule_id]="${rule_id}"
        [backend]="${FW_ACTIVE_BACKEND}"
        [direction]="${direction}"
        [action]="${action}"
        [protocol]="${_params[protocol]:-any}"
        [src_ip]="${_params[src_ip]:-any}"
        [dst_ip]="${_params[dst_ip]:-any}"
        [src_port]="${_params[src_port]:-any}"
        [dst_port]="${_params[dst_port]:-any}"
        [interface]="${_params[interface]:-any}"
        [chain]="${_params[chain]:-}"
        [table]="${_params[table]:-}"
        [zone]="${_params[zone]:-}"
        [set_name]="${_params[set_name]:-}"
        [conn_state]="${_params[conn_state]:-}"
        [log_prefix]="${_params[log_prefix]:-}"
        [log_level]="${_params[log_level]:-}"
        [limit]="${_params[limit]:-}"
        [limit_burst]="${_params[limit_burst]:-}"
        [duration_type]="${duration_type}"
        [ttl]="${ttl}"
        [description]="${description}"
        [state]="active"
        [created_at]="${timestamp}"
        [activated_at]="${timestamp}"
        [expires_at]=""
    )

    # Calculate expiry for temporary rules
    if [[ "${duration_type}" == "temporary" ]] && [[ "${ttl}" -gt 0 ]]; then
        local epoch_now
        epoch_now="$(util_timestamp_epoch)"
        local expire_epoch=$((epoch_now + ttl))
        rule_record[expires_at]="$(date -u -d @"${expire_epoch}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || \
            rule_record[expires_at]="${expire_epoch}"
    fi

    # Add to index
    rule_index_add "rule_record" || {
        log_error "rule_engine" "Failed to index rule ${rule_id} — rule was applied but not tracked"
        return "${E_GENERAL}"
    }

    # Update state tracking
    rule_state_set "${rule_id}" "active" "${duration_type}" "${ttl}" || true

    RULE_CREATE_ID="${rule_id}"
    log_info "rule_engine" "Rule created and applied: ${rule_id}" \
        "backend=${FW_ACTIVE_BACKEND} direction=${direction} action=${action}"

    return "${E_SUCCESS}"
}

# ==============================================================================
# rule_remove()
# Description:  Remove a firewall rule by its UUID.
# Parameters:   $1 - Rule ID (UUID)
#               $2 - Remove from backend (1=yes, 0=index only; default: 1)
# Returns:      0 on success
# ==============================================================================
rule_remove() {
    local rule_id="${1:?rule_remove requires rule ID}"
    local remove_backend="${2:-1}"

    validate_rule_id "${rule_id}" || {
        log_error "rule_engine" "Invalid rule ID format: ${rule_id}"
        return "${E_RULE_INVALID}"
    }

    log_info "rule_engine" "Removing rule: ${rule_id}"

    # Look up rule in index
    local -A rule_data=()
    if ! rule_index_get "${rule_id}" "rule_data"; then
        log_error "rule_engine" "Rule not found in index: ${rule_id}"
        return "${E_RULE_NOT_FOUND}"
    fi

    # Remove from firewall backend
    if [[ "${remove_backend}" -eq 1 ]]; then
        local backend="${rule_data[backend]:-${FW_ACTIVE_BACKEND}}"

        # Temporarily switch backend if needed
        local original_backend="${FW_ACTIVE_BACKEND}"
        if [[ "${backend}" != "${FW_ACTIVE_BACKEND}" ]]; then
            fw_set_backend "${backend}" || {
                log_error "rule_engine" "Cannot set backend ${backend} for rule removal"
                return "${E_FW_NOT_FOUND}"
            }
        fi

        # Build removal parameters
        local -A remove_params=()
        local key
        for key in "${!rule_data[@]}"; do
            remove_params["${key}"]="${rule_data[${key}]}"
        done
        remove_params[comment]="apotropaios:${rule_id}"

        if ! fw_remove_rule "remove_params"; then
            log_warning "rule_engine" "Backend removal failed for rule ${rule_id} (may have been manually removed)"
        fi

        # Restore original backend
        if [[ "${backend}" != "${original_backend}" ]] && [[ -n "${original_backend}" ]]; then
            FW_ACTIVE_BACKEND="${original_backend}"
        fi
    fi

    # Remove from index
    rule_index_remove "${rule_id}" || {
        log_warning "rule_engine" "Failed to remove rule from index: ${rule_id}"
    }

    # Remove from state tracking
    rule_state_remove "${rule_id}" || true

    log_info "rule_engine" "Rule removed: ${rule_id}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# rule_deactivate()
# Description:  Deactivate a rule (remove from firewall but keep in index).
# Parameters:   $1 - Rule ID
# Returns:      0 on success
# ==============================================================================
rule_deactivate() {
    local rule_id="${1:?rule_deactivate requires rule ID}"

    validate_rule_id "${rule_id}" || return "${E_RULE_INVALID}"

    local -A rule_data=()
    rule_index_get "${rule_id}" "rule_data" || return "${E_RULE_NOT_FOUND}"

    if [[ "${rule_data[state]:-}" == "inactive" ]]; then
        log_warning "rule_engine" "Rule already inactive: ${rule_id}"
        return "${E_SUCCESS}"
    fi

    # Remove from backend but keep in index
    local -A remove_params=()
    local key
    for key in "${!rule_data[@]}"; do
        remove_params["${key}"]="${rule_data[${key}]}"
    done
    remove_params[comment]="apotropaios:${rule_id}"

    local backend="${rule_data[backend]:-${FW_ACTIVE_BACKEND}}"
    local original_backend="${FW_ACTIVE_BACKEND}"
    [[ "${backend}" != "${FW_ACTIVE_BACKEND}" ]] && fw_set_backend "${backend}" 2>/dev/null

    fw_remove_rule "remove_params" || log_warning "rule_engine" "Backend deactivation may have partially failed"

    [[ "${backend}" != "${original_backend}" ]] && FW_ACTIVE_BACKEND="${original_backend}"

    # Update state
    rule_index_update_field "${rule_id}" "state" "inactive"
    rule_state_set "${rule_id}" "inactive" "" "" || true

    log_info "rule_engine" "Rule deactivated: ${rule_id}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# rule_activate()
# Description:  Re-activate a previously deactivated rule.
# Parameters:   $1 - Rule ID
# Returns:      0 on success
# ==============================================================================
rule_activate() {
    local rule_id="${1:?rule_activate requires rule ID}"

    validate_rule_id "${rule_id}" || return "${E_RULE_INVALID}"

    local -A rule_data=()
    rule_index_get "${rule_id}" "rule_data" || return "${E_RULE_NOT_FOUND}"

    if [[ "${rule_data[state]:-}" == "active" ]]; then
        log_warning "rule_engine" "Rule already active: ${rule_id}"
        return "${E_SUCCESS}"
    fi

    # Re-apply via backend
    local -A apply_params=()
    local key
    for key in "${!rule_data[@]}"; do
        apply_params["${key}"]="${rule_data[${key}]}"
    done
    apply_params[comment]="apotropaios:${rule_id}"

    local backend="${rule_data[backend]:-${FW_ACTIVE_BACKEND}}"
    local original_backend="${FW_ACTIVE_BACKEND}"
    [[ "${backend}" != "${FW_ACTIVE_BACKEND}" ]] && fw_set_backend "${backend}" 2>/dev/null

    if ! fw_add_rule "apply_params"; then
        log_error "rule_engine" "Failed to re-activate rule ${rule_id}"
        [[ "${backend}" != "${original_backend}" ]] && FW_ACTIVE_BACKEND="${original_backend}"
        return "${E_RULE_APPLY_FAIL}"
    fi

    [[ "${backend}" != "${original_backend}" ]] && FW_ACTIVE_BACKEND="${original_backend}"

    # Update state
    local timestamp
    timestamp="$(util_timestamp)"
    rule_index_update_field "${rule_id}" "state" "active"
    rule_index_update_field "${rule_id}" "activated_at" "${timestamp}"
    rule_state_set "${rule_id}" "active" "${rule_data[duration_type]:-permanent}" "${rule_data[ttl]:-0}" || true

    log_info "rule_engine" "Rule re-activated: ${rule_id}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# rule_block_all_traffic()
# Description:  Create and apply rules to block all inbound/outbound traffic.
# Returns:      0 on success
# ==============================================================================
rule_block_all_traffic() {
    _fw_require_backend || return 1

    log_warning "rule_engine" "Blocking ALL traffic via ${FW_ACTIVE_BACKEND}"

    if ! fw_block_all; then
        log_error "rule_engine" "Failed to block all traffic"
        return "${E_RULE_APPLY_FAIL}"
    fi

    # Record as a special tracked rule
    local rule_id
    rule_id="$(security_generate_uuid)"
    local timestamp
    timestamp="$(util_timestamp)"

    local -A rule_record=(
        [rule_id]="${rule_id}"
        [backend]="${FW_ACTIVE_BACKEND}"
        [direction]="all"
        [action]="drop"
        [protocol]="all"
        [src_ip]="any"
        [dst_ip]="any"
        [src_port]="any"
        [dst_port]="any"
        [duration_type]="permanent"
        [ttl]="0"
        [description]="BLOCK ALL TRAFFIC"
        [state]="active"
        [created_at]="${timestamp}"
        [activated_at]="${timestamp}"
        [expires_at]=""
    )
    rule_index_add "rule_record" || true

    log_info "rule_engine" "All traffic blocked (rule_id=${rule_id})"
    return "${E_SUCCESS}"
}

# ==============================================================================
# rule_allow_all_traffic()
# Description:  Create and apply rules to allow all inbound/outbound traffic.
# Returns:      0 on success
# ==============================================================================
rule_allow_all_traffic() {
    _fw_require_backend || return 1

    log_warning "rule_engine" "Allowing ALL traffic via ${FW_ACTIVE_BACKEND}"

    if ! fw_allow_all; then
        log_error "rule_engine" "Failed to allow all traffic"
        return "${E_RULE_APPLY_FAIL}"
    fi

    local rule_id
    rule_id="$(security_generate_uuid)"
    local timestamp
    timestamp="$(util_timestamp)"

    local -A rule_record=(
        [rule_id]="${rule_id}"
        [backend]="${FW_ACTIVE_BACKEND}"
        [direction]="all"
        [action]="accept"
        [protocol]="all"
        [src_ip]="any"
        [dst_ip]="any"
        [src_port]="any"
        [dst_port]="any"
        [duration_type]="permanent"
        [ttl]="0"
        [description]="ALLOW ALL TRAFFIC"
        [state]="active"
        [created_at]="${timestamp}"
        [activated_at]="${timestamp}"
        [expires_at]=""
    )
    rule_index_add "rule_record" || true

    log_info "rule_engine" "All traffic allowed (rule_id=${rule_id})"
    return "${E_SUCCESS}"
}

# ==============================================================================
# rule_check_expired()
# Description:  Check for and handle expired temporary rules.
# Returns:      Number of expired rules processed
# ==============================================================================
rule_check_expired() {
    local expired_count=0
    local now_epoch
    now_epoch="$(util_timestamp_epoch)"

    log_debug "rule_engine" "Checking for expired temporary rules"

    local rule_id
    while IFS= read -r rule_id; do
        [[ -z "${rule_id}" ]] && continue

        local -A rule_data=()
        rule_index_get "${rule_id}" "rule_data" || continue

        [[ "${rule_data[duration_type]:-}" != "temporary" ]] && continue
        [[ "${rule_data[state]:-}" != "active" ]] && continue

        local expires_at="${rule_data[expires_at]:-}"
        [[ -z "${expires_at}" ]] && continue

        # Convert expiry to epoch for comparison
        local expire_epoch
        expire_epoch="$(date -d "${expires_at}" '+%s' 2>/dev/null)" || expire_epoch="${expires_at}"

        if [[ "${now_epoch}" -ge "${expire_epoch}" ]]; then
            log_info "rule_engine" "Rule expired: ${rule_id} (expired at ${expires_at})"
            rule_deactivate "${rule_id}" || true
            rule_index_update_field "${rule_id}" "state" "expired"
            ((expired_count++)) || true
        fi
    done < <(rule_index_list_ids)

    [[ "${expired_count}" -gt 0 ]] && \
        log_info "rule_engine" "Processed ${expired_count} expired rule(s)"

    return "${expired_count}"
}
