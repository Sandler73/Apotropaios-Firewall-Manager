#!/usr/bin/env bash
# ==============================================================================
# File:         lib/rules/rule_state.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Rule activation state and TTL (time-to-live) tracking
# Description:  Tracks the activation state of firewall rules including
#               permanent/temporary designation, time-based expiry for
#               temporary rules, and state persistence across sessions.
# Notes:        - Requires core libs + rule_index
#               - State file written to disk alongside rule index
#               - TTL expiry checked by rule_check_expired() in rule_engine
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_RULE_STATE_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_RULE_STATE_LOADED=1

# ==============================================================================
# State Variables
# ==============================================================================

# In-memory state: keyed by rule_id
declare -A _RULE_STATE_MAP=()
declare -A _RULE_STATE_TYPE=()     # permanent or temporary
declare -A _RULE_STATE_TTL=()      # TTL in seconds (0 for permanent)
declare -A _RULE_STATE_CREATED=()  # Epoch when state was set
declare -A _RULE_STATE_EXPIRES=()  # Epoch when rule expires (0 for permanent)

# State file path
_RULE_STATE_FILE=""

# ==============================================================================
# rule_state_init()
# Description:  Initialize rule state tracking.
# Parameters:   $1 - Rules data directory
# Returns:      0 on success
# ==============================================================================
rule_state_init() {
    local rules_dir="${1:?rule_state_init requires rules directory}"

    _RULE_STATE_FILE="${rules_dir}/${APOTROPAIOS_RULE_STATE_FILE}"

    # Load existing state
    if [[ -f "${_RULE_STATE_FILE}" ]]; then
        _rule_state_load || log_warning "rule_state" "Failed to load state file"
    fi

    log_info "rule_state" "Rule state tracking initialized"
    return "${E_SUCCESS}"
}

# ==============================================================================
# rule_state_set()
# Description:  Set or update the state of a rule.
# Parameters:   $1 - Rule ID
#               $2 - State (active, inactive, expired, pending)
#               $3 - Duration type (permanent, temporary)
#               $4 - TTL in seconds (for temporary rules)
# Returns:      0 on success
# ==============================================================================
rule_state_set() {
    local rule_id="${1:?rule_state_set requires rule ID}"
    local state="${2:-active}"
    local duration_type="${3:-permanent}"
    local ttl="${4:-0}"

    local now_epoch
    now_epoch="$(util_timestamp_epoch)"

    _RULE_STATE_MAP["${rule_id}"]="${state}"
    _RULE_STATE_TYPE["${rule_id}"]="${duration_type}"
    _RULE_STATE_TTL["${rule_id}"]="${ttl}"
    _RULE_STATE_CREATED["${rule_id}"]="${now_epoch}"

    # Calculate expiry
    if [[ "${duration_type}" == "temporary" ]] && [[ "${ttl}" -gt 0 ]]; then
        _RULE_STATE_EXPIRES["${rule_id}"]="$((now_epoch + ttl))"
    else
        _RULE_STATE_EXPIRES["${rule_id}"]="0"
    fi

    # Persist
    _rule_state_save || true

    log_debug "rule_state" "State set: ${rule_id} state=${state} type=${duration_type} ttl=${ttl}"
    return 0
}

# ==============================================================================
# rule_state_get()
# Description:  Get the current state of a rule.
# Parameters:   $1 - Rule ID
# Returns:      State string on stdout, 0 if found, 1 if not
# ==============================================================================
rule_state_get() {
    local rule_id="${1:?rule_state_get requires rule ID}"

    if [[ -n "${_RULE_STATE_MAP[${rule_id}]+exists}" ]]; then
        printf '%s' "${_RULE_STATE_MAP[${rule_id}]}"
        return 0
    fi
    return 1
}

# ==============================================================================
# rule_state_remove()
# Description:  Remove state tracking for a rule.
# Parameters:   $1 - Rule ID
# ==============================================================================
rule_state_remove() {
    local rule_id="${1:?rule_state_remove requires rule ID}"

    unset "_RULE_STATE_MAP[${rule_id}]" 2>/dev/null || true
    unset "_RULE_STATE_TYPE[${rule_id}]" 2>/dev/null || true
    unset "_RULE_STATE_TTL[${rule_id}]" 2>/dev/null || true
    unset "_RULE_STATE_CREATED[${rule_id}]" 2>/dev/null || true
    unset "_RULE_STATE_EXPIRES[${rule_id}]" 2>/dev/null || true

    _rule_state_save || true
    return 0
}

# ==============================================================================
# rule_state_is_expired()
# Description:  Check if a temporary rule has expired.
# Parameters:   $1 - Rule ID
# Returns:      0 if expired, 1 if not expired or not temporary
# ==============================================================================
rule_state_is_expired() {
    local rule_id="${1:?rule_state_is_expired requires rule ID}"

    [[ "${_RULE_STATE_TYPE[${rule_id}]:-permanent}" != "temporary" ]] && return 1

    local expires="${_RULE_STATE_EXPIRES[${rule_id}]:-0}"
    [[ "${expires}" -eq 0 ]] && return 1

    local now_epoch
    now_epoch="$(util_timestamp_epoch)"

    [[ "${now_epoch}" -ge "${expires}" ]] && return 0
    return 1
}

# ==============================================================================
# rule_state_time_remaining()
# Description:  Get remaining time for a temporary rule in seconds.
# Parameters:   $1 - Rule ID
# Returns:      Seconds remaining on stdout (0 if expired or permanent)
# ==============================================================================
rule_state_time_remaining() {
    local rule_id="${1:?}"

    local expires="${_RULE_STATE_EXPIRES[${rule_id}]:-0}"
    [[ "${expires}" -eq 0 ]] && { printf '0'; return; }

    local now_epoch
    now_epoch="$(util_timestamp_epoch)"

    local remaining=$((expires - now_epoch))
    [[ "${remaining}" -lt 0 ]] && remaining=0

    printf '%d' "${remaining}"
}

# ==============================================================================
# _rule_state_load() [INTERNAL]
# ==============================================================================
_rule_state_load() {
    [[ ! -f "${_RULE_STATE_FILE}" ]] && return 1

    local line
    while IFS='|' read -r rule_id state dtype ttl created expires || [[ -n "${rule_id}" ]]; do
        [[ -z "${rule_id}" ]] && continue
        [[ "${rule_id}" == "#"* ]] && continue

        _RULE_STATE_MAP["${rule_id}"]="${state}"
        _RULE_STATE_TYPE["${rule_id}"]="${dtype}"
        _RULE_STATE_TTL["${rule_id}"]="${ttl}"
        _RULE_STATE_CREATED["${rule_id}"]="${created}"
        _RULE_STATE_EXPIRES["${rule_id}"]="${expires}"
    done < "${_RULE_STATE_FILE}"

    return 0
}

# ==============================================================================
# _rule_state_save() [INTERNAL]
# ==============================================================================
_rule_state_save() {
    [[ -z "${_RULE_STATE_FILE}" ]] && return 1

    local tmp_file="${_RULE_STATE_FILE}.tmp.$$"
    {
        printf '# Apotropaios Rule State\n'
        printf '# Format: rule_id|state|duration_type|ttl|created_epoch|expires_epoch\n'

        local rule_id
        for rule_id in "${!_RULE_STATE_MAP[@]}"; do
            printf '%s|%s|%s|%s|%s|%s\n' \
                "${rule_id}" \
                "${_RULE_STATE_MAP[${rule_id}]}" \
                "${_RULE_STATE_TYPE[${rule_id}]:-permanent}" \
                "${_RULE_STATE_TTL[${rule_id}]:-0}" \
                "${_RULE_STATE_CREATED[${rule_id}]:-0}" \
                "${_RULE_STATE_EXPIRES[${rule_id}]:-0}"
        done
    } > "${tmp_file}" 2>/dev/null || { rm -f "${tmp_file}" 2>/dev/null; return 1; }

    mv -f "${tmp_file}" "${_RULE_STATE_FILE}" 2>/dev/null || { rm -f "${tmp_file}" 2>/dev/null; return 1; }
    chmod "${SECURE_FILE_PERMS}" "${_RULE_STATE_FILE}" 2>/dev/null || true
    return 0
}
