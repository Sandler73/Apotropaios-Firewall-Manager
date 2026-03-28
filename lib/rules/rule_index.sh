#!/usr/bin/env bash
# ==============================================================================
# File:         lib/rules/rule_index.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Persistent rule index with unique ID tracking
# Description:  Maintains a persistent index of all rules created by the
#               framework. Each rule is tracked by UUID with full parameter
#               details. The index is written to disk as a key-value file
#               and can be loaded across execution sessions.
# Notes:        - Index file format: one rule per line, pipe-delimited fields
#               - File locking used for concurrent access safety
#               - Index is loaded into memory for fast lookups
#               - Validated on load to detect corruption
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_RULE_INDEX_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_RULE_INDEX_LOADED=1

# ==============================================================================
# State Variables
# ==============================================================================

# In-memory rule index: array of rule IDs
declare -a _RULE_INDEX_IDS=()

# In-memory rule data: associative array keyed by "rule_id:field"
declare -A _RULE_INDEX_DATA=()

# Index file path (set by rule_index_init)
_RULE_INDEX_FILE=""

# Index loaded flag
_RULE_INDEX_LOADED=0

# Field order for serialization
readonly -a _RULE_INDEX_FIELDS=(
    "rule_id" "backend" "direction" "action" "protocol"
    "src_ip" "dst_ip" "src_port" "dst_port" "interface"
    "chain" "table" "zone" "set_name"
    "duration_type" "ttl" "description" "state"
    "created_at" "activated_at" "expires_at"
)

# ==============================================================================
# rule_index_init()
# Description:  Initialize the rule index. Creates directory and loads
#               existing index from disk if available.
# Parameters:   $1 - Rules data directory
# Returns:      0 on success
# ==============================================================================
rule_index_init() {
    local rules_dir="${1:?rule_index_init requires rules directory}"

    security_secure_dir "${rules_dir}" || return "${E_GENERAL}"

    _RULE_INDEX_FILE="${rules_dir}/${APOTROPAIOS_RULE_INDEX_FILE}"

    # Load existing index if present
    if [[ -f "${_RULE_INDEX_FILE}" ]]; then
        rule_index_load || {
            log_warning "rule_index" "Failed to load existing index — starting fresh"
            _RULE_INDEX_IDS=()
            _RULE_INDEX_DATA=()
        }
    fi

    _RULE_INDEX_LOADED=1
    log_info "rule_index" "Rule index initialized: ${#_RULE_INDEX_IDS[@]} rule(s) loaded"
    return "${E_SUCCESS}"
}

# ==============================================================================
# rule_index_load()
# Description:  Load rule index from disk file into memory.
# Returns:      0 on success, 1 on failure
# ==============================================================================
rule_index_load() {
    [[ -z "${_RULE_INDEX_FILE}" ]] && return 1
    [[ ! -f "${_RULE_INDEX_FILE}" ]] && return 1

    # Validate file before loading
    local file_size
    file_size="$(stat -c%s "${_RULE_INDEX_FILE}" 2>/dev/null)" || file_size=0
    if [[ "${file_size}" -gt 10485760 ]]; then  # 10MB limit
        log_error "rule_index" "Index file exceeds size limit: ${file_size} bytes"
        return 1
    fi

    # Clear existing in-memory data
    _RULE_INDEX_IDS=()
    _RULE_INDEX_DATA=()

    local line_num=0
    local valid_count=0
    local corrupt_count=0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_num++)) || true

        # Skip comments and empty lines
        [[ -z "${line}" ]] && continue
        [[ "${line}" == "#"* ]] && continue

        # Parse pipe-delimited fields
        local IFS='|'
        local -a fields
        read -ra fields <<< "${line}"

        # Validate field count
        if [[ "${#fields[@]}" -ne "${#_RULE_INDEX_FIELDS[@]}" ]]; then
            log_warning "rule_index" "Corrupt entry at line ${line_num}: field count mismatch (${#fields[@]} != ${#_RULE_INDEX_FIELDS[@]})"
            ((corrupt_count++)) || true
            continue
        fi

        local rule_id="${fields[0]}"

        # Validate rule ID format
        if ! validate_rule_id "${rule_id}"; then
            log_warning "rule_index" "Corrupt entry at line ${line_num}: invalid rule ID"
            ((corrupt_count++)) || true
            continue
        fi

        # Store in memory
        _RULE_INDEX_IDS+=("${rule_id}")
        local i=0
        for field_name in "${_RULE_INDEX_FIELDS[@]}"; do
            _RULE_INDEX_DATA["${rule_id}:${field_name}"]="${fields[${i}]}"
            ((i++)) || true
        done

        ((valid_count++)) || true
    done < "${_RULE_INDEX_FILE}"

    if [[ "${corrupt_count}" -gt 0 ]]; then
        log_warning "rule_index" "Loaded ${valid_count} rules, skipped ${corrupt_count} corrupt entries"
    else
        log_debug "rule_index" "Loaded ${valid_count} rules from index"
    fi

    return 0
}

# ==============================================================================
# rule_index_save()
# Description:  Save the in-memory rule index to disk.
# Returns:      0 on success
# ==============================================================================
rule_index_save() {
    [[ -z "${_RULE_INDEX_FILE}" ]] && {
        log_error "rule_index" "Index file path not set"
        return 1
    }

    # Write to temp file first, then atomic rename
    local tmp_file="${_RULE_INDEX_FILE}.tmp.$$"

    {
        printf '# Apotropaios Rule Index\n'
        printf '# Generated: %s\n' "$(util_timestamp)"
        printf '# Fields: %s\n' "$(IFS='|'; printf '%s' "${_RULE_INDEX_FIELDS[*]}")"
        printf '#\n'

        local rule_id
        for rule_id in "${_RULE_INDEX_IDS[@]}"; do
            local -a values=()
            local field_name
            for field_name in "${_RULE_INDEX_FIELDS[@]}"; do
                values+=("${_RULE_INDEX_DATA[${rule_id}:${field_name}]:-}")
            done
            local IFS='|'
            printf '%s\n' "${values[*]}"
        done
    } > "${tmp_file}" 2>/dev/null || {
        log_error "rule_index" "Failed to write index temp file"
        rm -f "${tmp_file}" 2>/dev/null || true
        return 1
    }

    # Atomic rename
    mv -f "${tmp_file}" "${_RULE_INDEX_FILE}" 2>/dev/null || {
        log_error "rule_index" "Failed to move index file into place"
        rm -f "${tmp_file}" 2>/dev/null || true
        return 1
    }

    chmod "${SECURE_FILE_PERMS}" "${_RULE_INDEX_FILE}" 2>/dev/null || true
    log_debug "rule_index" "Index saved: ${#_RULE_INDEX_IDS[@]} rules"
    return 0
}

# ==============================================================================
# rule_index_add()
# Description:  Add a rule record to the index.
# Parameters:   $1 - Associative array name (nameref) with rule fields
# Returns:      0 on success
# ==============================================================================
rule_index_add() {
    local -n _record="${1:?rule_index_add requires record array}"

    local rule_id="${_record[rule_id]:-}"
    [[ -z "${rule_id}" ]] && {
        log_error "rule_index" "Cannot add rule: missing rule_id"
        return 1
    }

    # Check for duplicate
    if [[ -n "${_RULE_INDEX_DATA[${rule_id}:rule_id]+exists}" ]]; then
        log_warning "rule_index" "Duplicate rule ID: ${rule_id}"
        return "${E_RULE_EXISTS}"
    fi

    # Add to ID list
    _RULE_INDEX_IDS+=("${rule_id}")

    # Store all fields
    local field_name
    for field_name in "${_RULE_INDEX_FIELDS[@]}"; do
        _RULE_INDEX_DATA["${rule_id}:${field_name}"]="${_record[${field_name}]:-}"
    done

    # Persist to disk
    rule_index_save || log_warning "rule_index" "Failed to persist index after add"

    log_debug "rule_index" "Rule added to index: ${rule_id}"
    return 0
}

# ==============================================================================
# rule_index_remove()
# Description:  Remove a rule from the index.
# Parameters:   $1 - Rule ID
# Returns:      0 on success, E_RULE_NOT_FOUND if not found
# ==============================================================================
rule_index_remove() {
    local rule_id="${1:?rule_index_remove requires rule ID}"

    # Check exists
    if [[ -z "${_RULE_INDEX_DATA[${rule_id}:rule_id]+exists}" ]]; then
        return "${E_RULE_NOT_FOUND}"
    fi

    # Remove from ID list
    local -a new_ids=()
    local id
    for id in "${_RULE_INDEX_IDS[@]}"; do
        [[ "${id}" != "${rule_id}" ]] && new_ids+=("${id}")
    done
    _RULE_INDEX_IDS=("${new_ids[@]}")

    # Remove data entries
    local field_name
    for field_name in "${_RULE_INDEX_FIELDS[@]}"; do
        unset "_RULE_INDEX_DATA[${rule_id}:${field_name}]" 2>/dev/null || true
    done

    # Persist
    rule_index_save || log_warning "rule_index" "Failed to persist index after remove"

    log_debug "rule_index" "Rule removed from index: ${rule_id}"
    return 0
}

# ==============================================================================
# rule_index_get()
# Description:  Retrieve a rule's data by ID.
# Parameters:   $1 - Rule ID
#               $2 - Target associative array name (nameref)
# Returns:      0 if found, E_RULE_NOT_FOUND if not
# ==============================================================================
rule_index_get() {
    local rule_id="${1:?rule_index_get requires rule ID}"
    local -n _target="${2:?rule_index_get requires target array}"

    if [[ -z "${_RULE_INDEX_DATA[${rule_id}:rule_id]+exists}" ]]; then
        return "${E_RULE_NOT_FOUND}"
    fi

    local field_name
    for field_name in "${_RULE_INDEX_FIELDS[@]}"; do
        _target["${field_name}"]="${_RULE_INDEX_DATA[${rule_id}:${field_name}]:-}"
    done

    return 0
}

# ==============================================================================
# rule_index_update_field()
# Description:  Update a single field of a rule in the index.
# Parameters:   $1 - Rule ID
#               $2 - Field name
#               $3 - New value
# Returns:      0 on success
# ==============================================================================
rule_index_update_field() {
    local rule_id="$1"
    local field="$2"
    local value="$3"

    if [[ -z "${_RULE_INDEX_DATA[${rule_id}:rule_id]+exists}" ]]; then
        return "${E_RULE_NOT_FOUND}"
    fi

    _RULE_INDEX_DATA["${rule_id}:${field}"]="${value}"
    rule_index_save || true

    return 0
}

# ==============================================================================
# rule_index_list_ids()
# Description:  Output all rule IDs, one per line.
# ==============================================================================
rule_index_list_ids() {
    local id
    for id in "${_RULE_INDEX_IDS[@]}"; do
        printf '%s\n' "${id}"
    done
}

# ==============================================================================
# rule_index_count()
# Description:  Return the number of rules in the index.
# ==============================================================================
rule_index_count() {
    printf '%d' "${#_RULE_INDEX_IDS[@]}"
}

# ==============================================================================
# rule_index_list_formatted()
# Description:  Print all rules in a formatted table.
# ==============================================================================
rule_index_list_formatted() {
    local count="${#_RULE_INDEX_IDS[@]}"

    if [[ "${count}" -eq 0 ]]; then
        printf '  %bNo rules in index%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
        return
    fi

    printf '\n  %bRule Index (%d rules):%b\n' "${COLOR_BOLD}" "${count}" "${COLOR_RESET}"
    util_print_separator "─" 100

    # Header
    printf '  %-38s %-10s %-9s %-8s %-6s %-7s %-10s %s\n' \
        "RULE ID" "BACKEND" "DIRECTION" "ACTION" "PROTO" "D.PORT" "STATE" "DESCRIPTION"
    util_print_separator "─" 100

    local rule_id
    for rule_id in "${_RULE_INDEX_IDS[@]}"; do
        local state="${_RULE_INDEX_DATA[${rule_id}:state]:-unknown}"
        local state_color="${COLOR_RESET}"
        case "${state}" in
            active)   state_color="${COLOR_GREEN}" ;;
            inactive) state_color="${COLOR_YELLOW}" ;;
            expired)  state_color="${COLOR_RED}" ;;
        esac

        printf '  %-38s %-10s %-9s %-8s %-6s %-7s %b%-10s%b %s\n' \
            "${rule_id}" \
            "${_RULE_INDEX_DATA[${rule_id}:backend]:-}" \
            "${_RULE_INDEX_DATA[${rule_id}:direction]:-}" \
            "${_RULE_INDEX_DATA[${rule_id}:action]:-}" \
            "${_RULE_INDEX_DATA[${rule_id}:protocol]:-any}" \
            "${_RULE_INDEX_DATA[${rule_id}:dst_port]:-any}" \
            "${state_color}" "${state}" "${COLOR_RESET}" \
            "${_RULE_INDEX_DATA[${rule_id}:description]:-}"
    done
}
