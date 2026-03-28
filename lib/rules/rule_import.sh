#!/usr/bin/env bash
# ==============================================================================
# File:         lib/rules/rule_import.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Rule configuration file import and export
# Description:  Provides functionality to import firewall rules from prebuilt
#               configuration files and export current rules to portable format.
#               Supports Apotropaios native format and validates all imported
#               data before application.
# Notes:        - Imported files are validated line-by-line before any application
#               - Supports dry-run mode for validation without application
#               - Export generates complete rule specifications
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_RULE_IMPORT_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_RULE_IMPORT_LOADED=1

# ==============================================================================
# rule_import_file()
# Description:  Import and apply rules from a configuration file.
# Parameters:   $1 - Configuration file path
#               $2 - Dry run (1=validate only, 0=apply; default: 0)
# Returns:      0 on success, E_RULE_IMPORT_FAIL on failure
# ==============================================================================
rule_import_file() {
    local config_file="${1:?rule_import_file requires file path}"
    local dry_run="${2:-0}"

    # Validate file path
    validate_file_path "${config_file}" || {
        log_error "rule_import" "Invalid file path: ${config_file}"
        return "${E_RULE_IMPORT_FAIL}"
    }

    [[ ! -f "${config_file}" ]] && {
        log_error "rule_import" "Configuration file not found: ${config_file}"
        return "${E_RULE_IMPORT_FAIL}"
    }

    [[ ! -r "${config_file}" ]] && {
        log_error "rule_import" "Configuration file not readable: ${config_file}"
        return "${E_RULE_IMPORT_FAIL}"
    }

    # Validate file size
    local file_size
    file_size="$(stat -c%s "${config_file}" 2>/dev/null)" || file_size=0
    if [[ "${file_size}" -gt 10485760 ]]; then
        log_error "rule_import" "Configuration file too large: ${file_size} bytes (max 10MB)"
        return "${E_RULE_IMPORT_FAIL}"
    fi

    # Verify file integrity if checksum is available
    local checksum_file="${config_file}.sha256"
    if [[ -f "${checksum_file}" ]]; then
        local expected_checksum
        expected_checksum="$(cat "${checksum_file}" 2>/dev/null | awk '{print $1}')" || true
        if [[ -n "${expected_checksum}" ]]; then
            security_verify_checksum "${config_file}" "${expected_checksum}" || {
                log_error "rule_import" "Configuration file integrity check failed"
                return "${E_RULE_IMPORT_FAIL}"
            }
        fi
    fi

    log_info "rule_import" "Importing rules from: ${config_file} (dry_run=${dry_run})"

    local line_num=0
    local success_count=0
    local error_count=0
    local skip_count=0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_num++)) || true

        # Skip comments and empty lines
        [[ -z "${line}" ]] && continue
        [[ "${line}" == "#"* ]] && continue
        [[ "${line}" == "//"* ]] && continue

        # Parse rule line
        local -A rule_params=()
        if ! _rule_import_parse_line "${line}" "rule_params"; then
            log_warning "rule_import" "Skipping invalid entry at line ${line_num}"
            ((error_count++)) || true
            continue
        fi

        # Validate parsed parameters
        if ! _rule_import_validate "rule_params"; then
            log_warning "rule_import" "Validation failed for line ${line_num}"
            ((error_count++)) || true
            continue
        fi

        if [[ "${dry_run}" -eq 1 ]]; then
            log_debug "rule_import" "Dry run: line ${line_num} validated OK"
            ((success_count++)) || true
            continue
        fi

        # Apply the rule
        if rule_create "rule_params"; then
            ((success_count++)) || true
            log_debug "rule_import" "Rule applied from line ${line_num}: ${RULE_CREATE_ID}"
        else
            ((error_count++)) || true
            log_warning "rule_import" "Failed to apply rule from line ${line_num}"
        fi

    done < "${config_file}"

    log_info "rule_import" "Import complete: ${success_count} applied, ${error_count} errors, ${skip_count} skipped" \
        "file=${config_file} total_lines=${line_num}"

    [[ "${error_count}" -gt 0 ]] && return "${E_RULE_IMPORT_FAIL}"
    return "${E_SUCCESS}"
}

# ==============================================================================
# _rule_import_parse_line() [INTERNAL]
# Description:  Parse a single rule configuration line.
#               Format: key=value pairs separated by spaces or pipe-delimited.
# Parameters:   $1 - Line string
#               $2 - Target associative array name (nameref)
# Returns:      0 if parsed, 1 if invalid format
# ==============================================================================
_rule_import_parse_line() {
    local line="$1"
    local -n _target="$2"

    # Detect format: pipe-delimited (index export) vs key=value
    if [[ "${line}" == *"|"* ]] && [[ "${line}" != *"="* ]]; then
        # Pipe-delimited format (from rule_index export)
        local IFS='|'
        local -a fields
        read -ra fields <<< "${line}"

        if [[ "${#fields[@]}" -ge 11 ]]; then
            _target[direction]="${fields[2]:-}"
            _target[action]="${fields[3]:-}"
            _target[protocol]="${fields[4]:-}"
            _target[src_ip]="${fields[5]:-}"
            _target[dst_ip]="${fields[6]:-}"
            _target[src_port]="${fields[7]:-}"
            _target[dst_port]="${fields[8]:-}"
            _target[interface]="${fields[9]:-}"
            _target[duration_type]="${fields[14]:-permanent}"
            _target[ttl]="${fields[15]:-0}"
            _target[description]="${fields[16]:-imported}"
            # Backend from field 1 if present
            [[ -n "${fields[1]:-}" ]] && _target[backend]="${fields[1]}"
            return 0
        fi
        return 1
    fi

    # Key=value format
    local pair key value
    for pair in ${line}; do
        # Handle key=value
        if [[ "${pair}" == *"="* ]]; then
            key="${pair%%=*}"
            value="${pair#*=}"
            # Remove quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            # Sanitize
            key="$(sanitize_input "${key}")"
            value="$(sanitize_input "${value}")"
            _target["${key}"]="${value}"
        fi
    done

    # Must have at least direction or action
    [[ -z "${_target[direction]:-}" ]] && [[ -z "${_target[action]:-}" ]] && return 1

    return 0
}

# ==============================================================================
# _rule_import_validate() [INTERNAL]
# Description:  Validate parsed rule parameters.
# ==============================================================================
_rule_import_validate() {
    local -n _params="$1"

    # Set defaults for missing fields
    [[ -z "${_params[direction]:-}" ]] && _params[direction]="inbound"
    [[ -z "${_params[action]:-}" ]] && _params[action]="accept"
    [[ -z "${_params[duration_type]:-}" ]] && _params[duration_type]="permanent"
    [[ -z "${_params[ttl]:-}" ]] && _params[ttl]="0"

    # Clean "any" placeholders
    [[ "${_params[protocol]:-}" == "any" ]] && _params[protocol]=""
    [[ "${_params[src_ip]:-}" == "any" ]] && _params[src_ip]=""
    [[ "${_params[dst_ip]:-}" == "any" ]] && _params[dst_ip]=""
    [[ "${_params[src_port]:-}" == "any" ]] && _params[src_port]=""
    [[ "${_params[dst_port]:-}" == "any" ]] && _params[dst_port]=""

    # Validate non-empty fields
    [[ -n "${_params[protocol]:-}" ]] && {
        validate_protocol "${_params[protocol]}" >/dev/null || return 1
    }
    [[ -n "${_params[src_ip]:-}" ]] && {
        validate_ip "${_params[src_ip]}" || validate_cidr "${_params[src_ip]}" || return 1
    }
    [[ -n "${_params[dst_ip]:-}" ]] && {
        validate_ip "${_params[dst_ip]}" || validate_cidr "${_params[dst_ip]}" || return 1
    }
    [[ -n "${_params[dst_port]:-}" ]] && {
        validate_port "${_params[dst_port]}" || validate_port_range "${_params[dst_port]}" || return 1
    }

    validate_rule_direction "${_params[direction]}" || return 1
    validate_rule_action "${_params[action]}" || return 1

    return 0
}

# ==============================================================================
# rule_export_file()
# Description:  Export all indexed rules to a configuration file.
# Parameters:   $1 - Output file path
# Returns:      0 on success
# ==============================================================================
rule_export_file() {
    local output_file="${1:?rule_export_file requires output path}"

    validate_file_path "${output_file}" || {
        log_error "rule_import" "Invalid output path: ${output_file}"
        return 1
    }

    local count
    count="$(rule_index_count)"

    {
        printf '# Apotropaios Firewall Rules Export\n'
        printf '# Generated: %s\n'  "$(util_timestamp)"
        printf '# Total rules: %d\n' "${count}"
        printf '# Format: direction=VALUE action=VALUE protocol=VALUE src_ip=VALUE dst_ip=VALUE src_port=VALUE dst_port=VALUE duration_type=VALUE ttl=VALUE description=VALUE\n'
        printf '#\n'

        local rule_id
        while IFS= read -r rule_id; do
            [[ -z "${rule_id}" ]] && continue

            local -A rd=()
            rule_index_get "${rule_id}" "rd" || continue

            printf 'direction=%s action=%s protocol=%s src_ip=%s dst_ip=%s src_port=%s dst_port=%s duration_type=%s ttl=%s description="%s"\n' \
                "${rd[direction]:-inbound}" \
                "${rd[action]:-accept}" \
                "${rd[protocol]:-any}" \
                "${rd[src_ip]:-any}" \
                "${rd[dst_ip]:-any}" \
                "${rd[src_port]:-any}" \
                "${rd[dst_port]:-any}" \
                "${rd[duration_type]:-permanent}" \
                "${rd[ttl]:-0}" \
                "${rd[description]:-}"
        done < <(rule_index_list_ids)
    } > "${output_file}" 2>/dev/null || {
        log_error "rule_import" "Failed to write export file"
        return 1
    }

    # Generate checksum
    local checksum
    checksum="$(security_file_checksum "${output_file}")" || true
    if [[ -n "${checksum}" ]]; then
        printf '%s  %s\n' "${checksum}" "$(basename "${output_file}")" > "${output_file}.sha256" 2>/dev/null || true
    fi

    chmod "${SECURE_FILE_PERMS}" "${output_file}" 2>/dev/null || true
    log_info "rule_import" "Exported ${count} rules to ${output_file}"
    return "${E_SUCCESS}"
}
