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
# Version:      1.1.10
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

# Source help system
# shellcheck source=lib/menu/help_system.sh
source "${APOTROPAIOS_BASE_DIR}/lib/menu/help_system.sh"

# ==============================================================================
# CLI Argument Parsing State
# ==============================================================================
_CLI_LOG_LEVEL=""
_CLI_BACKEND=""
_CLI_COMMAND=""
_CLI_NON_INTERACTIVE=0
_CLI_INTERACTIVE=0
_CLI_COMMAND_HELP=0
declare -a _CLI_COMMAND_ARGS=()

# ==============================================================================
# _parse_args()
# Description:  Parse command-line arguments and options. Supports progressive
#               help: --help before a command shows global help; --help after
#               a command shows command-specific help.
# Parameters:   $@ - All command-line arguments
# ==============================================================================
_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                # If a command has already been captured, this is command-specific help
                if [[ -n "${_CLI_COMMAND}" ]]; then
                    _CLI_COMMAND_HELP=1
                else
                    # No command yet — show global help
                    _show_usage
                    exit "${E_SUCCESS}"
                fi
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
            --interactive)
                _CLI_INTERACTIVE=1
                ;;
            -*)
                # If a command is already set, pass unknown flags as command args
                # (e.g., add-rule --direction inbound)
                if [[ -n "${_CLI_COMMAND}" ]]; then
                    _CLI_COMMAND_ARGS+=("$1")
                else
                    printf 'Error: Unknown option: %s\n' "$1" >&2
                    printf 'Run with --help for usage information\n' >&2
                    exit "${E_USAGE}"
                fi
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
# Description:  Display top-level usage information (Tier 1 help).
#               Points users to per-command help (Tier 2) for details.
# ==============================================================================
_show_usage() {
    util_print_banner
    printf 'Usage: %s [OPTIONS] [COMMAND] [ARGS...]\n' "$(basename "$0")"
    printf '       %s COMMAND --help     %b(detailed command help)%b\n\n' "$(basename "$0")" "${COLOR_DIM}" "${COLOR_RESET}"

    printf '%bGlobal Options:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %-26s %s\n' "-h, --help" "Show this help (or COMMAND --help for details)"
    printf '  %-26s %s\n' "-v, --version" "Show version and exit"
    printf '  %-26s %s\n' "--interactive" "Launch the interactive menu-driven interface"
    printf '  %-26s %s\n' "--log-level LEVEL" "Set verbosity: trace|debug|info|warning|error|critical"
    printf '  %-26s %s\n' "--backend NAME" "Set firewall: firewalld|ipset|iptables|nftables|ufw"
    printf '  %-26s %s\n' "--non-interactive" "Disable interactive prompts (for scripting/automation)"

    printf '\n%bCommands:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "menu" "${COLOR_RESET}" "Launch interactive menu (default if no command given)"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "detect" "${COLOR_RESET}" "Detect OS and installed firewalls"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "status" "${COLOR_RESET}" "Show active firewall backend status"
    printf '\n'
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "add-rule [OPTS]" "${COLOR_RESET}" "Create and apply a firewall rule"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "remove-rule ID" "${COLOR_RESET}" "Remove a rule by its UUID"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "activate-rule ID" "${COLOR_RESET}" "Re-activate a deactivated rule"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "deactivate-rule ID" "${COLOR_RESET}" "Deactivate a rule (keep in index)"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "list-rules" "${COLOR_RESET}" "List all Apotropaios-tracked rules"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "system-rules" "${COLOR_RESET}" "Audit all native system firewall rules"
    printf '\n'
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "block-all" "${COLOR_RESET}" "Block ALL inbound and outbound traffic"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "allow-all" "${COLOR_RESET}" "Allow ALL traffic (remove restrictions)"
    printf '\n'
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "import FILE" "${COLOR_RESET}" "Import rules from configuration file"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "export FILE" "${COLOR_RESET}" "Export rules to configuration file"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "backup [LABEL]" "${COLOR_RESET}" "Create a configuration backup"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "restore FILE" "${COLOR_RESET}" "Restore from backup archive"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "install FW_NAME" "${COLOR_RESET}" "Install a firewall package"
    printf '  %b%-22s%b %s\n' "${COLOR_CYAN}" "update FW_NAME" "${COLOR_RESET}" "Update a firewall package"

    printf '\n%bOperation Modes:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  The framework operates in two distinct modes:\n'
    printf '    %bInteractive:%b  sudo %s --interactive        %b(guided menu interface)%b\n' "${COLOR_CYAN}" "${COLOR_RESET}" "$(basename "$0")" "${COLOR_DIM}" "${COLOR_RESET}"
    printf '    %bCLI:%b          sudo %s COMMAND [OPTIONS]    %b(direct command execution)%b\n' "${COLOR_CYAN}" "${COLOR_RESET}" "$(basename "$0")" "${COLOR_DIM}" "${COLOR_RESET}"

    printf '\n%bQuick Examples:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  sudo %s --interactive                          # Launch interactive menu\n' "$(basename "$0")"
    printf '  sudo %s detect                                 # Scan system (CLI mode)\n' "$(basename "$0")"
    printf '  sudo %s add-rule --help                        # Full add-rule help\n' "$(basename "$0")"
    printf '  sudo %s add-rule --dst-port 443 --action accept\n' "$(basename "$0")"
    printf '  sudo %s backup pre-deploy\n' "$(basename "$0")"

    printf '\n%bDetailed Help:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  Every command supports --help for detailed usage, options, and examples:\n'
    printf '    %s add-rule --help      Full rule option reference\n' "$(basename "$0")"
    printf '    %s backup --help        Backup contents and retention info\n' "$(basename "$0")"
    printf '    %s import --help        Configuration file format reference\n' "$(basename "$0")"
    printf '\n'
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
# Description:  Execute the CLI command. Checks for per-command help first.
# ==============================================================================
_execute_command() {
    # Tier 2: If --help was passed after a command, show command-specific help
    if [[ "${_CLI_COMMAND_HELP}" -eq 1 ]] && [[ -n "${_CLI_COMMAND}" ]]; then
        help_dispatch "${_CLI_COMMAND}"
        return $?
    fi

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
            --help|-h)       help_cmd_add_rule; exit "${E_SUCCESS}" ;;
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
            --conn-state|--state)  shift; rule_params[conn_state]="$1" ;;
            --log-prefix)    shift; rule_params[log_prefix]="$1" ;;
            --log-level)     shift; rule_params[log_level]="$1" ;;
            --limit)         shift; rule_params[limit]="$1" ;;
            --limit-burst)   shift; rule_params[limit_burst]="$1" ;;
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

    # Validate mutually exclusive flags
    if [[ "${_CLI_INTERACTIVE}" -eq 1 ]] && [[ "${_CLI_NON_INTERACTIVE}" -eq 1 ]]; then
        printf 'Error: --interactive and --non-interactive are mutually exclusive\n' >&2
        exit "${E_USAGE}"
    fi

    # Validate --interactive is not combined with a CLI command
    if [[ "${_CLI_INTERACTIVE}" -eq 1 ]] && [[ -n "${_CLI_COMMAND}" ]]; then
        printf 'Error: --interactive cannot be combined with a command (%s)\n' "${_CLI_COMMAND}" >&2
        printf 'Use --interactive for menu mode, or specify a command for CLI mode\n' >&2
        exit "${E_USAGE}"
    fi

    # --interactive flag forces menu mode
    if [[ "${_CLI_INTERACTIVE}" -eq 1 ]]; then
        _CLI_COMMAND="menu"
    fi

    # Per-command help (Tier 2) does not require full initialization
    # — the help functions only use constants and printf, no firewall ops
    if [[ "${_CLI_COMMAND_HELP}" -eq 1 ]] && [[ -n "${_CLI_COMMAND}" ]]; then
        help_dispatch "${_CLI_COMMAND}"
        exit $?
    fi

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
