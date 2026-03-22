#!/usr/bin/env bash
# ==============================================================================
# File:         apotropaios.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Main entry point for the Apotropaios Firewall Manager framework
# Description:  Unified firewall management framework supporting firewalld,
#               ipset, iptables, nftables, and ufw across Ubuntu, Kali Linux,
#               Debian 12, Rocky Linux 9, AlmaLinux 9, and Arch Linux.
#               Provides both interactive menu-driven and CLI interfaces for
#               comprehensive firewall rule creation, management, backup,
#               restoration, and monitoring.
# Notes:        - Requires bash 4.0+
#               - Most operations require root privileges
#               - Source guard at bottom enables BATS test sourcing
#               - Zero external dependencies beyond core system utilities
# Execution:    sudo ./apotropaios.sh [OPTIONS] [COMMAND]
# Examples:     sudo ./apotropaios.sh                    # Interactive menu
#               sudo ./apotropaios.sh detect             # Detect OS and firewalls
#               sudo ./apotropaios.sh --backend iptables status
#               sudo ./apotropaios.sh --log-level debug menu
#               sudo ./apotropaios.sh block-all
#               sudo ./apotropaios.sh add-rule --direction inbound --protocol tcp --dst-port 443 --action accept
#               sudo ./apotropaios.sh import /path/to/rules.conf
#               sudo ./apotropaios.sh backup pre-deployment
# Version:      1.0.0
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Determine script location and base directory
# ==============================================================================
# shellcheck disable=SC2155
readonly APOTROPAIOS_SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APOTROPAIOS_BASE_DIR="${APOTROPAIOS_SCRIPT_PATH}"

# ==============================================================================
# Source core libraries (order matters — dependencies first)
# ==============================================================================
# shellcheck source=lib/core/constants.sh
source "${APOTROPAIOS_BASE_DIR}/lib/core/constants.sh"
# shellcheck source=lib/core/logging.sh
source "${APOTROPAIOS_BASE_DIR}/lib/core/logging.sh"
# shellcheck source=lib/core/errors.sh
source "${APOTROPAIOS_BASE_DIR}/lib/core/errors.sh"
# shellcheck source=lib/core/validation.sh
source "${APOTROPAIOS_BASE_DIR}/lib/core/validation.sh"
# shellcheck source=lib/core/security.sh
source "${APOTROPAIOS_BASE_DIR}/lib/core/security.sh"
# shellcheck source=lib/core/utils.sh
source "${APOTROPAIOS_BASE_DIR}/lib/core/utils.sh"

# Source detection modules
# shellcheck source=lib/detection/os_detect.sh
source "${APOTROPAIOS_BASE_DIR}/lib/detection/os_detect.sh"
# shellcheck source=lib/detection/fw_detect.sh
source "${APOTROPAIOS_BASE_DIR}/lib/detection/fw_detect.sh"

# Source firewall backends
# shellcheck source=lib/firewall/common.sh
source "${APOTROPAIOS_BASE_DIR}/lib/firewall/common.sh"
# shellcheck source=lib/firewall/iptables.sh
source "${APOTROPAIOS_BASE_DIR}/lib/firewall/iptables.sh"
# shellcheck source=lib/firewall/nftables.sh
source "${APOTROPAIOS_BASE_DIR}/lib/firewall/nftables.sh"
# shellcheck source=lib/firewall/firewalld.sh
source "${APOTROPAIOS_BASE_DIR}/lib/firewall/firewalld.sh"
# shellcheck source=lib/firewall/ufw.sh
source "${APOTROPAIOS_BASE_DIR}/lib/firewall/ufw.sh"
# shellcheck source=lib/firewall/ipset.sh
source "${APOTROPAIOS_BASE_DIR}/lib/firewall/ipset.sh"

# Source rule engine
# shellcheck source=lib/rules/rule_index.sh
source "${APOTROPAIOS_BASE_DIR}/lib/rules/rule_index.sh"
# shellcheck source=lib/rules/rule_state.sh
source "${APOTROPAIOS_BASE_DIR}/lib/rules/rule_state.sh"
# shellcheck source=lib/rules/rule_engine.sh
source "${APOTROPAIOS_BASE_DIR}/lib/rules/rule_engine.sh"
# shellcheck source=lib/rules/rule_import.sh
source "${APOTROPAIOS_BASE_DIR}/lib/rules/rule_import.sh"

# Source backup/restore
# shellcheck source=lib/backup/backup.sh
source "${APOTROPAIOS_BASE_DIR}/lib/backup/backup.sh"
# shellcheck source=lib/backup/restore.sh
source "${APOTROPAIOS_BASE_DIR}/lib/backup/restore.sh"
# shellcheck source=lib/backup/immutable.sh
source "${APOTROPAIOS_BASE_DIR}/lib/backup/immutable.sh"

# Source installer
# shellcheck source=lib/install/installer.sh
source "${APOTROPAIOS_BASE_DIR}/lib/install/installer.sh"

# Source menu system
# shellcheck source=lib/menu/menu_main.sh
source "${APOTROPAIOS_BASE_DIR}/lib/menu/menu_main.sh"

# ==============================================================================
# CLI Argument Parsing State
# ==============================================================================
_CLI_LOG_LEVEL=""
_CLI_BACKEND=""
_CLI_COMMAND=""
_CLI_NON_INTERACTIVE=0
declare -a _CLI_COMMAND_ARGS=()

# ==============================================================================
# _parse_args()
# Description:  Parse command-line arguments and options.
# Parameters:   $@ - All command-line arguments
# ==============================================================================
_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                _show_usage
                exit "${E_SUCCESS}"
                ;;
            --version|-v)
                printf '%s v%s\n' "${APOTROPAIOS_FULL_NAME}" "${APOTROPAIOS_VERSION}"
                exit "${E_SUCCESS}"
                ;;
            --log-level)
                shift
                _CLI_LOG_LEVEL="${1:-}"
                [[ -z "${_CLI_LOG_LEVEL}" ]] && {
                    printf 'Error: --log-level requires a value\n' >&2
                    exit "${E_USAGE}"
                }
                ;;
            --backend)
                shift
                _CLI_BACKEND="${1:-}"
                [[ -z "${_CLI_BACKEND}" ]] && {
                    printf 'Error: --backend requires a value\n' >&2
                    exit "${E_USAGE}"
                }
                ;;
            --non-interactive)
                _CLI_NON_INTERACTIVE=1
                ;;
            -*)
                printf 'Error: Unknown option: %s\n' "$1" >&2
                printf 'Run with --help for usage information\n' >&2
                exit "${E_USAGE}"
                ;;
            *)
                # First non-option is the command
                if [[ -z "${_CLI_COMMAND}" ]]; then
                    _CLI_COMMAND="$1"
                else
                    _CLI_COMMAND_ARGS+=("$1")
                fi
                ;;
        esac
        shift
    done
}

# ==============================================================================
# _show_usage()
# Description:  Display usage information.
# ==============================================================================
_show_usage() {
    util_print_banner
    printf 'Usage: %s [OPTIONS] [COMMAND] [ARGS...]\n\n' "$(basename "$0")"
    printf 'Options:\n'
    printf '  -h, --help              Show this help message\n'
    printf '  -v, --version           Show version\n'
    printf '  --log-level LEVEL       Set log level (trace|debug|info|warning|error|critical)\n'
    printf '  --backend NAME          Set firewall backend (firewalld|ipset|iptables|nftables|ufw)\n'
    printf '  --non-interactive       Disable interactive prompts\n\n'
    printf 'Commands:\n'
    printf '  menu                    Start interactive menu (default)\n'
    printf '  detect                  Detect OS and installed firewalls\n'
    printf '  status                  Show firewall status\n'
    printf '  block-all               Block all inbound and outbound traffic\n'
    printf '  allow-all               Allow all inbound and outbound traffic\n'
    printf '  list-rules              List all tracked rules\n'
    printf '  system-rules            List all native system firewall rules\n'
    printf '  add-rule [OPTS]         Add a firewall rule\n'
    printf '  remove-rule ID          Remove a rule by UUID\n'
    printf '  activate-rule ID        Re-activate a deactivated rule\n'
    printf '  deactivate-rule ID      Deactivate a rule without removing\n'
    printf '  import FILE             Import rules from configuration file\n'
    printf '  export FILE             Export rules to configuration file\n'
    printf '  backup [LABEL]          Create a configuration backup\n'
    printf '  restore FILE            Restore from backup file\n'
    printf '  install FW_NAME         Install a firewall package\n'
    printf '  update FW_NAME          Update a firewall package\n\n'
    printf 'Add-rule options:\n'
    printf '  --direction DIR         inbound|outbound|forward (default: inbound)\n'
    printf '  --protocol PROTO        tcp|udp|icmp|all (default: tcp)\n'
    printf '  --src-ip IP             Source IP or CIDR\n'
    printf '  --dst-ip IP             Destination IP or CIDR\n'
    printf '  --src-port PORT         Source port or range\n'
    printf '  --dst-port PORT         Destination port or range\n'
    printf '  --action ACTION         accept|drop|reject (default: accept)\n'
    printf '  --duration TYPE         permanent|temporary (default: permanent)\n'
    printf '  --ttl SECONDS           TTL for temporary rules\n'
    printf '  --description TEXT      Rule description\n\n'
    printf 'Examples:\n'
    printf '  sudo %s detect\n' "$(basename "$0")"
    printf '  sudo %s --backend iptables add-rule --dst-port 443 --action accept\n' "$(basename "$0")"
    printf '  sudo %s import /etc/apotropaios/rules.conf\n' "$(basename "$0")"
    printf '  sudo %s backup pre-deploy\n' "$(basename "$0")"
}

# ==============================================================================
# _initialize()
# Description:  Initialize all framework subsystems.
# ==============================================================================
_initialize() {
    # Initialize logging
    local log_dir="${APOTROPAIOS_BASE_DIR}/${APOTROPAIOS_LOGS_DIR_REL}"

    if [[ -n "${_CLI_LOG_LEVEL}" ]]; then
        if validate_log_level "${_CLI_LOG_LEVEL}"; then
            local level_num="${LOG_LEVEL_NUMBERS[${_CLI_LOG_LEVEL}]:-${DEFAULT_LOG_LEVEL}}"
            log_init "${log_dir}" "${level_num}" || {
                printf 'FATAL: Failed to initialize logging\n' >&2
                exit "${E_LOG_FAIL}"
            }
        else
            printf 'Error: Invalid log level: %s\n' "${_CLI_LOG_LEVEL}" >&2
            exit "${E_USAGE}"
        fi
    else
        log_init "${log_dir}" || {
            printf 'FATAL: Failed to initialize logging\n' >&2
            exit "${E_LOG_FAIL}"
        }
    fi

    # Initialize error handling
    error_init

    # Register logging shutdown as cleanup
    error_register_cleanup "log_shutdown"

    # Initialize security subsystem
    security_init "${APOTROPAIOS_BASE_DIR}" || {
        log_critical "main" "Failed to initialize security subsystem"
        exit "${E_GENERAL}"
    }

    # Detect operating system
    os_detect || {
        log_warning "main" "OS detection returned unsupported — proceeding with limited functionality"
    }

    # Detect installed firewalls
    fw_detect_all

    # Initialize rule subsystems
    local rules_dir="${APOTROPAIOS_BASE_DIR}/${APOTROPAIOS_RULES_DIR_REL}"
    rule_index_init "${rules_dir}" || log_warning "main" "Rule index initialization failed"
    rule_state_init "${rules_dir}" || log_warning "main" "Rule state initialization failed"

    # Initialize backup subsystem
    local backup_dir="${APOTROPAIOS_BASE_DIR}/${APOTROPAIOS_BACKUPS_DIR_REL}"
    backup_init "${backup_dir}" || log_warning "main" "Backup initialization failed"

    # Auto-select backend if specified via CLI
    if [[ -n "${_CLI_BACKEND}" ]]; then
        fw_set_backend "${_CLI_BACKEND}" || {
            log_error "main" "Cannot set backend: ${_CLI_BACKEND}"
            exit "${E_FW_NOT_FOUND}"
        }
    else
        # Auto-select first available firewall
        local installed
        installed="$(fw_get_installed)"
        if [[ -n "${installed}" ]]; then
            local first_fw="${installed%% *}"
            fw_set_backend "${first_fw}" || true
        fi
    fi

    # Check for expired temporary rules
    rule_check_expired || true

    log_info "main" "Apotropaios v${APOTROPAIOS_VERSION} initialized" \
        "os=${OS_DETECTED_ID} backend=${FW_ACTIVE_BACKEND:-none} rules=$(rule_index_count 2>/dev/null || echo 0)"
}

# ==============================================================================
# _execute_command()
# Description:  Execute the CLI command.
# ==============================================================================
_execute_command() {
    case "${_CLI_COMMAND}" in
        ""|menu)
            menu_main
            ;;
        detect)
            util_print_banner
            printf '  %bOS Detection:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
            os_get_info
            fw_get_info
            ;;
        status)
            _fw_require_backend || exit "${E_FW_NOT_FOUND}"
            fw_status
            ;;
        block-all)
            _fw_require_backend || exit "${E_FW_NOT_FOUND}"
            backup_create_restore_point "pre_block_all" || true
            rule_block_all_traffic
            ;;
        allow-all)
            _fw_require_backend || exit "${E_FW_NOT_FOUND}"
            rule_allow_all_traffic
            ;;
        list-rules)
            rule_index_list_formatted
            ;;
        system-rules)
            _menu_list_system_rules
            ;;
        add-rule)
            _fw_require_backend || exit "${E_FW_NOT_FOUND}"
            _cli_add_rule "${_CLI_COMMAND_ARGS[@]}"
            ;;
        remove-rule)
            [[ "${#_CLI_COMMAND_ARGS[@]}" -lt 1 ]] && { printf 'Error: remove-rule requires a rule ID\n' >&2; exit "${E_USAGE}"; }
            rule_remove "${_CLI_COMMAND_ARGS[0]}"
            ;;
        activate-rule)
            [[ "${#_CLI_COMMAND_ARGS[@]}" -lt 1 ]] && { printf 'Error: activate-rule requires a rule ID\n' >&2; exit "${E_USAGE}"; }
            rule_activate "${_CLI_COMMAND_ARGS[0]}"
            ;;
        deactivate-rule)
            [[ "${#_CLI_COMMAND_ARGS[@]}" -lt 1 ]] && { printf 'Error: deactivate-rule requires a rule ID\n' >&2; exit "${E_USAGE}"; }
            rule_deactivate "${_CLI_COMMAND_ARGS[0]}"
            ;;
        import)
            [[ "${#_CLI_COMMAND_ARGS[@]}" -lt 1 ]] && { printf 'Error: import requires a file path\n' >&2; exit "${E_USAGE}"; }
            _fw_require_backend || exit "${E_FW_NOT_FOUND}"
            rule_import_file "${_CLI_COMMAND_ARGS[0]}"
            ;;
        export)
            [[ "${#_CLI_COMMAND_ARGS[@]}" -lt 1 ]] && { printf 'Error: export requires a file path\n' >&2; exit "${E_USAGE}"; }
            rule_export_file "${_CLI_COMMAND_ARGS[0]}"
            ;;
        backup)
            backup_create "${_CLI_COMMAND_ARGS[0]:-manual}"
            ;;
        restore)
            [[ "${#_CLI_COMMAND_ARGS[@]}" -lt 1 ]] && { printf 'Error: restore requires a backup file path\n' >&2; exit "${E_USAGE}"; }
            backup_restore "${_CLI_COMMAND_ARGS[0]}"
            ;;
        install)
            [[ "${#_CLI_COMMAND_ARGS[@]}" -lt 1 ]] && { printf 'Error: install requires a firewall name\n' >&2; exit "${E_USAGE}"; }
            install_firewall "${_CLI_COMMAND_ARGS[0]}"
            ;;
        update)
            [[ "${#_CLI_COMMAND_ARGS[@]}" -lt 1 ]] && { printf 'Error: update requires a firewall name\n' >&2; exit "${E_USAGE}"; }
            update_firewall "${_CLI_COMMAND_ARGS[0]}"
            ;;
        *)
            printf 'Error: Unknown command: %s\n' "${_CLI_COMMAND}" >&2
            printf 'Run with --help for usage information\n' >&2
            exit "${E_USAGE}"
            ;;
    esac
}

# ==============================================================================
# _cli_add_rule()
# Description:  Parse and execute add-rule CLI subcommand.
# ==============================================================================
_cli_add_rule() {
    local -A rule_params=()
    rule_params[direction]="inbound"
    rule_params[protocol]="tcp"
    rule_params[action]="accept"
    rule_params[duration_type]="permanent"
    rule_params[ttl]="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --direction)     shift; rule_params[direction]="$1" ;;
            --protocol)      shift; rule_params[protocol]="$1" ;;
            --src-ip)        shift; rule_params[src_ip]="$1" ;;
            --dst-ip)        shift; rule_params[dst_ip]="$1" ;;
            --src-port)      shift; rule_params[src_port]="$1" ;;
            --dst-port)      shift; rule_params[dst_port]="$1" ;;
            --action)        shift; rule_params[action]="$1" ;;
            --duration)      shift; rule_params[duration_type]="$1" ;;
            --ttl)           shift; rule_params[ttl]="$1" ;;
            --description)   shift; rule_params[description]="$1" ;;
            --zone)          shift; rule_params[zone]="$1" ;;
            --interface)     shift; rule_params[interface]="$1" ;;
            --chain)         shift; rule_params[chain]="$1" ;;
            --table)         shift; rule_params[table]="$1" ;;
            *) printf 'Warning: Unknown add-rule option: %s\n' "$1" >&2 ;;
        esac
        shift
    done

    if rule_create "rule_params"; then
        printf 'Rule created: %s\n' "${RULE_CREATE_ID}"
    else
        printf 'Failed to create rule\n' >&2
        exit "${E_RULE_APPLY_FAIL}"
    fi
}

# ==============================================================================
# main()
# Description:  Main entry point function.
# Parameters:   $@ - Command-line arguments
# ==============================================================================
main() {
    _parse_args "$@"
    _initialize
    _execute_command
}

# ==============================================================================
# Source Guard (Bash Lesson #8)
# Allows BATS test framework to source without executing main
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
