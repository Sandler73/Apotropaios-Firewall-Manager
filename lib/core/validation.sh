#!/usr/bin/env bash
# ==============================================================================
# File:         lib/core/validation.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Input validation and sanitization framework
# Description:  Provides whitelist-based input validation for all user-supplied
#               data including IP addresses, ports, protocols, hostnames, file
#               paths, chain/table names, and rule parameters. Implements
#               defense-in-depth per OWASP CRG and CWE-20 guidelines.
#               All validation uses whitelist (positive) matching — everything
#               not explicitly permitted is rejected.
# Notes:        - Requires lib/core/constants.sh and lib/core/logging.sh
#               - Validation functions return 0 (valid) or 1 (invalid)
#               - Error messages written to log, NOT to stdout (Bash Lesson #16)
#               - Validate at every trust boundary before any use of input
#               - Never interpolate raw input into commands or paths
# Version:      1.1.5
# ==============================================================================

# Prevent double-sourcing
[[ -n "${_APOTROPAIOS_VALIDATION_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_VALIDATION_LOADED=1

# ==============================================================================
# _contains_shell_meta() [INTERNAL]
# Description:  Check if a string contains shell metacharacters using portable
#               glob patterns instead of regex character classes, which have
#               version-dependent behavior across bash versions.
# Parameters:   $1 - String to check
# Returns:      0 if metacharacters found (DANGEROUS), 1 if clean
# ==============================================================================
_contains_shell_meta() {
    local s="${1:-}"
    [[ "${s}" == *";"* ]] && return 0
    [[ "${s}" == *"|"* ]] && return 0
    [[ "${s}" == *"&"* ]] && return 0
    [[ "${s}" == *'`'* ]] && return 0
    [[ "${s}" == *'$'* ]] && return 0
    [[ "${s}" == *"("* ]] && return 0
    [[ "${s}" == *")"* ]] && return 0
    [[ "${s}" == *"{"* ]] && return 0
    [[ "${s}" == *"}"* ]] && return 0
    [[ "${s}" == *"\\"* ]] && return 0
    [[ "${s}" == *"<"* ]] && return 0
    [[ "${s}" == *">"* ]] && return 0
    [[ "${s}" == *"!"* ]] && return 0
    [[ "${s}" == *"#"* ]] && return 0
    return 1
}

# ==============================================================================
# validate_port()
# Description:  Validate a TCP/UDP port number (1-65535).
# Parameters:   $1 - Port number string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_port() {
    local port="${1:-}"

    # Reject empty input
    [[ -z "${port}" ]] && {
        log_debug "validation" "Port validation failed: empty input"
        return 1
    }

    # Length check (max 5 digits)
    [[ "${#port}" -gt 5 ]] && {
        log_debug "validation" "Port validation failed: exceeds max length"
        return 1
    }

    # Must be numeric only
    [[ ! "${port}" =~ ${PATTERN_PORT} ]] && {
        log_debug "validation" "Port validation failed: non-numeric characters"
        return 1
    }

    # Range check: 1-65535
    if [[ "${port}" -lt 1 ]] || [[ "${port}" -gt 65535 ]]; then
        log_debug "validation" "Port validation failed: out of range (${port})"
        return 1
    fi

    return 0
}

# ==============================================================================
# validate_port_range()
# Description:  Validate a port range (e.g., 8080-8090 or 8080:8090).
# Parameters:   $1 - Port range string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_port_range() {
    local range="${1:-}"

    [[ -z "${range}" ]] && return 1

    # Check format
    [[ ! "${range}" =~ ${PATTERN_PORT_RANGE} ]] && {
        log_debug "validation" "Port range validation failed: invalid format"
        return 1
    }

    # Extract start and end ports (handle both - and : separators)
    local start_port end_port
    if [[ "${range}" == *"-"* ]]; then
        start_port="${range%%-*}"
        end_port="${range##*-}"
    else
        start_port="${range%%:*}"
        end_port="${range##*:}"
    fi

    # Validate each port individually
    validate_port "${start_port}" || return 1
    validate_port "${end_port}" || return 1

    # Start must be less than or equal to end
    if [[ "${start_port}" -gt "${end_port}" ]]; then
        log_debug "validation" "Port range validation failed: start > end (${start_port} > ${end_port})"
        return 1
    fi

    return 0
}

# ==============================================================================
# validate_ipv4()
# Description:  Validate an IPv4 address. Checks format and octet ranges.
# Parameters:   $1 - IPv4 address string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_ipv4() {
    local ip="${1:-}"

    [[ -z "${ip}" ]] && return 1

    # Length check
    [[ "${#ip}" -gt 15 ]] && return 1

    # Pattern check
    [[ ! "${ip}" =~ ${PATTERN_IPV4} ]] && {
        log_debug "validation" "IPv4 validation failed: pattern mismatch"
        return 1
    }

    # Validate each octet (0-255)
    local IFS='.'
    local -a octets
    read -ra octets <<< "${ip}"
    [[ "${#octets[@]}" -ne 4 ]] && return 1

    local octet
    for octet in "${octets[@]}"; do
        # Reject leading zeros (except "0" itself)
        if [[ "${#octet}" -gt 1 ]] && [[ "${octet}" == 0* ]]; then
            log_debug "validation" "IPv4 validation failed: leading zeros in octet"
            return 1
        fi
        if [[ "${octet}" -gt 255 ]]; then
            log_debug "validation" "IPv4 validation failed: octet out of range (${octet})"
            return 1
        fi
    done

    return 0
}

# ==============================================================================
# validate_ipv6()
# Description:  Validate an IPv6 address (simplified validation).
# Parameters:   $1 - IPv6 address string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_ipv6() {
    local ip="${1:-}"

    [[ -z "${ip}" ]] && return 1

    # Length check (max IPv6 representation is 39 chars)
    [[ "${#ip}" -gt 39 ]] && return 1

    # Pattern check
    [[ ! "${ip}" =~ ${PATTERN_IPV6} ]] && {
        log_debug "validation" "IPv6 validation failed: pattern mismatch"
        return 1
    }

    return 0
}

# ==============================================================================
# validate_ip()
# Description:  Validate an IP address (auto-detect IPv4 or IPv6).
# Parameters:   $1 - IP address string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_ip() {
    local ip="${1:-}"
    [[ -z "${ip}" ]] && return 1

    # Try IPv4 first
    if validate_ipv4 "${ip}"; then
        return 0
    fi

    # Then IPv6
    if validate_ipv6 "${ip}"; then
        return 0
    fi

    log_debug "validation" "IP validation failed: neither valid IPv4 nor IPv6"
    return 1
}

# ==============================================================================
# validate_cidr()
# Description:  Validate CIDR notation (IP/prefix).
# Parameters:   $1 - CIDR string (e.g., 192.168.1.0/24 or fd00::/64)
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_cidr() {
    local cidr="${1:-}"
    [[ -z "${cidr}" ]] && return 1

    # Check if it contains a slash
    [[ "${cidr}" != *"/"* ]] && {
        log_debug "validation" "CIDR validation failed: no prefix"
        return 1
    }

    local ip="${cidr%%/*}"
    local prefix="${cidr##*/}"

    # Validate the prefix is numeric
    [[ ! "${prefix}" =~ ${PATTERN_NUMERIC} ]] && return 1

    # Determine IP version and validate accordingly
    if validate_ipv4 "${ip}"; then
        # IPv4 prefix: 0-32
        [[ "${prefix}" -gt 32 ]] && {
            log_debug "validation" "CIDR validation failed: IPv4 prefix out of range (${prefix})"
            return 1
        }
    elif validate_ipv6 "${ip}"; then
        # IPv6 prefix: 0-128
        [[ "${prefix}" -gt 128 ]] && {
            log_debug "validation" "CIDR validation failed: IPv6 prefix out of range (${prefix})"
            return 1
        }
    else
        log_debug "validation" "CIDR validation failed: invalid IP portion"
        return 1
    fi

    return 0
}

# ==============================================================================
# validate_protocol()
# Description:  Validate and normalize a network protocol name.
# Parameters:   $1 - Protocol name
# Returns:      0 if valid, 1 if invalid. Normalized value on stdout.
# ==============================================================================
validate_protocol() {
    local proto="${1:-}"
    [[ -z "${proto}" ]] && return 1

    # Normalize to lowercase
    proto="$(printf '%s' "${proto}" | tr '[:upper:]' '[:lower:]')"

    # Whitelist check
    [[ ! "${proto}" =~ ${PATTERN_PROTOCOL} ]] && {
        log_debug "validation" "Protocol validation failed: ${proto}"
        return 1
    }

    printf '%s' "${proto}"
    return 0
}

# ==============================================================================
# validate_hostname()
# Description:  Validate a hostname per RFC 1123. Rejects shell metacharacters.
# Parameters:   $1 - Hostname string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_hostname() {
    local hostname="${1:-}"
    [[ -z "${hostname}" ]] && return 1

    # Length check (max 253 chars per RFC)
    [[ "${#hostname}" -gt 253 ]] && return 1

    # Reject shell metacharacters (security — Bash Lesson #12)
    if _contains_shell_meta "${hostname}"; then
        log_warning "validation" "Hostname validation failed: contains shell metacharacters"
        return 1
    fi

    # Pattern check (RFC 1123)
    [[ ! "${hostname}" =~ ${PATTERN_HOSTNAME} ]] && {
        log_debug "validation" "Hostname validation failed: RFC 1123 pattern mismatch"
        return 1
    }

    return 0
}

# ==============================================================================
# validate_interface()
# Description:  Validate a network interface name.
# Parameters:   $1 - Interface name
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_interface() {
    local iface="${1:-}"
    [[ -z "${iface}" ]] && return 1
    [[ "${#iface}" -gt 15 ]] && return 1

    [[ ! "${iface}" =~ ${PATTERN_INTERFACE} ]] && {
        log_debug "validation" "Interface validation failed: pattern mismatch"
        return 1
    }

    return 0
}

# ==============================================================================
# validate_file_path()
# Description:  Validate a file path for safety. Rejects traversal sequences,
#               shell metacharacters, and null bytes.
# Parameters:   $1 - File path string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_file_path() {
    local path="${1:-}"
    [[ -z "${path}" ]] && return 1

    # Length check
    [[ "${#path}" -gt "${MAX_PATH_LENGTH}" ]] && {
        log_debug "validation" "Path validation failed: exceeds max length"
        return 1
    }

    # Reject path traversal (../)
    if [[ "${path}" == *".."* ]]; then
        log_warning "validation" "Path validation failed: directory traversal detected"
        return 1
    fi

    # Reject shell metacharacters (CWE-78: OS Command Injection)
    if _contains_shell_meta "${path}"; then
        log_warning "validation" "Path validation failed: shell metacharacters detected"
        return 1
    fi

    # Reject null bytes
    if [[ "${path}" == *$'\0'* ]]; then
        log_warning "validation" "Path validation failed: null byte detected"
        return 1
    fi

    # Must match safe path pattern
    [[ ! "${path}" =~ ${PATTERN_SAFE_PATH} ]] && {
        log_debug "validation" "Path validation failed: unsafe characters"
        return 1
    }

    return 0
}

# ==============================================================================
# validate_zone()
# Description:  Validate a firewalld zone name.
# Parameters:   $1 - Zone name
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_zone() {
    local zone="${1:-}"
    [[ -z "${zone}" ]] && return 1
    [[ "${#zone}" -gt 32 ]] && return 1

    [[ ! "${zone}" =~ ${PATTERN_ZONE} ]] && {
        log_debug "validation" "Zone validation failed: pattern mismatch"
        return 1
    }
    return 0
}

# ==============================================================================
# validate_chain()
# Description:  Validate an iptables/nftables chain name.
# Parameters:   $1 - Chain name
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_chain() {
    local chain="${1:-}"
    [[ -z "${chain}" ]] && return 1
    [[ "${#chain}" -gt 64 ]] && return 1

    [[ ! "${chain}" =~ ${PATTERN_CHAIN} ]] && {
        log_debug "validation" "Chain validation failed: pattern mismatch"
        return 1
    }
    return 0
}

# ==============================================================================
# validate_table()
# Description:  Validate an iptables/nftables table name.
# Parameters:   $1 - Table name
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_table() {
    local table="${1:-}"
    [[ -z "${table}" ]] && return 1
    [[ "${#table}" -gt 32 ]] && return 1

    [[ ! "${table}" =~ ${PATTERN_TABLE} ]] && {
        log_debug "validation" "Table validation failed: pattern mismatch"
        return 1
    }
    return 0
}

# ==============================================================================
# validate_table_family()
# Description:  Validate an nftables table family.
# Parameters:   $1 - Table family string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_table_family() {
    local family="${1:-}"
    [[ -z "${family}" ]] && return 1

    family="$(printf '%s' "${family}" | tr '[:upper:]' '[:lower:]')"

    case "${family}" in
        inet|ip|ip6|arp|bridge|netdev) return 0 ;;
    esac

    log_debug "validation" "Table family validation failed: ${family}"
    return 1
}

# ==============================================================================
# validate_ipset_name()
# Description:  Validate an ipset name.
# Parameters:   $1 - IPSet name
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_ipset_name() {
    local name="${1:-}"
    [[ -z "${name}" ]] && return 1
    [[ "${#name}" -gt 31 ]] && return 1

    [[ ! "${name}" =~ ${PATTERN_IPSET_NAME} ]] && {
        log_debug "validation" "IPSet name validation failed: pattern mismatch"
        return 1
    }
    return 0
}

# ==============================================================================
# validate_rule_id()
# Description:  Validate a rule UUID.
# Parameters:   $1 - Rule ID string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_rule_id() {
    local rule_id="${1:-}"
    [[ -z "${rule_id}" ]] && return 1
    [[ "${#rule_id}" -ne 36 ]] && return 1

    [[ ! "${rule_id}" =~ ${PATTERN_RULE_ID} ]] && {
        log_debug "validation" "Rule ID validation failed: UUID pattern mismatch"
        return 1
    }
    return 0
}

# ==============================================================================
# validate_rule_action()
# Description:  Validate a firewall rule action against the allowed list.
#               Supports compound actions (comma-separated) like "log,drop".
#               Compound actions must contain at most one terminal action
#               and may include non-terminal actions (e.g., log).
# Parameters:   $1 - Action string (single or comma-separated)
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_rule_action() {
    local action="${1:-}"
    [[ -z "${action}" ]] && return 1

    # Normalize to lowercase and remove spaces
    action="$(printf '%s' "${action}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"

    # Split on comma for compound actions
    local IFS=','
    local -a parts
    read -ra parts <<< "${action}"

    local terminal_count=0
    local part valid_action found

    for part in "${parts[@]}"; do
        [[ -z "${part}" ]] && return 1

        # Validate each part is a known action
        found=0
        for valid_action in "${RULE_ACTIONS[@]}"; do
            if [[ "${part}" == "${valid_action}" ]]; then
                found=1
                break
            fi
        done
        [[ "${found}" -eq 0 ]] && {
            log_debug "validation" "Unknown action component: ${part}"
            return 1
        }

        # Count terminal actions — at most one allowed
        for valid_action in "${RULE_TERMINAL_ACTIONS[@]}"; do
            if [[ "${part}" == "${valid_action}" ]]; then
                ((terminal_count++)) || true
                break
            fi
        done
    done

    # Compound rules: must have exactly 1 terminal action (or 0 if all non-terminal)
    if [[ "${terminal_count}" -gt 1 ]]; then
        log_debug "validation" "Compound action has ${terminal_count} terminal actions (max 1)"
        return 1
    fi

    return 0
}

# ==============================================================================
# validate_conn_state()
# Description:  Validate connection tracking state(s).
#               Accepts comma-separated states: new,established,related,invalid,untracked
# Parameters:   $1 - State string (single or comma-separated)
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_conn_state() {
    local state_input="${1:-}"
    [[ -z "${state_input}" ]] && return 1

    state_input="$(printf '%s' "${state_input}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"

    local IFS=','
    local -a parts
    read -ra parts <<< "${state_input}"

    local part valid_state found

    for part in "${parts[@]}"; do
        [[ -z "${part}" ]] && return 1
        found=0
        for valid_state in "${RULE_CONN_STATES[@]}"; do
            if [[ "${part}" == "${valid_state}" ]]; then
                found=1
                break
            fi
        done
        [[ "${found}" -eq 0 ]] && {
            log_debug "validation" "Invalid connection state: ${part}"
            return 1
        }
    done

    return 0
}

# ==============================================================================
# validate_log_prefix()
# Description:  Validate a log prefix string. Must be 1-29 chars, alphanumeric
#               plus basic punctuation (no shell metacharacters).
# Parameters:   $1 - Log prefix string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_log_prefix() {
    local prefix="${1:-}"
    [[ -z "${prefix}" ]] && return 1
    [[ "${#prefix}" -gt 29 ]] && return 1
    # Alphanumeric, spaces, hyphens, underscores, colons, dots only
    [[ "${prefix}" =~ ^[a-zA-Z0-9\ _.:/-]+$ ]] || return 1
    return 0
}

# ==============================================================================
# validate_rate_limit()
# Description:  Validate a rate limit string (e.g., "5/minute", "10/second").
# Parameters:   $1 - Rate limit string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_rate_limit() {
    local limit="${1:-}"
    [[ -z "${limit}" ]] && return 1
    [[ "${limit}" =~ ^[0-9]+/(second|minute|hour|day)$ ]] || return 1
    return 0
}

# ==============================================================================
# validate_rule_direction()
# Description:  Validate a firewall rule direction.
# Parameters:   $1 - Direction string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_rule_direction() {
    local direction="${1:-}"
    [[ -z "${direction}" ]] && return 1

    direction="$(printf '%s' "${direction}" | tr '[:upper:]' '[:lower:]')"

    local valid_dir
    for valid_dir in "${RULE_DIRECTIONS[@]}"; do
        [[ "${direction}" == "${valid_dir}" ]] && return 0
    done

    log_debug "validation" "Rule direction validation failed: ${direction}"
    return 1
}

# ==============================================================================
# validate_duration_type()
# Description:  Validate a rule duration type (permanent/temporary).
# Parameters:   $1 - Duration type string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_duration_type() {
    local dtype="${1:-}"
    [[ -z "${dtype}" ]] && return 1

    dtype="$(printf '%s' "${dtype}" | tr '[:upper:]' '[:lower:]')"

    local valid_type
    for valid_type in "${RULE_DURATION_TYPES[@]}"; do
        [[ "${dtype}" == "${valid_type}" ]] && return 0
    done

    log_debug "validation" "Duration type validation failed: ${dtype}"
    return 1
}

# ==============================================================================
# validate_ttl()
# Description:  Validate a temporary rule TTL (time-to-live) in seconds.
# Parameters:   $1 - TTL in seconds
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_ttl() {
    local ttl="${1:-}"
    [[ -z "${ttl}" ]] && return 1

    # Must be numeric
    [[ ! "${ttl}" =~ ${PATTERN_NUMERIC} ]] && return 1

    # Range check
    if [[ "${ttl}" -lt "${RULE_MIN_TTL_SECONDS}" ]] || [[ "${ttl}" -gt "${RULE_MAX_TTL_SECONDS}" ]]; then
        log_debug "validation" "TTL validation failed: out of range (${ttl}s, min=${RULE_MIN_TTL_SECONDS}, max=${RULE_MAX_TTL_SECONDS})"
        return 1
    fi

    return 0
}

# ==============================================================================
# validate_log_level()
# Description:  Validate a log level name or number.
# Parameters:   $1 - Log level string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_log_level() {
    local level="${1:-}"
    [[ -z "${level}" ]] && return 1

    # Check if it's a known level name
    if [[ -n "${LOG_LEVEL_NUMBERS[${level}]+exists}" ]]; then
        return 0
    fi

    # Check if it's a valid numeric level
    if [[ "${level}" =~ ${PATTERN_NUMERIC} ]]; then
        [[ -n "${LOG_LEVEL_NAMES[${level}]+exists}" ]] && return 0
    fi

    log_debug "validation" "Log level validation failed: ${level}"
    return 1
}

# ==============================================================================
# sanitize_input()
# Description:  Sanitize a general input string using a WHITELIST approach.
#               Keeps only known-safe characters — everything else is stripped.
#               Defense-in-depth measure applied after validation.
# Parameters:   $1 - Raw input string
# Returns:      Sanitized string via stdout
# ==============================================================================
sanitize_input() {
    local input="${1:-}"

    # Enforce maximum length
    if [[ "${#input}" -gt "${MAX_INPUT_LENGTH}" ]]; then
        input="${input:0:${MAX_INPUT_LENGTH}}"
    fi

    # Remove null bytes
    input="$(printf '%s' "${input}" | tr -d '\0')"

    # WHITELIST: keep only safe characters
    # Allowed: alphanumeric, space, dot, comma, underscore, colon, slash,
    #          plus, equals, at sign, tilde, percent, hyphen (last to avoid range)
    # This covers: IPs, CIDRs, ports, paths, descriptions, rule actions,
    #              connection states, rate limits, email-style identifiers
    # NOTE: Hyphen MUST be last in the tr class to be treated as literal,
    #       not as a range operator (BUG-010: caused total menu failure)
    input="$(printf '%s' "${input}" | tr -cd 'a-zA-Z0-9 .,_:/+=@~%-')"

    # Remove control characters (keep printable ASCII + common whitespace)
    input="$(printf '%s' "${input}" | tr -cd '[:print:][:space:]')"

    # Trim leading/trailing whitespace
    input="$(printf '%s' "${input}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    printf '%s' "${input}"
}

# ==============================================================================
# validate_numeric()
# Description:  Validate that input is a positive integer.
# Parameters:   $1 - Input string
#               $2 - Minimum value (optional)
#               $3 - Maximum value (optional)
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_numeric() {
    local input="${1:-}"
    local min="${2:-}"
    local max="${3:-}"

    [[ -z "${input}" ]] && return 1
    [[ ! "${input}" =~ ${PATTERN_NUMERIC} ]] && return 1

    if [[ -n "${min}" ]] && [[ "${input}" -lt "${min}" ]]; then
        log_debug "validation" "Numeric validation failed: ${input} < ${min}"
        return 1
    fi

    if [[ -n "${max}" ]] && [[ "${input}" -gt "${max}" ]]; then
        log_debug "validation" "Numeric validation failed: ${input} > ${max}"
        return 1
    fi

    return 0
}

# ==============================================================================
# validate_description()
# Description:  Validate a rule description string.
# Parameters:   $1 - Description string
# Returns:      0 if valid, 1 if invalid
# ==============================================================================
validate_description() {
    local desc="${1:-}"

    # Allow empty descriptions
    [[ -z "${desc}" ]] && return 0

    # Length check
    if [[ "${#desc}" -gt "${MAX_RULE_DESCRIPTION_LENGTH}" ]]; then
        log_debug "validation" "Description validation failed: exceeds max length (${#desc} > ${MAX_RULE_DESCRIPTION_LENGTH})"
        return 1
    fi

    # Reject shell metacharacters
    if _contains_shell_meta "${desc}"; then
        log_warning "validation" "Description validation failed: shell metacharacters detected"
        return 1
    fi

    return 0
}
