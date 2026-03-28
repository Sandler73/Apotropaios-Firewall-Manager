#!/usr/bin/env bash
# ==============================================================================
# File:         lib/menu/menu_main.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Main interactive menu-driven interface
# Description:  Provides the primary interactive menu for the framework.
#               Orchestrates navigation between submenus for rule management,
#               firewall management, backup/restore, and help documentation.
# Notes:        - All menu input validated before processing
#               - Menu state does not persist — stateless per invocation
#               - Ctrl+C handled gracefully via error subsystem traps
#               - v1.1.0: Added backend selection in rule wizard, system rules
#                 audit, rule expiry watcher notifications
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_MENU_MAIN_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_MENU_MAIN_LOADED=1

# ==============================================================================
# menu_main()
# Description:  Display and handle the main menu loop.
# Returns:      0 on clean exit
# ==============================================================================
menu_main() {
    local choice=""

    while true; do
        _menu_main_display
        printf '  %bSelect option [1-8, q to quit]:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"
        read -r choice </dev/tty 2>/dev/null || choice="q"

        # Sanitize input
        choice="$(sanitize_input "${choice}")"
        choice="$(util_trim "${choice}")"

        case "${choice}" in
            1) menu_firewall_management ;;
            2) menu_rule_management ;;
            3) menu_rule_quick_actions ;;
            4) menu_backup_management ;;
            5) menu_system_info ;;
            6) menu_install_management ;;
            7) menu_help ;;
            8|q|Q|quit|exit)
                printf '\n  %bExiting Apotropaios. Stay protected.%b\n\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                return "${E_SUCCESS}"
                ;;
            *)
                printf '  %bInvalid option. Please try again.%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                ;;
        esac
    done
}

# ==============================================================================
# _menu_main_display() [INTERNAL]
# ==============================================================================
_menu_main_display() {
    printf '\n'
    util_print_banner
    util_print_separator "═" 60

    printf '  %b MAIN MENU %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    util_print_separator "─" 60
    printf '\n'
    printf '  %b1.%b Firewall Management     (start, stop, status, select)\n'  "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b2.%b Rule Management          (create, list, modify, import)\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b3.%b Quick Actions            (block all, allow all)\n'         "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b4.%b Backup & Recovery        (backup, restore, snapshots)\n'   "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b5.%b System Information       (OS, firewalls, status)\n'        "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b6.%b Install & Update         (install, update, configure)\n'   "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b7.%b Help & Documentation\n'                                    "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b8.%b Exit\n'                                                    "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '\n'
    printf '  %bActive backend:%b %s\n' "${COLOR_DIM}" "${COLOR_RESET}" "${FW_ACTIVE_BACKEND:-none}"
    printf '  %bRules tracked:%b  %s\n' "${COLOR_DIM}" "${COLOR_RESET}" "$(rule_index_count 2>/dev/null || echo 0)"
    util_print_separator "═" 60
}

# ==============================================================================
# menu_firewall_management()
# ==============================================================================
menu_firewall_management() {
    local choice=""
    while true; do
        printf '\n'
        util_print_separator "─" 55
        printf '  %b FIREWALL MANAGEMENT %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        util_print_separator "─" 55
        printf '  %b1.%b Select active firewall backend\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b2.%b Start/enable firewall\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b3.%b Stop/disable firewall\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b4.%b Firewall status\n'        "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b5.%b Reload configuration\n'   "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b6.%b Reset to defaults\n'      "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b7.%b List current rules\n'     "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b8.%b Backend configuration\n'  "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %bb.%b Back to main menu\n'      "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '\n  %bActive: %s%b\n' "${COLOR_DIM}" "${FW_ACTIVE_BACKEND:-none}" "${COLOR_RESET}"
        printf '  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"
        read -r choice </dev/tty 2>/dev/null || choice="b"
        choice="$(sanitize_input "${choice}")"

        case "${choice}" in
            1) _menu_select_backend ;;
            2)
                if _fw_require_backend; then
                    fw_enable && printf '  %bFirewall enabled%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                fi
                ;;
            3)
                if _fw_require_backend; then
                    fw_disable && printf '  %bFirewall disabled%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                fi
                ;;
            4)
                if _fw_require_backend; then
                    printf '\n'
                    fw_status
                    printf '\n  Press Enter to continue...'
                    read -r </dev/tty 2>/dev/null || true
                fi
                ;;
            5)
                if _fw_require_backend; then
                    fw_reload && printf '  %bConfiguration reloaded%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                fi
                ;;
            6)
                if util_confirm "Reset firewall to defaults? This cannot be undone"; then
                    backup_create_restore_point "pre_reset" || true
                    _fw_require_backend && fw_reset
                fi
                ;;
            7)
                if _fw_require_backend; then
                    printf '\n'
                    fw_list_rules
                    printf '\n  Press Enter to continue...'
                    read -r </dev/tty 2>/dev/null || true
                fi
                ;;
            8) _menu_backend_config ;;
            b|B|back) return ;;
            *) printf '  %bInvalid option%b\n' "${COLOR_RED}" "${COLOR_RESET}" ;;
        esac
    done
}

# ==============================================================================
# _menu_select_backend() [INTERNAL]
# ==============================================================================
_menu_select_backend() {
    local installed
    installed="$(fw_get_installed)"

    if [[ -z "${installed}" ]]; then
        printf '  %bNo firewalls installed. Use Install & Update to add one.%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return
    fi

    printf '\n  Installed firewalls:\n'
    local i=1
    local -a fw_list=()
    local fw
    for fw in ${installed}; do
        fw_list+=("${fw}")
        local running=""
        fw_is_running "${fw}" && running=" ${COLOR_GREEN}(running)${COLOR_RESET}"
        printf '  %b%d.%b %s%b\n' "${COLOR_BOLD}" "${i}" "${COLOR_RESET}" "${fw}" "${running}"
        ((i++)) || true
    done

    printf '\n  %bSelect [1-%d]:%b ' "${COLOR_CYAN}" "${#fw_list[@]}" "${COLOR_RESET}"
    local sel
    read -r sel </dev/tty 2>/dev/null || return
    sel="$(sanitize_input "${sel}")"

    if validate_numeric "${sel}" 1 "${#fw_list[@]}"; then
        local idx=$((sel - 1))
        fw_set_backend "${fw_list[${idx}]}" && \
            printf '  %bBackend set to: %s%b\n' "${COLOR_GREEN}" "${fw_list[${idx}]}" "${COLOR_RESET}"
    else
        printf '  %bInvalid selection%b\n' "${COLOR_RED}" "${COLOR_RESET}"
    fi
}

# ==============================================================================
# menu_rule_management()
# ENH-002: Renamed option 2, ENH-003: Added option 3 "List existing System rules"
# ==============================================================================
menu_rule_management() {
    local choice=""
    while true; do
        printf '\n'
        util_print_separator "─" 55
        printf '  %b RULE MANAGEMENT %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        util_print_separator "─" 55
        printf '  %b 1.%b Create new rule\n'                "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b 2.%b List all Apotropaios rules\n'     "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b 3.%b List existing System rules\n'     "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b 4.%b Remove rule by ID\n'              "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b 5.%b Activate rule\n'                  "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b 6.%b Deactivate rule\n'                "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b 7.%b Import rules from file\n'         "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b 8.%b Export rules to file\n'           "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b 9.%b Check expired rules\n'            "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b10.%b Rule expiry watcher\n'            "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b b.%b Back\n'                           "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '\n  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"
        read -r choice </dev/tty 2>/dev/null || choice="b"
        choice="$(sanitize_input "${choice}")"

        case "${choice}" in
            1)  _menu_create_rule ;;
            2)  rule_index_list_formatted ;;
            3)  _menu_list_system_rules ;;
            4)  _menu_remove_rule ;;
            5)  _menu_activate_rule ;;
            6)  _menu_deactivate_rule ;;
            7)  _menu_import_rules ;;
            8)  _menu_export_rules ;;
            9)  rule_check_expired; printf '  Done\n' ;;
            10) _menu_rule_watcher ;;
            b|B) return ;;
            *) printf '  %bInvalid option%b\n' "${COLOR_RED}" "${COLOR_RESET}" ;;
        esac
    done
}

# ==============================================================================
# _menu_create_rule() [INTERNAL]
# Description:  Interactive rule creation wizard with backend selection and
#               backend-specific field prompts.
# BUG-003/ENH-001: Added backend selection, ipset/firewalld-specific fields
# ==============================================================================
_menu_create_rule() {
    printf '\n  %b=== Create Firewall Rule ===%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"

    # Step 1: Select firewall backend
    local installed
    installed="$(fw_get_installed)"
    if [[ -z "${installed}" ]]; then
        printf '  %bNo firewalls installed. Cannot create rules.%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return
    fi

    printf '\n  %bStep 1: Select firewall backend%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    local i=1
    local -a fw_list=()
    local fw
    for fw in ${installed}; do
        fw_list+=("${fw}")
        local marker=""
        [[ "${fw}" == "${FW_ACTIVE_BACKEND}" ]] && marker=" ${COLOR_GREEN}(active)${COLOR_RESET}"
        printf '  %b%d.%b %s%b\n' "${COLOR_BOLD}" "${i}" "${COLOR_RESET}" "${fw}" "${marker}"
        ((i++)) || true
    done

    printf '  %bSelect backend [1-%d]:%b ' "${COLOR_CYAN}" "${#fw_list[@]}" "${COLOR_RESET}"
    local sel
    read -r sel </dev/tty 2>/dev/null || return
    sel="$(sanitize_input "${sel}")"
    if ! validate_numeric "${sel}" 1 "${#fw_list[@]}"; then
        printf '  %bInvalid selection%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return
    fi
    local idx=$((sel - 1))
    local selected_backend="${fw_list[${idx}]}"
    fw_set_backend "${selected_backend}" 2>/dev/null || return

    printf '  %bUsing backend: %s%b\n\n' "${COLOR_GREEN}" "${selected_backend}" "${COLOR_RESET}"

    # Declare the rule parameters array
    local -A new_rule=()
    new_rule[backend]="${selected_backend}"

    # Step 2: Common fields
    printf '  %bStep 2: Rule parameters%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"

    # Direction
    printf '  Direction (inbound/outbound/forward) [inbound]: '
    local dir_input
    read -r dir_input </dev/tty 2>/dev/null || dir_input="inbound"
    new_rule[direction]="$(util_to_lower "$(sanitize_input "${dir_input:-inbound}")")"

    # Protocol
    printf '  Protocol (tcp/udp/icmp/sctp/all) [tcp]: '
    local proto_input
    read -r proto_input </dev/tty 2>/dev/null || proto_input="tcp"
    new_rule[protocol]="$(util_to_lower "$(sanitize_input "${proto_input:-tcp}")")"

    # Source IP
    printf '  Source IP/CIDR (leave empty for any): '
    local src_input
    read -r src_input </dev/tty 2>/dev/null || src_input=""
    new_rule[src_ip]="$(sanitize_input "${src_input}")"

    # Destination IP
    printf '  Destination IP/CIDR (leave empty for any): '
    local dst_input
    read -r dst_input </dev/tty 2>/dev/null || dst_input=""
    new_rule[dst_ip]="$(sanitize_input "${dst_input}")"

    # Source port (only for tcp/udp/sctp)
    if [[ "${new_rule[protocol]}" == "tcp" ]] || [[ "${new_rule[protocol]}" == "udp" ]] || [[ "${new_rule[protocol]}" == "sctp" ]]; then
        printf '  Source port or range (leave empty for any): '
        local sport_input
        read -r sport_input </dev/tty 2>/dev/null || sport_input=""
        new_rule[src_port]="$(sanitize_input "${sport_input}")"
    fi

    # Destination port (only for tcp/udp/sctp)
    if [[ "${new_rule[protocol]}" == "tcp" ]] || [[ "${new_rule[protocol]}" == "udp" ]] || [[ "${new_rule[protocol]}" == "sctp" ]]; then
        printf '  Destination port or range (leave empty for any): '
        local dport_input
        read -r dport_input </dev/tty 2>/dev/null || dport_input=""
        new_rule[dst_port]="$(sanitize_input "${dport_input}")"
    fi

    # Action — supports compound (e.g., "log,drop")
    printf '  Action (accept/drop/reject/log or compound e.g. log,drop) [accept]: '
    local action_input
    read -r action_input </dev/tty 2>/dev/null || action_input="accept"
    new_rule[action]="$(util_to_lower "$(sanitize_input "${action_input:-accept}")")"

    # Interface
    printf '  Network interface (leave empty for any): '
    local iface_input
    read -r iface_input </dev/tty 2>/dev/null || iface_input=""
    new_rule[interface]="$(sanitize_input "${iface_input}")"

    # Connection state
    printf '  Connection state (new/established/related/invalid, comma-separated, or empty): '
    local cs_input
    read -r cs_input </dev/tty 2>/dev/null || cs_input=""
    cs_input="$(sanitize_input "${cs_input}")"
    if [[ -n "${cs_input}" ]]; then
        new_rule[conn_state]="$(util_to_lower "${cs_input}")"
    fi

    # Advanced logging options (if action includes log)
    if [[ "${new_rule[action]}" == *"log"* ]]; then
        printf '\n  %bLog Options:%b\n' "${COLOR_DIM}" "${COLOR_RESET}"
        printf '  Log prefix (max 29 chars, leave empty for auto): '
        local lp_input
        read -r lp_input </dev/tty 2>/dev/null || lp_input=""
        lp_input="$(sanitize_input "${lp_input}")"
        [[ -n "${lp_input}" ]] && new_rule[log_prefix]="${lp_input}"

        printf '  Log level (emerg/alert/crit/err/warning/notice/info/debug) [warning]: '
        local ll_input
        read -r ll_input </dev/tty 2>/dev/null || ll_input=""
        ll_input="$(sanitize_input "${ll_input}")"
        [[ -n "${ll_input}" ]] && new_rule[log_level]="$(util_to_lower "${ll_input}")"
    fi

    # Rate limiting
    printf '  Rate limit (e.g. 5/minute, 10/second, or empty for none): '
    local rl_input
    read -r rl_input </dev/tty 2>/dev/null || rl_input=""
    rl_input="$(sanitize_input "${rl_input}")"
    if [[ -n "${rl_input}" ]]; then
        new_rule[limit]="${rl_input}"
        printf '  Limit burst (packets before limit kicks in, or empty) [5]: '
        local lb_input
        read -r lb_input </dev/tty 2>/dev/null || lb_input=""
        lb_input="$(sanitize_input "${lb_input}")"
        [[ -n "${lb_input}" ]] && new_rule[limit_burst]="${lb_input}"
    fi

    # Step 3: Backend-specific fields
    printf '\n  %bStep 3: %s-specific options%b\n' "${COLOR_BOLD}" "${selected_backend}" "${COLOR_RESET}"

    case "${selected_backend}" in
        firewalld)
            printf '  Zone [public]: '
            local zone_input
            read -r zone_input </dev/tty 2>/dev/null || zone_input="public"
            new_rule[zone]="$(sanitize_input "${zone_input:-public}")"
            printf '  Make permanent? (y/n) [y]: '
            local perm_input
            read -r perm_input </dev/tty 2>/dev/null || perm_input="y"
            if [[ "$(util_to_lower "${perm_input:-y}")" == "y" ]]; then
                new_rule[permanent]="1"
            else
                new_rule[permanent]="0"
            fi
            ;;
        ipset)
            printf '  IPSet name (required): '
            local sname_input
            read -r sname_input </dev/tty 2>/dev/null || sname_input=""
            sname_input="$(sanitize_input "${sname_input}")"
            if [[ -z "${sname_input}" ]]; then
                printf '  %bIPSet name is required for ipset rules%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                return
            fi
            new_rule[set_name]="${sname_input}"
            printf '  Set type (hash:ip/hash:net/hash:ip,port) [hash:net]: '
            local stype_input
            read -r stype_input </dev/tty 2>/dev/null || stype_input="hash:net"
            new_rule[set_type]="$(sanitize_input "${stype_input:-hash:net}")"
            printf '  Entry to add (IP/CIDR to add to the set): '
            local entry_input
            read -r entry_input </dev/tty 2>/dev/null || entry_input=""
            new_rule[entry]="$(sanitize_input "${entry_input}")"
            printf '  Also create iptables match rule? (y/n) [y]: '
            local fwr_input
            read -r fwr_input </dev/tty 2>/dev/null || fwr_input="y"
            if [[ "$(util_to_lower "${fwr_input:-y}")" == "y" ]]; then
                new_rule[create_fw_rule]="1"
            else
                new_rule[create_fw_rule]="0"
            fi
            ;;
        nftables)
            printf '  Table name [apotropaios]: '
            local tbl_input
            read -r tbl_input </dev/tty 2>/dev/null || tbl_input="apotropaios"
            new_rule[table]="$(sanitize_input "${tbl_input:-apotropaios}")"
            printf '  Table family (inet/ip/ip6) [inet]: '
            local fam_input
            read -r fam_input </dev/tty 2>/dev/null || fam_input="inet"
            new_rule[table_family]="$(sanitize_input "${fam_input:-inet}")"
            ;;
        iptables)
            printf '  Table (filter/nat/mangle/raw) [filter]: '
            local itbl_input
            read -r itbl_input </dev/tty 2>/dev/null || itbl_input="filter"
            new_rule[table]="$(sanitize_input "${itbl_input:-filter}")"
            printf '  Chain (leave empty for auto based on direction): '
            local chain_input
            read -r chain_input </dev/tty 2>/dev/null || chain_input=""
            new_rule[chain]="$(sanitize_input "${chain_input}")"
            ;;
        ufw)
            printf '  %b(No additional ufw-specific options needed)%b\n' "${COLOR_DIM}" "${COLOR_RESET}"
            ;;
    esac

    # Step 4: Duration
    printf '\n  %bStep 4: Duration%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  Duration (permanent/temporary) [permanent]: '
    local dur_input
    read -r dur_input </dev/tty 2>/dev/null || dur_input="permanent"
    new_rule[duration_type]="$(util_to_lower "$(sanitize_input "${dur_input:-permanent}")")"

    if [[ "${new_rule[duration_type]}" == "temporary" ]]; then
        printf '  TTL in seconds (60-2592000) [3600]: '
        local ttl_input
        read -r ttl_input </dev/tty 2>/dev/null || ttl_input="3600"
        new_rule[ttl]="$(sanitize_input "${ttl_input:-3600}")"
    else
        new_rule[ttl]="0"
    fi

    # Description
    printf '  Description (optional): '
    local desc_input
    read -r desc_input </dev/tty 2>/dev/null || desc_input=""
    new_rule[description]="$(sanitize_input "${desc_input}")"

    # Step 5: Summary and confirmation
    printf '\n  %b=== Rule Summary ===%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    util_print_kv "Backend" "${selected_backend}" 18
    util_print_kv "Direction" "${new_rule[direction]}" 18
    util_print_kv "Protocol" "${new_rule[protocol]}" 18
    util_print_kv "Source IP" "${new_rule[src_ip]:-any}" 18
    util_print_kv "Destination IP" "${new_rule[dst_ip]:-any}" 18
    [[ -n "${new_rule[src_port]:-}" ]] && util_print_kv "Source Port" "${new_rule[src_port]}" 18
    [[ -n "${new_rule[dst_port]:-}" ]] && util_print_kv "Dest Port" "${new_rule[dst_port]}" 18
    util_print_kv "Action" "${new_rule[action]}" 18
    [[ -n "${new_rule[interface]:-}" ]] && util_print_kv "Interface" "${new_rule[interface]}" 18
    [[ -n "${new_rule[conn_state]:-}" ]] && util_print_kv "Conn State" "${new_rule[conn_state]}" 18
    [[ -n "${new_rule[log_prefix]:-}" ]] && util_print_kv "Log Prefix" "${new_rule[log_prefix]}" 18
    [[ -n "${new_rule[log_level]:-}" ]] && util_print_kv "Log Level" "${new_rule[log_level]}" 18
    [[ -n "${new_rule[limit]:-}" ]] && util_print_kv "Rate Limit" "${new_rule[limit]}" 18
    [[ -n "${new_rule[limit_burst]:-}" ]] && util_print_kv "Limit Burst" "${new_rule[limit_burst]}" 18
    util_print_kv "Duration" "${new_rule[duration_type]}" 18
    [[ "${new_rule[duration_type]}" == "temporary" ]] && util_print_kv "TTL" "${new_rule[ttl]}s ($(util_human_duration "${new_rule[ttl]}"))" 18

    # Backend-specific summary
    case "${selected_backend}" in
        firewalld) util_print_kv "Zone" "${new_rule[zone]:-public}" 18 ;;
        ipset)     util_print_kv "Set Name" "${new_rule[set_name]}" 18; util_print_kv "Set Type" "${new_rule[set_type]:-hash:net}" 18 ;;
        nftables)  util_print_kv "Table" "${new_rule[table_family]:-inet} ${new_rule[table]:-apotropaios}" 18 ;;
        iptables)  util_print_kv "Table" "${new_rule[table]:-filter}" 18 ;;
    esac

    [[ -n "${new_rule[description]:-}" ]] && util_print_kv "Description" "${new_rule[description]}" 18

    printf '\n'
    if util_confirm "Apply this rule?"; then
        if rule_create "new_rule"; then
            printf '  %bRule created successfully: %s%b\n' "${COLOR_GREEN}" "${RULE_CREATE_ID}" "${COLOR_RESET}"
        else
            printf '  %bFailed to create rule. Check log for details.%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        fi
    else
        printf '  Rule creation cancelled\n'
    fi
}

# ==============================================================================
# _menu_list_system_rules() [INTERNAL]
# Description:  Audit and display all existing firewall rules across all
#               installed backends. Shows native/default rules not created
#               by Apotropaios. ENH-003
# ==============================================================================
_menu_list_system_rules() {
    printf '\n  %b=== Existing System Firewall Rules ===%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b(Rules from all installed firewall backends)%b\n\n' "${COLOR_DIM}" "${COLOR_RESET}"

    local found_any=0
    local fw_name

    for fw_name in "${SUPPORTED_FW_LIST[@]}"; do
        if ! fw_is_installed "${fw_name}"; then
            continue
        fi

        printf '  %b┌── %s ──┐%b\n' "${COLOR_BOLD}" "${fw_name}" "${COLOR_RESET}"

        local output=""
        case "${fw_name}" in
            iptables)
                output="$(iptables -L -n --line-numbers 2>&1)" || true
                ;;
            nftables)
                output="$(nft list ruleset 2>&1)" || true
                ;;
            firewalld)
                if util_is_command_available firewall-cmd; then
                    output="$(firewall-cmd --list-all 2>&1)" || true
                fi
                ;;
            ufw)
                output="$(ufw status numbered verbose 2>&1)" || true
                ;;
            ipset)
                output="$(ipset list -t 2>&1)" || true
                ;;
        esac

        if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]] || [[ "${output}" == *"you must be root"* ]]; then
            printf '  %b  Root privileges required to view %s rules%b\n' "${COLOR_RED}" "${fw_name}" "${COLOR_RESET}"
        elif [[ -z "${output}" ]]; then
            printf '    %b(no rules configured)%b\n' "${COLOR_DIM}" "${COLOR_RESET}"
        else
            # Indent and display output
            while IFS= read -r line; do
                printf '    %s\n' "${line}"
            done <<< "${output}"
            found_any=1
        fi
        printf '\n'
    done

    if [[ "${found_any}" -eq 0 ]]; then
        printf '  %bNo system rules found or insufficient permissions.%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
        printf '  %bRun with sudo for full visibility.%b\n' "${COLOR_DIM}" "${COLOR_RESET}"
    fi

    printf '  Press Enter to continue...'
    read -r </dev/tty 2>/dev/null || true
}

# ==============================================================================
# _menu_remove_rule() [INTERNAL]
# ==============================================================================
_menu_remove_rule() {
    rule_index_list_formatted
    printf '\n  Enter Rule ID to remove (or b to cancel): '
    local rid
    read -r rid </dev/tty 2>/dev/null || return
    rid="$(sanitize_input "${rid}")"
    [[ -z "${rid}" ]] && { printf '  %bInvalid input: Rule ID cannot be empty%b\n' "${COLOR_RED}" "${COLOR_RESET}"; return; }
    [[ "${rid}" == "b" || "${rid}" == "B" ]] && return

    # Validate UUID format before calling engine
    if ! validate_rule_id "${rid}" 2>/dev/null; then
        printf '  %bInvalid input: Not a valid rule ID format (expected UUID)%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return
    fi

    if util_confirm "Remove rule ${rid}?"; then
        local _rc=0
        rule_remove "${rid}" && _rc=0 || _rc=$?
        if [[ "${_rc}" -eq 0 ]]; then
            printf '  %bRule removed%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
        elif [[ "${_rc}" -eq "${E_RULE_NOT_FOUND}" ]]; then
            printf '  %bRule not found: %s%b\n' "${COLOR_RED}" "${rid}" "${COLOR_RESET}"
        else
            printf '  %bFailed to remove rule (error code: %d)%b\n' "${COLOR_RED}" "${_rc}" "${COLOR_RESET}"
        fi
    fi
}

# ==============================================================================
# _menu_activate_rule() / _menu_deactivate_rule() [INTERNAL]
# ==============================================================================
_menu_activate_rule() {
    rule_index_list_formatted
    printf '\n  Enter Rule ID to activate (or b to cancel): '
    local rid; read -r rid </dev/tty 2>/dev/null || return
    rid="$(sanitize_input "${rid}")"
    [[ -z "${rid}" ]] && { printf '  %bInvalid input: Rule ID cannot be empty%b\n' "${COLOR_RED}" "${COLOR_RESET}"; return; }
    [[ "${rid}" == "b" || "${rid}" == "B" ]] && return

    if ! validate_rule_id "${rid}" 2>/dev/null; then
        printf '  %bInvalid input: Not a valid rule ID format (expected UUID)%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return
    fi

    local _rc=0
    rule_activate "${rid}" && _rc=0 || _rc=$?
    if [[ "${_rc}" -eq 0 ]]; then
        printf '  %bRule activated%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
    elif [[ "${_rc}" -eq "${E_RULE_NOT_FOUND}" ]]; then
        printf '  %bRule not found: %s%b\n' "${COLOR_RED}" "${rid}" "${COLOR_RESET}"
    elif [[ "${_rc}" -eq "${E_RULE_APPLY_FAIL}" ]]; then
        printf '  %bFailed to apply rule to backend%b\n' "${COLOR_RED}" "${COLOR_RESET}"
    else
        printf '  %bFailed to activate rule (error code: %d)%b\n' "${COLOR_RED}" "${_rc}" "${COLOR_RESET}"
    fi
}

_menu_deactivate_rule() {
    rule_index_list_formatted
    printf '\n  Enter Rule ID to deactivate (or b to cancel): '
    local rid; read -r rid </dev/tty 2>/dev/null || return
    rid="$(sanitize_input "${rid}")"
    [[ -z "${rid}" ]] && { printf '  %bInvalid input: Rule ID cannot be empty%b\n' "${COLOR_RED}" "${COLOR_RESET}"; return; }
    [[ "${rid}" == "b" || "${rid}" == "B" ]] && return

    if ! validate_rule_id "${rid}" 2>/dev/null; then
        printf '  %bInvalid input: Not a valid rule ID format (expected UUID)%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return
    fi

    local _rc=0
    rule_deactivate "${rid}" && _rc=0 || _rc=$?
    if [[ "${_rc}" -eq 0 ]]; then
        printf '  %bRule deactivated%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
    elif [[ "${_rc}" -eq "${E_RULE_NOT_FOUND}" ]]; then
        printf '  %bRule not found: %s%b\n' "${COLOR_RED}" "${rid}" "${COLOR_RESET}"
    else
        printf '  %bFailed to deactivate rule (error code: %d)%b\n' "${COLOR_RED}" "${_rc}" "${COLOR_RESET}"
    fi
}

# ==============================================================================
# _menu_import_rules() [INTERNAL]
# Description:  Import rules from file with sub-options for scanning available
#               rule files and selecting from a list. Default path is the
#               Apotropaios data/rules directory.
# ==============================================================================
_menu_import_rules() {
    local default_dir="${APOTROPAIOS_BASE_DIR}/data/rules"

    printf '\n  %b=== Import Rules ===%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b1.%b Enter file path manually\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b2.%b Scan for available rule files\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %bb.%b Back\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '\n  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"

    local ichoice
    read -r ichoice </dev/tty 2>/dev/null || return
    ichoice="$(sanitize_input "${ichoice}")"

    local fpath=""

    case "${ichoice}" in
        1)
            printf '  Enter configuration file path (default: %s): ' "${default_dir}"
            read -r fpath </dev/tty 2>/dev/null || return
            fpath="$(sanitize_input "${fpath}")"
            [[ -z "${fpath}" ]] && { printf '  %bInvalid input: File path cannot be empty%b\n' "${COLOR_RED}" "${COLOR_RESET}"; return; }
            ;;
        2)
            printf '  Enter directory to scan [%s]: ' "${default_dir}"
            local scan_dir
            read -r scan_dir </dev/tty 2>/dev/null || return
            scan_dir="$(sanitize_input "${scan_dir}")"
            [[ -z "${scan_dir}" ]] && scan_dir="${default_dir}"

            if [[ ! -d "${scan_dir}" ]]; then
                printf '  %bDirectory not found: %s%b\n' "${COLOR_RED}" "${scan_dir}" "${COLOR_RESET}"
                return
            fi

            # Scan for .conf and .rules files
            printf '\n  %bAvailable rule files in: %s%b\n' "${COLOR_BOLD}" "${scan_dir}" "${COLOR_RESET}"
            util_print_separator "─" 60

            local -a found_files=()
            local idx=1
            while IFS= read -r -d '' f; do
                found_files+=("${f}")
                local fsize
                fsize="$(stat -c%s "${f}" 2>/dev/null)" || fsize=0
                local fdate
                fdate="$(stat -c '%y' "${f}" 2>/dev/null | cut -d'.' -f1)" || fdate="unknown"
                printf '  %b%2d.%b %-40s %6s  %s\n' "${COLOR_BOLD}" "${idx}" "${COLOR_RESET}" \
                    "$(basename "${f}")" \
                    "$(util_human_bytes "${fsize}")" \
                    "${fdate}"
                ((idx++)) || true
            done < <(find "${scan_dir}" -maxdepth 2 -type f \( -name "*.conf" -o -name "*.rules" -o -name "*.txt" \) -print0 2>/dev/null | sort -z)

            if [[ "${#found_files[@]}" -eq 0 ]]; then
                printf '  %bNo rule files found (.conf, .rules, .txt)%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                return
            fi

            printf '\n  %bSelect file [1-%d] (or b to cancel):%b ' "${COLOR_CYAN}" "${#found_files[@]}" "${COLOR_RESET}"
            local fsel
            read -r fsel </dev/tty 2>/dev/null || return
            fsel="$(sanitize_input "${fsel}")"
            [[ "${fsel}" == "b" || "${fsel}" == "B" ]] && return

            if validate_numeric "${fsel}" 1 "${#found_files[@]}"; then
                local fidx=$((fsel - 1))
                fpath="${found_files[${fidx}]}"
            else
                printf '  %bInvalid selection%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                return
            fi
            ;;
        b|B) return ;;
        *)
            printf '  %bInvalid option%b\n' "${COLOR_RED}" "${COLOR_RESET}"
            return
            ;;
    esac

    # Validate the selected file path
    if [[ ! -f "${fpath}" ]]; then
        printf '  %bFile not found: %s%b\n' "${COLOR_RED}" "${fpath}" "${COLOR_RESET}"
        return
    fi
    if [[ ! -r "${fpath}" ]]; then
        printf '  %bFile not readable: %s%b\n' "${COLOR_RED}" "${fpath}" "${COLOR_RESET}"
        return
    fi

    printf '\n  Selected: %s\n' "${fpath}"

    if util_confirm "Validate-only first (dry run)?"; then
        local _rc=0
        rule_import_file "${fpath}" 1 2>/dev/null && _rc=0 || _rc=$?
        if [[ "${_rc}" -eq 0 ]]; then
            printf '  %bValidation passed%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
            if util_confirm "Apply rules now?"; then
                rule_import_file "${fpath}" 0 2>/dev/null && _rc=0 || _rc=$?
                if [[ "${_rc}" -eq 0 ]]; then
                    printf '  %bRules imported successfully%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                else
                    printf '  %bImport completed with errors (code: %d)%b\n' "${COLOR_RED}" "${_rc}" "${COLOR_RESET}"
                fi
            fi
        else
            printf '  %bValidation failed — file contains invalid entries (code: %d)%b\n' "${COLOR_RED}" "${_rc}" "${COLOR_RESET}"
        fi
    else
        local _rc=0
        rule_import_file "${fpath}" 0 2>/dev/null && _rc=0 || _rc=$?
        if [[ "${_rc}" -eq 0 ]]; then
            printf '  %bRules imported successfully%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
        else
            printf '  %bImport completed with errors (code: %d)%b\n' "${COLOR_RED}" "${_rc}" "${COLOR_RESET}"
        fi
    fi
}

# ==============================================================================
# _menu_export_rules() [INTERNAL]
# Description:  Export Apotropaios rules to a file with default path support
#               and robust error handling to prevent framework crashes.
# ==============================================================================
_menu_export_rules() {
    local default_dir="${APOTROPAIOS_BASE_DIR}/data/rules"
    local count
    count="$(rule_index_count 2>/dev/null)" || count=0

    if [[ "${count}" -eq 0 ]]; then
        printf '  %bNo Apotropaios rules to export%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
        return
    fi

    printf '\n  %b=== Export Rules (%d rules) ===%b\n' "${COLOR_BOLD}" "${count}" "${COLOR_RESET}"

    # Generate default filename
    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S' 2>/dev/null)" || timestamp="export"
    local default_file="${default_dir}/apotropaios-rules-${timestamp}.conf"

    printf '  Enter output file path\n'
    printf '  [default: %s]: ' "${default_file}"
    local fpath
    read -r fpath </dev/tty 2>/dev/null || return
    fpath="$(sanitize_input "${fpath}")"

    # Use default if empty
    [[ -z "${fpath}" ]] && fpath="${default_file}"

    # Ensure parent directory exists
    local parent_dir
    parent_dir="$(dirname "${fpath}")"
    if [[ ! -d "${parent_dir}" ]]; then
        if util_confirm "Directory '${parent_dir}' does not exist. Create it?"; then
            mkdir -p "${parent_dir}" 2>/dev/null || {
                printf '  %bFailed to create directory: %s%b\n' "${COLOR_RED}" "${parent_dir}" "${COLOR_RESET}"
                return
            }
        else
            printf '  Export cancelled\n'
            return
        fi
    fi

    # Check if file already exists
    if [[ -f "${fpath}" ]]; then
        if ! util_confirm "File already exists. Overwrite?"; then
            printf '  Export cancelled\n'
            return
        fi
    fi

    local _rc=0
    rule_export_file "${fpath}" 2>/dev/null && _rc=0 || _rc=$?
    if [[ "${_rc}" -eq 0 ]]; then
        printf '  %bRules exported to: %s%b\n' "${COLOR_GREEN}" "${fpath}" "${COLOR_RESET}"
        [[ -f "${fpath}.sha256" ]] && printf '  %bChecksum written: %s.sha256%b\n' "${COLOR_DIM}" "${fpath}" "${COLOR_RESET}"
    else
        printf '  %bFailed to export rules (error code: %d)%b\n' "${COLOR_RED}" "${_rc}" "${COLOR_RESET}"
        printf '  %bCheck file path permissions and log for details%b\n' "${COLOR_DIM}" "${COLOR_RESET}"
    fi
}

# ==============================================================================
# _menu_rule_watcher() [INTERNAL]
# Description:  Rule expiry watcher with notification and timer extension.
#               Monitors temporary rules and alerts user when within 10 minutes
#               of expiration. Offers option to extend the timer. ENH-004
# ==============================================================================
_menu_rule_watcher() {
    printf '\n  %b=== Rule Expiry Watcher ===%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  Scanning temporary rules...\n\n'

    local found_temp=0
    local rule_id

    while IFS= read -r rule_id; do
        [[ -z "${rule_id}" ]] && continue

        local -A rd=()
        rule_index_get "${rule_id}" "rd" 2>/dev/null || continue

        [[ "${rd[duration_type]:-}" != "temporary" ]] && continue
        [[ "${rd[state]:-}" != "active" ]] && continue

        found_temp=1

        local remaining
        remaining="$(rule_state_time_remaining "${rule_id}")"
        local human_remaining
        human_remaining="$(util_human_duration "${remaining}")"

        local status_color="${COLOR_GREEN}"
        local alert=""
        if [[ "${remaining}" -le 0 ]]; then
            status_color="${COLOR_RED}"
            alert=" ** EXPIRED **"
        elif [[ "${remaining}" -le 600 ]]; then
            status_color="${COLOR_RED}"
            alert=" ** EXPIRING SOON **"
        elif [[ "${remaining}" -le 1800 ]]; then
            status_color="${COLOR_YELLOW}"
        fi

        printf '  %b%-38s%b %s %b%-12s%b%s\n' \
            "${COLOR_BOLD}" "${rule_id}" "${COLOR_RESET}" \
            "${rd[description]:-no description}" \
            "${status_color}" "${human_remaining}" "${COLOR_RESET}" \
            "${alert}"

    done < <(rule_index_list_ids)

    if [[ "${found_temp}" -eq 0 ]]; then
        printf '  %bNo temporary rules found%b\n' "${COLOR_DIM}" "${COLOR_RESET}"
        return
    fi

    printf '\n  %bOptions:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b1.%b Extend a rule timer\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b2.%b Expire and remove due rules now\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %bb.%b Back\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"

    local wchoice
    read -r wchoice </dev/tty 2>/dev/null || return
    wchoice="$(sanitize_input "${wchoice}")"

    case "${wchoice}" in
        1)
            printf '  Enter Rule ID to extend: '
            local ext_id
            read -r ext_id </dev/tty 2>/dev/null || return
            ext_id="$(sanitize_input "${ext_id}")"

            printf '  Additional time in seconds (60-2592000) [3600]: '
            local ext_time
            read -r ext_time </dev/tty 2>/dev/null || ext_time="3600"
            ext_time="$(sanitize_input "${ext_time:-3600}")"

            if validate_ttl "${ext_time}"; then
                _rule_extend_ttl "${ext_id}" "${ext_time}"
            else
                printf '  %bInvalid TTL value%b\n' "${COLOR_RED}" "${COLOR_RESET}"
            fi
            ;;
        2)
            local expired_count
            rule_check_expired && expired_count=0 || expired_count=$?
            printf '  Processed %d expired rule(s)\n' "${expired_count}"
            ;;
        b|B) return ;;
    esac
}

# ==============================================================================
# _rule_extend_ttl() [INTERNAL]
# Description:  Extend the TTL of a temporary rule. ENH-004
# Parameters:   $1 - Rule ID
#               $2 - Additional seconds to add
# ==============================================================================
_rule_extend_ttl() {
    local rule_id="${1:?}"
    local additional_seconds="${2:?}"

    validate_rule_id "${rule_id}" || {
        printf '  %bInvalid rule ID%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return 1
    }

    # Get current expiry
    local current_expires="${_RULE_STATE_EXPIRES[${rule_id}]:-0}"
    if [[ "${current_expires}" -eq 0 ]]; then
        printf '  %bRule is not a temporary rule or has no expiry set%b\n' "${COLOR_RED}" "${COLOR_RESET}"
        return 1
    fi

    local now_epoch
    now_epoch="$(util_timestamp_epoch)"
    local new_expires

    # If already expired, extend from now
    if [[ "${current_expires}" -le "${now_epoch}" ]]; then
        new_expires=$((now_epoch + additional_seconds))
    else
        new_expires=$((current_expires + additional_seconds))
    fi

    # Update state
    _RULE_STATE_EXPIRES["${rule_id}"]="${new_expires}"
    local new_ttl=$((new_expires - now_epoch))
    _RULE_STATE_TTL["${rule_id}"]="${new_ttl}"

    # Update index
    local new_expires_ts
    new_expires_ts="$(date -u -d @"${new_expires}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || new_expires_ts="${new_expires}"
    rule_index_update_field "${rule_id}" "expires_at" "${new_expires_ts}" 2>/dev/null || true
    rule_index_update_field "${rule_id}" "ttl" "${new_ttl}" 2>/dev/null || true

    # If rule was expired/inactive, re-activate it
    local state="${_RULE_STATE_MAP[${rule_id}]:-}"
    if [[ "${state}" == "expired" ]] || [[ "${state}" == "inactive" ]]; then
        rule_activate "${rule_id}" 2>/dev/null && \
            printf '  %bRule re-activated%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
    fi

    # Persist state
    _rule_state_save 2>/dev/null || true

    log_info "rule_watcher" "TTL extended for rule ${rule_id}: +${additional_seconds}s, new_expiry=${new_expires_ts}"
    printf '  %bTimer extended: %s remaining%b\n' "${COLOR_GREEN}" "$(util_human_duration "${new_ttl}")" "${COLOR_RESET}"
}

# ==============================================================================
# _menu_backend_config() [INTERNAL]
# Description:  Backend-specific configuration management. Presents options
#               relevant to the currently selected firewall backend including
#               config file inspection, creation, and specialized settings.
# ==============================================================================
_menu_backend_config() {
    if ! _fw_require_backend; then
        return
    fi

    local backend="${FW_ACTIVE_BACKEND}"

    printf '\n'
    util_print_separator "─" 60
    printf '  %b BACKEND CONFIGURATION: %s %b\n' "${COLOR_BOLD}" "${backend}" "${COLOR_RESET}"
    util_print_separator "─" 60

    case "${backend}" in
        ipset)     _menu_backend_config_ipset ;;
        iptables)  _menu_backend_config_iptables ;;
        nftables)  _menu_backend_config_nftables ;;
        firewalld) _menu_backend_config_firewalld ;;
        ufw)       _menu_backend_config_ufw ;;
        *)
            printf '  %bNo backend-specific configuration for: %s%b\n' "${COLOR_YELLOW}" "${backend}" "${COLOR_RESET}"
            ;;
    esac
}

# ==============================================================================
# _menu_backend_config_ipset() [INTERNAL]
# Description:  IPSet-specific configuration options.
# ==============================================================================
_menu_backend_config_ipset() {
    local ipset_conf="/etc/ipset.conf"
    local choice=""

    while true; do
        printf '\n  %b IPSet Configuration %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        util_print_separator "─" 55
        printf '  %b1.%b Check for ipset config (%s)\n' "${COLOR_BOLD}" "${COLOR_RESET}" "${ipset_conf}"
        printf '  %b2.%b View current ipset config\n'   "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b3.%b Create/save ipset config\n'    "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b4.%b Load ipset config\n'           "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b5.%b List all active sets\n'        "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b6.%b Create new empty set\n'        "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b7.%b Flush all sets\n'              "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %bb.%b Back\n'                        "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '\n  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"
        read -r choice </dev/tty 2>/dev/null || choice="b"
        choice="$(sanitize_input "${choice}")"

        case "${choice}" in
            1)
                printf '\n  %bChecking: %s%b\n' "${COLOR_BOLD}" "${ipset_conf}" "${COLOR_RESET}"
                if [[ -f "${ipset_conf}" ]]; then
                    local fsize
                    fsize="$(stat -c%s "${ipset_conf}" 2>/dev/null)" || fsize=0
                    local fdate
                    fdate="$(stat -c '%y' "${ipset_conf}" 2>/dev/null | cut -d'.' -f1)" || fdate="unknown"
                    local fperms
                    fperms="$(stat -c '%a' "${ipset_conf}" 2>/dev/null)" || fperms="unknown"
                    local set_count
                    set_count="$(grep -c 'create ' "${ipset_conf}" 2>/dev/null)" || set_count=0
                    printf '  %bConfig found%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                    printf '    Size:        %s\n' "$(util_human_bytes "${fsize}")"
                    printf '    Modified:    %s\n' "${fdate}"
                    printf '    Permissions: %s\n' "${fperms}"
                    printf '    Sets defined: %d\n' "${set_count}"
                else
                    printf '  %bConfig not found: %s%b\n' "${COLOR_YELLOW}" "${ipset_conf}" "${COLOR_RESET}"
                    printf '  Use option 3 to create one from current active sets.\n'
                fi
                ;;
            2)
                if [[ -f "${ipset_conf}" ]]; then
                    printf '\n  %b--- %s ---%b\n' "${COLOR_DIM}" "${ipset_conf}" "${COLOR_RESET}"
                    cat "${ipset_conf}" 2>/dev/null || printf '  %bCannot read config%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                    printf '  %b--- end ---%b\n' "${COLOR_DIM}" "${COLOR_RESET}"
                else
                    printf '  %bConfig file does not exist%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                fi
                ;;
            3)
                printf '  Save current ipset state to [%s]: ' "${ipset_conf}"
                local save_path
                read -r save_path </dev/tty 2>/dev/null || save_path=""
                save_path="$(sanitize_input "${save_path}")"
                [[ -z "${save_path}" ]] && save_path="${ipset_conf}"
                local output
                output="$(ipset save 2>&1)" || true
                if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
                    printf '  %bRoot privileges required to save ipset config%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                elif [[ -z "${output}" ]]; then
                    printf '  %bNo active ipsets to save%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                else
                    printf '%s\n' "${output}" > "${save_path}" 2>/dev/null && {
                        chmod 600 "${save_path}" 2>/dev/null || true
                        printf '  %bIPSet config saved to: %s%b\n' "${COLOR_GREEN}" "${save_path}" "${COLOR_RESET}"
                    } || {
                        printf '  %bFailed to write config file%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                    }
                fi
                ;;
            4)
                if [[ ! -f "${ipset_conf}" ]]; then
                    printf '  %bConfig file not found: %s%b\n' "${COLOR_RED}" "${ipset_conf}" "${COLOR_RESET}"
                else
                    if util_confirm "Load ipset config from ${ipset_conf}? This may modify active sets"; then
                        local output
                        output="$(ipset restore < "${ipset_conf}" 2>&1)" || true
                        if [[ -n "${output}" ]]; then
                            printf '  %b%s%b\n' "${COLOR_RED}" "${output}" "${COLOR_RESET}"
                        else
                            printf '  %bIPSet config loaded successfully%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                        fi
                    fi
                fi
                ;;
            5)
                printf '\n'
                local output
                output="$(ipset list -t 2>&1)" || true
                if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
                    printf '  %bRoot privileges required%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                elif [[ -z "${output}" ]]; then
                    printf '  %bNo active ipsets%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                else
                    printf '%s\n' "${output}"
                fi
                ;;
            6)
                printf '  Set name: '
                local sname; read -r sname </dev/tty 2>/dev/null || continue
                sname="$(sanitize_input "${sname}")"
                [[ -z "${sname}" ]] && { printf '  %bInvalid input: Set name cannot be empty%b\n' "${COLOR_RED}" "${COLOR_RESET}"; continue; }
                printf '  Set type (hash:ip/hash:net/hash:ip,port) [hash:net]: '
                local stype; read -r stype </dev/tty 2>/dev/null || stype="hash:net"
                stype="$(sanitize_input "${stype:-hash:net}")"
                local output
                output="$(ipset create "${sname}" "${stype}" 2>&1)" || true
                if [[ -n "${output}" ]]; then
                    printf '  %b%s%b\n' "${COLOR_RED}" "${output}" "${COLOR_RESET}"
                else
                    printf '  %bSet created: %s (%s)%b\n' "${COLOR_GREEN}" "${sname}" "${stype}" "${COLOR_RESET}"
                fi
                ;;
            7)
                if util_confirm "Flush ALL ipset sets? This removes all entries"; then
                    local output
                    output="$(ipset flush 2>&1)" || true
                    if [[ -n "${output}" ]]; then
                        printf '  %b%s%b\n' "${COLOR_RED}" "${output}" "${COLOR_RESET}"
                    else
                        printf '  %bAll sets flushed%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                    fi
                fi
                ;;
            b|B) return ;;
            *) printf '  %bInvalid option%b\n' "${COLOR_RED}" "${COLOR_RESET}" ;;
        esac
    done
}

# ==============================================================================
# _menu_backend_config_iptables() [INTERNAL]
# ==============================================================================
_menu_backend_config_iptables() {
    local iptables_conf="/etc/iptables/rules.v4"
    local iptables_conf_alt="/etc/sysconfig/iptables"
    # Use whichever exists
    [[ ! -f "${iptables_conf}" ]] && [[ -f "${iptables_conf_alt}" ]] && iptables_conf="${iptables_conf_alt}"

    local choice=""
    while true; do
        printf '\n  %b iptables Configuration %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        util_print_separator "─" 55
        printf '  %b1.%b Check for saved rules (%s)\n'    "${COLOR_BOLD}" "${COLOR_RESET}" "${iptables_conf}"
        printf '  %b2.%b View saved rules file\n'          "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b3.%b Save current rules to file\n'     "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b4.%b Restore rules from file\n'        "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b5.%b Show active table summary\n'      "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b6.%b Show chain policies\n'            "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %bb.%b Back\n'                            "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '\n  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"
        read -r choice </dev/tty 2>/dev/null || choice="b"
        choice="$(sanitize_input "${choice}")"

        case "${choice}" in
            1)
                printf '\n  %bChecking: %s%b\n' "${COLOR_BOLD}" "${iptables_conf}" "${COLOR_RESET}"
                if [[ -f "${iptables_conf}" ]]; then
                    local fsize fdate rule_count
                    fsize="$(stat -c%s "${iptables_conf}" 2>/dev/null)" || fsize=0
                    fdate="$(stat -c '%y' "${iptables_conf}" 2>/dev/null | cut -d'.' -f1)" || fdate="unknown"
                    rule_count="$(grep -c '^-A ' "${iptables_conf}" 2>/dev/null)" || rule_count=0
                    printf '  %bRules file found%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                    printf '    Size:        %s\n' "$(util_human_bytes "${fsize}")"
                    printf '    Modified:    %s\n' "${fdate}"
                    printf '    Rule lines:  %d\n' "${rule_count}"
                else
                    printf '  %bNo saved rules file found at: %s%b\n' "${COLOR_YELLOW}" "${iptables_conf}" "${COLOR_RESET}"
                fi
                ;;
            2)
                if [[ -f "${iptables_conf}" ]]; then
                    printf '\n  %b--- %s ---%b\n' "${COLOR_DIM}" "${iptables_conf}" "${COLOR_RESET}"
                    cat "${iptables_conf}" 2>/dev/null || printf '  %bCannot read file%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                    printf '  %b--- end ---%b\n' "${COLOR_DIM}" "${COLOR_RESET}"
                else
                    printf '  %bFile does not exist%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                fi
                ;;
            3)
                printf '  Save to [%s]: ' "${iptables_conf}"
                local sp; read -r sp </dev/tty 2>/dev/null || sp=""
                sp="$(sanitize_input "${sp}")"
                [[ -z "${sp}" ]] && sp="${iptables_conf}"
                local output
                output="$(iptables-save 2>&1)" || true
                if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
                    printf '  %bRoot privileges required%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                else
                    local parent; parent="$(dirname "${sp}")"
                    mkdir -p "${parent}" 2>/dev/null || true
                    printf '%s\n' "${output}" > "${sp}" 2>/dev/null && {
                        chmod 600 "${sp}" 2>/dev/null || true
                        printf '  %bRules saved to: %s%b\n' "${COLOR_GREEN}" "${sp}" "${COLOR_RESET}"
                    } || printf '  %bFailed to write file%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                fi
                ;;
            4)
                if [[ ! -f "${iptables_conf}" ]]; then
                    printf '  %bNo saved rules file found%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                elif util_confirm "Restore iptables rules from ${iptables_conf}?"; then
                    local output
                    output="$(iptables-restore < "${iptables_conf}" 2>&1)" || true
                    if [[ -n "${output}" ]]; then
                        printf '  %b%s%b\n' "${COLOR_RED}" "${output}" "${COLOR_RESET}"
                    else
                        printf '  %bRules restored successfully%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                    fi
                fi
                ;;
            5)
                local output
                output="$(iptables -L -n --line-numbers 2>&1)" || true
                if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
                    printf '  %bRoot privileges required%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                else
                    printf '\n%s\n' "${output}"
                fi
                ;;
            6)
                for tbl in filter nat mangle raw; do
                    local output
                    output="$(iptables -t "${tbl}" -L -n 2>&1 | head -3)" || true
                    if [[ "${output}" != *"Permission denied"* ]] && [[ "${output}" != *"Operation not permitted"* ]]; then
                        printf '  %b%-8s%b %s\n' "${COLOR_BOLD}" "${tbl}:" "${COLOR_RESET}" "$(echo "${output}" | head -1)"
                    fi
                done
                ;;
            b|B) return ;;
            *) printf '  %bInvalid option%b\n' "${COLOR_RED}" "${COLOR_RESET}" ;;
        esac
    done
}

# ==============================================================================
# _menu_backend_config_nftables() [INTERNAL]
# ==============================================================================
_menu_backend_config_nftables() {
    local nft_conf="/etc/nftables.conf"
    local choice=""
    while true; do
        printf '\n  %b nftables Configuration %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        util_print_separator "─" 55
        printf '  %b1.%b Check for nftables config (%s)\n' "${COLOR_BOLD}" "${COLOR_RESET}" "${nft_conf}"
        printf '  %b2.%b View config file\n'                "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b3.%b Save current ruleset to config\n'  "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b4.%b List all tables\n'                  "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b5.%b List all chains\n'                  "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %bb.%b Back\n'                              "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '\n  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"
        read -r choice </dev/tty 2>/dev/null || choice="b"
        choice="$(sanitize_input "${choice}")"

        case "${choice}" in
            1)
                printf '\n  %bChecking: %s%b\n' "${COLOR_BOLD}" "${nft_conf}" "${COLOR_RESET}"
                if [[ -f "${nft_conf}" ]]; then
                    local fsize fdate
                    fsize="$(stat -c%s "${nft_conf}" 2>/dev/null)" || fsize=0
                    fdate="$(stat -c '%y' "${nft_conf}" 2>/dev/null | cut -d'.' -f1)" || fdate="unknown"
                    printf '  %bConfig found%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                    printf '    Size:     %s\n' "$(util_human_bytes "${fsize}")"
                    printf '    Modified: %s\n' "${fdate}"
                else
                    printf '  %bConfig not found: %s%b\n' "${COLOR_YELLOW}" "${nft_conf}" "${COLOR_RESET}"
                fi
                ;;
            2)
                if [[ -f "${nft_conf}" ]]; then
                    printf '\n  %b--- %s ---%b\n' "${COLOR_DIM}" "${nft_conf}" "${COLOR_RESET}"
                    cat "${nft_conf}" 2>/dev/null || printf '  %bCannot read%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                    printf '  %b--- end ---%b\n' "${COLOR_DIM}" "${COLOR_RESET}"
                else
                    printf '  %bFile does not exist%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                fi
                ;;
            3)
                printf '  Save to [%s]: ' "${nft_conf}"
                local sp; read -r sp </dev/tty 2>/dev/null || sp=""
                sp="$(sanitize_input "${sp}")"
                [[ -z "${sp}" ]] && sp="${nft_conf}"
                local output
                output="$(nft list ruleset 2>&1)" || true
                if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
                    printf '  %bRoot privileges required%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                else
                    printf '%s\n' "${output}" > "${sp}" 2>/dev/null && {
                        chmod 600 "${sp}" 2>/dev/null || true
                        printf '  %bRuleset saved to: %s%b\n' "${COLOR_GREEN}" "${sp}" "${COLOR_RESET}"
                    } || printf '  %bFailed to write file%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                fi
                ;;
            4)
                local output
                output="$(nft list tables 2>&1)" || true
                if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
                    printf '  %bRoot privileges required%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                elif [[ -z "${output}" ]]; then
                    printf '  %bNo tables defined%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                else
                    printf '\n%s\n' "${output}"
                fi
                ;;
            5)
                local output
                output="$(nft list chains 2>&1)" || true
                if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
                    printf '  %bRoot privileges required%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                elif [[ -z "${output}" ]]; then
                    printf '  %bNo chains defined%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                else
                    printf '\n%s\n' "${output}"
                fi
                ;;
            b|B) return ;;
            *) printf '  %bInvalid option%b\n' "${COLOR_RED}" "${COLOR_RESET}" ;;
        esac
    done
}

# ==============================================================================
# _menu_backend_config_firewalld() [INTERNAL]
# ==============================================================================
_menu_backend_config_firewalld() {
    local choice=""
    while true; do
        printf '\n  %b firewalld Configuration %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        util_print_separator "─" 55
        printf '  %b1.%b Show default zone\n'         "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b2.%b List all zones\n'             "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b3.%b Show active zones\n'          "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b4.%b List services in default zone\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b5.%b Show rich rules\n'            "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b6.%b Check runtime vs permanent\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %bb.%b Back\n'                        "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '\n  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"
        read -r choice </dev/tty 2>/dev/null || choice="b"
        choice="$(sanitize_input "${choice}")"

        case "${choice}" in
            1)
                local output
                output="$(firewall-cmd --get-default-zone 2>&1)" || true
                if [[ "${output}" == *"not running"* ]]; then
                    printf '  %bfirewalld is not running%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                else
                    printf '  Default zone: %b%s%b\n' "${COLOR_GREEN}" "${output}" "${COLOR_RESET}"
                fi
                ;;
            2)
                local output
                output="$(firewall-cmd --get-zones 2>&1)" || true
                printf '  Available zones: %s\n' "${output}"
                ;;
            3)
                local output
                output="$(firewall-cmd --get-active-zones 2>&1)" || true
                if [[ -n "${output}" ]]; then
                    printf '\n%s\n' "${output}"
                else
                    printf '  %bNo active zones%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                fi
                ;;
            4)
                local output
                output="$(firewall-cmd --list-services 2>&1)" || true
                printf '  Services: %s\n' "${output}"
                ;;
            5)
                local output
                output="$(firewall-cmd --list-rich-rules 2>&1)" || true
                if [[ -n "${output}" ]]; then
                    printf '\n  %bRich rules:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
                    printf '%s\n' "${output}"
                else
                    printf '  %bNo rich rules configured%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                fi
                ;;
            6)
                printf '\n  %bRuntime config:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
                firewall-cmd --list-all 2>/dev/null || printf '  Cannot query runtime\n'
                printf '\n  %bPermanent config:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
                firewall-cmd --permanent --list-all 2>/dev/null || printf '  Cannot query permanent\n'
                ;;
            b|B) return ;;
            *) printf '  %bInvalid option%b\n' "${COLOR_RED}" "${COLOR_RESET}" ;;
        esac
    done
}

# ==============================================================================
# _menu_backend_config_ufw() [INTERNAL]
# Description:  UFW-specific configuration options including application profile
#               management, logging level adjustment, and defaults management.
# ==============================================================================
_menu_backend_config_ufw() {
    local ufw_defaults="/etc/default/ufw"
    local ufw_rules_dir="/etc/ufw"
    local ufw_apps_dir="/etc/ufw/applications.d"
    local choice=""
    while true; do
        printf '\n  %b UFW Configuration %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        util_print_separator "─" 55
        printf '  %b1.%b Check UFW defaults (%s)\n'         "${COLOR_BOLD}" "${COLOR_RESET}" "${ufw_defaults}"
        printf '  %b2.%b View UFW defaults\n'                "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b3.%b Show application profiles\n'        "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b4.%b Enable application profile\n'       "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b5.%b Disable application profile\n'      "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b6.%b Show logging level\n'               "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b7.%b Set logging level\n'                "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b8.%b List UFW config files\n'            "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b9.%b Set default policies\n'             "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %bb.%b Back\n'                              "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '\n  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"
        read -r choice </dev/tty 2>/dev/null || choice="b"
        choice="$(sanitize_input "${choice}")"

        case "${choice}" in
            1)
                if [[ -f "${ufw_defaults}" ]]; then
                    local incoming outgoing forwarding
                    incoming="$(grep '^DEFAULT_INPUT_POLICY=' "${ufw_defaults}" 2>/dev/null | cut -d'=' -f2 | tr -d '"')" || incoming="unknown"
                    outgoing="$(grep '^DEFAULT_OUTPUT_POLICY=' "${ufw_defaults}" 2>/dev/null | cut -d'=' -f2 | tr -d '"')" || outgoing="unknown"
                    forwarding="$(grep '^DEFAULT_FORWARD_POLICY=' "${ufw_defaults}" 2>/dev/null | cut -d'=' -f2 | tr -d '"')" || forwarding="unknown"
                    printf '  %bUFW defaults found%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                    printf '    Default input:    %s\n' "${incoming}"
                    printf '    Default output:   %s\n' "${outgoing}"
                    printf '    Default forward:  %s\n' "${forwarding}"
                else
                    printf '  %bUFW defaults not found: %s%b\n' "${COLOR_YELLOW}" "${ufw_defaults}" "${COLOR_RESET}"
                fi
                ;;
            2)
                if [[ -f "${ufw_defaults}" ]]; then
                    printf '\n  %b--- %s ---%b\n' "${COLOR_DIM}" "${ufw_defaults}" "${COLOR_RESET}"
                    cat "${ufw_defaults}" 2>/dev/null || printf '  Cannot read\n'
                    printf '  %b--- end ---%b\n' "${COLOR_DIM}" "${COLOR_RESET}"
                else
                    printf '  %bFile does not exist%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                fi
                ;;
            3)
                # List available application profiles
                printf '\n  %bAvailable Application Profiles:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
                util_print_separator "─" 55
                local output
                output="$(ufw app list 2>&1)" || true
                if [[ "${output}" == *"Permission denied"* ]] || [[ "${output}" == *"Operation not permitted"* ]]; then
                    printf '  %bRoot privileges required%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                elif [[ -n "${output}" ]]; then
                    printf '%s\n' "${output}"
                    # Show detail for each app
                    printf '\n  %bProfile Details:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
                    local app_name
                    while IFS= read -r app_name; do
                        [[ -z "${app_name}" ]] && continue
                        [[ "${app_name}" == "Available"* ]] && continue
                        app_name="$(util_trim "${app_name}")"
                        [[ -z "${app_name}" ]] && continue
                        local detail
                        detail="$(ufw app info "${app_name}" 2>/dev/null)" || continue
                        local ports
                        ports="$(echo "${detail}" | grep 'Ports:' | sed 's/.*Ports: //')" || ports="unknown"
                        printf '    %-24s %s\n' "${app_name}" "${ports}"
                    done <<< "${output}"
                else
                    printf '  %bNo application profiles found%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                fi
                ;;
            4)
                # Enable/allow an application profile
                printf '\n'
                local output
                output="$(ufw app list 2>&1)" || true
                if [[ -z "${output}" ]] || [[ "${output}" == *"Permission denied"* ]]; then
                    printf '  %bCannot list applications%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                    continue
                fi
                printf '%s\n' "${output}"

                # Build a selectable list of detected apps
                local -a app_list=()
                local idx=1
                local app_name
                while IFS= read -r app_name; do
                    app_name="$(util_trim "${app_name}")"
                    [[ -z "${app_name}" ]] && continue
                    [[ "${app_name}" == "Available"* ]] && continue
                    app_list+=("${app_name}")
                    printf '  %b%2d.%b %s\n' "${COLOR_BOLD}" "${idx}" "${COLOR_RESET}" "${app_name}"
                    ((idx++)) || true
                done <<< "${output}"

                if [[ "${#app_list[@]}" -eq 0 ]]; then
                    printf '  %bNo application profiles detected%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                    continue
                fi

                printf '\n  %bSelect profile to enable [1-%d] (or b to cancel):%b ' "${COLOR_CYAN}" "${#app_list[@]}" "${COLOR_RESET}"
                local asel
                read -r asel </dev/tty 2>/dev/null || continue
                asel="$(sanitize_input "${asel}")"
                [[ "${asel}" == "b" || "${asel}" == "B" ]] && continue

                if validate_numeric "${asel}" 1 "${#app_list[@]}"; then
                    local aidx=$((asel - 1))
                    local selected_app="${app_list[${aidx}]}"
                    printf '  Enabling: %s\n' "${selected_app}"
                    local result
                    result="$(ufw allow "${selected_app}" 2>&1)" || true
                    if [[ "${result}" == *"Rule added"* ]] || [[ "${result}" == *"updated"* ]] || [[ "${result}" == *"existing"* ]]; then
                        printf '  %bApplication profile enabled: %s%b\n' "${COLOR_GREEN}" "${selected_app}" "${COLOR_RESET}"
                    else
                        printf '  %b%s%b\n' "${COLOR_RED}" "${result}" "${COLOR_RESET}"
                    fi
                else
                    printf '  %bInvalid selection%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                fi
                ;;
            5)
                # Disable/deny an application profile
                printf '\n'
                local output
                output="$(ufw app list 2>&1)" || true
                local -a app_list=()
                local idx=1
                local app_name
                while IFS= read -r app_name; do
                    app_name="$(util_trim "${app_name}")"
                    [[ -z "${app_name}" ]] && continue
                    [[ "${app_name}" == "Available"* ]] && continue
                    app_list+=("${app_name}")
                    printf '  %b%2d.%b %s\n' "${COLOR_BOLD}" "${idx}" "${COLOR_RESET}" "${app_name}"
                    ((idx++)) || true
                done <<< "${output}"

                if [[ "${#app_list[@]}" -eq 0 ]]; then
                    printf '  %bNo application profiles detected%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                    continue
                fi

                printf '\n  %bSelect profile to disable [1-%d] (or b to cancel):%b ' "${COLOR_CYAN}" "${#app_list[@]}" "${COLOR_RESET}"
                local asel
                read -r asel </dev/tty 2>/dev/null || continue
                asel="$(sanitize_input "${asel}")"
                [[ "${asel}" == "b" || "${asel}" == "B" ]] && continue

                if validate_numeric "${asel}" 1 "${#app_list[@]}"; then
                    local aidx=$((asel - 1))
                    local selected_app="${app_list[${aidx}]}"
                    if util_confirm "Delete rules for '${selected_app}'?"; then
                        local result
                        result="$(ufw delete allow "${selected_app}" 2>&1)" || true
                        printf '  %b%s%b\n' "${COLOR_GREEN}" "${result:-Profile rules removed}" "${COLOR_RESET}"
                    fi
                else
                    printf '  %bInvalid selection%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                fi
                ;;
            6)
                local output
                output="$(ufw status verbose 2>&1)" || true
                local logging_line
                logging_line="$(echo "${output}" | grep -i 'logging')" || logging_line=""
                if [[ -n "${logging_line}" ]]; then
                    printf '  %s\n' "${logging_line}"
                else
                    printf '  %bCannot determine logging level%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                fi
                ;;
            7)
                printf '\n  %bUFW Logging Levels:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
                printf '  %b1.%b off     — No logging\n'                     "${COLOR_BOLD}" "${COLOR_RESET}"
                printf '  %b2.%b low     — Log blocked packets not matching default policy\n' "${COLOR_BOLD}" "${COLOR_RESET}"
                printf '  %b3.%b medium  — Low + invalid + new connections not matching policy\n' "${COLOR_BOLD}" "${COLOR_RESET}"
                printf '  %b4.%b high    — Medium + all packets with rate limiting\n' "${COLOR_BOLD}" "${COLOR_RESET}"
                printf '  %b5.%b full    — All packets without rate limiting\n' "${COLOR_BOLD}" "${COLOR_RESET}"

                printf '\n  %bSelect level [1-5]:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"
                local lsel
                read -r lsel </dev/tty 2>/dev/null || continue
                lsel="$(sanitize_input "${lsel}")"

                local level_name=""
                case "${lsel}" in
                    1) level_name="off" ;;
                    2) level_name="low" ;;
                    3) level_name="medium" ;;
                    4) level_name="high" ;;
                    5) level_name="full" ;;
                    *) printf '  %bInvalid selection%b\n' "${COLOR_RED}" "${COLOR_RESET}"; continue ;;
                esac

                local result
                result="$(ufw logging "${level_name}" 2>&1)" || true
                if [[ "${result}" == *"changed"* ]] || [[ "${result}" == *"Logging"* ]]; then
                    printf '  %bLogging level set to: %s%b\n' "${COLOR_GREEN}" "${level_name}" "${COLOR_RESET}"
                else
                    printf '  %b%s%b\n' "${COLOR_RED}" "${result:-Failed to set logging level}" "${COLOR_RESET}"
                fi
                ;;
            8)
                if [[ -d "${ufw_rules_dir}" ]]; then
                    printf '\n  %bUFW config files in %s:%b\n' "${COLOR_BOLD}" "${ufw_rules_dir}" "${COLOR_RESET}"
                    ls -la "${ufw_rules_dir}"/ 2>/dev/null
                    if [[ -d "${ufw_apps_dir}" ]]; then
                        printf '\n  %bApplication profiles in %s:%b\n' "${COLOR_BOLD}" "${ufw_apps_dir}" "${COLOR_RESET}"
                        ls -la "${ufw_apps_dir}"/ 2>/dev/null
                    fi
                else
                    printf '  %bUFW config directory not found%b\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
                fi
                ;;
            9)
                printf '\n  %bSet Default Policies%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
                printf '  Incoming default (allow/deny/reject) [deny]: '
                local in_pol
                read -r in_pol </dev/tty 2>/dev/null || in_pol="deny"
                in_pol="$(util_to_lower "$(sanitize_input "${in_pol:-deny}")")"

                printf '  Outgoing default (allow/deny/reject) [allow]: '
                local out_pol
                read -r out_pol </dev/tty 2>/dev/null || out_pol="allow"
                out_pol="$(util_to_lower "$(sanitize_input "${out_pol:-allow}")")"

                printf '  Routed/forwarded default (allow/deny/reject) [deny]: '
                local fwd_pol
                read -r fwd_pol </dev/tty 2>/dev/null || fwd_pol="deny"
                fwd_pol="$(util_to_lower "$(sanitize_input "${fwd_pol:-deny}")")"

                if util_confirm "Set defaults: incoming=${in_pol}, outgoing=${out_pol}, routed=${fwd_pol}?"; then
                    local r1 r2 r3
                    r1="$(ufw default "${in_pol}" incoming 2>&1)" || true
                    r2="$(ufw default "${out_pol}" outgoing 2>&1)" || true
                    r3="$(ufw default "${fwd_pol}" routed 2>&1)" || true
                    printf '  Incoming:  %s\n' "${r1}"
                    printf '  Outgoing:  %s\n' "${r2}"
                    printf '  Routed:    %s\n' "${r3}"
                    printf '  %bDefault policies updated%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                fi
                ;;
            b|B) return ;;
            *) printf '  %bInvalid option%b\n' "${COLOR_RED}" "${COLOR_RESET}" ;;
        esac
    done
}

# ==============================================================================
# menu_rule_quick_actions()
# ==============================================================================
menu_rule_quick_actions() {
    printf '\n'
    util_print_separator "─" 50
    printf '  %b QUICK ACTIONS %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    util_print_separator "─" 50
    printf '  %b1.%b Block ALL traffic (inbound + outbound)\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %b2.%b Allow ALL traffic (inbound + outbound)\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %bb.%b Back\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '\n  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"

    local choice
    read -r choice </dev/tty 2>/dev/null || return
    choice="$(sanitize_input "${choice}")"

    case "${choice}" in
        1)
            if util_confirm "BLOCK ALL traffic? This will drop all network connections"; then
                backup_create_restore_point "pre_block_all" || true
                if _fw_require_backend; then
                    rule_block_all_traffic && printf '  %bAll traffic blocked%b\n' "${COLOR_RED}" "${COLOR_RESET}"
                fi
            fi
            ;;
        2)
            if util_confirm "ALLOW ALL traffic? This removes all firewall restrictions"; then
                if _fw_require_backend; then
                    rule_allow_all_traffic && printf '  %bAll traffic allowed%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                fi
            fi
            ;;
        b|B) return ;;
    esac
}

# ==============================================================================
# menu_backup_management()
# ==============================================================================
menu_backup_management() {
    local choice=""
    while true; do
        printf '\n'
        util_print_separator "─" 50
        printf '  %b BACKUP & RECOVERY %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
        util_print_separator "─" 50
        printf '  %b1.%b Create backup\n'               "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b2.%b List backups\n'                 "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b3.%b Restore from backup\n'          "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b4.%b Create immutable snapshot\n'    "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b5.%b List immutable snapshots\n'     "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %b6.%b Verify immutable snapshots\n'   "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '  %bb.%b Back\n'                          "${COLOR_BOLD}" "${COLOR_RESET}"
        printf '\n  %bChoice:%b ' "${COLOR_CYAN}" "${COLOR_RESET}"
        read -r choice </dev/tty 2>/dev/null || choice="b"
        choice="$(sanitize_input "${choice}")"

        case "${choice}" in
            1)
                printf '  Label (optional): '
                local lbl; read -r lbl </dev/tty 2>/dev/null || lbl="manual"
                backup_create "$(sanitize_input "${lbl:-manual}")" && \
                    printf '  %bBackup created%b\n' "${COLOR_GREEN}" "${COLOR_RESET}"
                ;;
            2) backup_list ;;
            3)
                printf '  Backup file path: '
                local bf; read -r bf </dev/tty 2>/dev/null || return
                bf="$(sanitize_input "${bf}")"
                backup_restore "${bf}"
                ;;
            4)
                printf '  Snapshot label: '
                local sl; read -r sl </dev/tty 2>/dev/null || sl="manual"
                immutable_create "$(sanitize_input "${sl:-manual}")"
                ;;
            5) immutable_list ;;
            6) immutable_verify && printf '  %bAll snapshots verified%b\n' "${COLOR_GREEN}" "${COLOR_RESET}" ;;
            b|B) return ;;
        esac
    done
}

# ==============================================================================
# menu_system_info()
# ==============================================================================
menu_system_info() {
    printf '\n'
    util_print_separator "─" 60
    printf '  %b SYSTEM INFORMATION %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    util_print_separator "─" 60

    printf '\n  %bOperating System:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    os_get_info

    # Re-detect firewalls for fresh status
    fw_detect_all 2>/dev/null || true
    fw_get_info

    printf '\n  %bFramework:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    util_print_kv "Version" "${APOTROPAIOS_VERSION}"
    util_print_kv "Active Backend" "${FW_ACTIVE_BACKEND:-none}"
    util_print_kv "Rules Tracked" "$(rule_index_count 2>/dev/null || echo 0)"
    util_print_kv "Log File" "$(log_get_file)"
    util_print_kv "Log Level" "$(log_get_level)"

    printf '\n  Press Enter to continue...'
    read -r </dev/tty 2>/dev/null || true
}

# ==============================================================================
# menu_install_management()
# ==============================================================================
menu_install_management() {
    printf '\n'
    util_print_separator "─" 50
    printf '  %b INSTALL & UPDATE %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    util_print_separator "─" 50

    local i=1
    local fw
    for fw in "${SUPPORTED_FW_LIST[@]}"; do
        local status=""
        if fw_is_installed "${fw}"; then
            status="${COLOR_GREEN}installed${COLOR_RESET}"
        else
            status="${COLOR_YELLOW}not installed${COLOR_RESET}"
        fi
        printf '  %b%d.%b %-12s [%b]\n' "${COLOR_BOLD}" "${i}" "${COLOR_RESET}" "${fw}" "${status}"
        ((i++)) || true
    done
    printf '  %bb.%b Back\n' "${COLOR_BOLD}" "${COLOR_RESET}"

    printf '\n  Select firewall to install/update [1-%d]: ' "${#SUPPORTED_FW_LIST[@]}"
    local sel; read -r sel </dev/tty 2>/dev/null || return
    sel="$(sanitize_input "${sel}")"
    [[ "${sel}" == "b" ]] && return

    if validate_numeric "${sel}" 1 "${#SUPPORTED_FW_LIST[@]}"; then
        local idx=$((sel - 1))
        local target_fw="${SUPPORTED_FW_LIST[${idx}]}"

        if fw_is_installed "${target_fw}"; then
            if util_confirm "Update ${target_fw}?"; then
                update_firewall "${target_fw}"
            fi
        else
            if util_confirm "Install ${target_fw}?"; then
                install_firewall "${target_fw}" && install_configure_firewall "${target_fw}"
            fi
        fi
    fi
}

# ==============================================================================
# menu_help()
# ==============================================================================
menu_help() {
    printf '\n'
    util_print_separator "─" 60
    printf '  %b HELP & DOCUMENTATION %b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    util_print_separator "─" 60
    printf '\n'
    printf '  %bApotropaios - Firewall Manager v%s%b\n\n' "${COLOR_BOLD}" "${APOTROPAIOS_VERSION}" "${COLOR_RESET}"
    printf '  A unified firewall management framework supporting:\n'
    printf '    - firewalld, ipset, iptables, nftables, ufw\n'
    printf '    - Ubuntu, Kali Linux, Debian 12, Rocky 9, AlmaLinux 9, Arch\n\n'
    printf '  %bCLI Usage:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '    apotropaios.sh [OPTIONS] [COMMAND]\n\n'
    printf '  %bOptions:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '    --help, -h          Show this help\n'
    printf '    --version, -v       Show version\n'
    printf '    --log-level LEVEL   Set log level (trace/debug/info/warning/error/critical)\n'
    printf '    --backend NAME      Set firewall backend\n'
    printf '    --non-interactive   Run without interactive menus\n\n'
    printf '  %bCommands:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '    menu                Start interactive menu (default)\n'
    printf '    detect              Detect OS and firewalls\n'
    printf '    status              Show firewall status\n'
    printf '    block-all           Block all traffic\n'
    printf '    allow-all           Allow all traffic\n'
    printf '    add-rule            Add a rule (with sub-options)\n'
    printf '    list-rules          List all tracked rules\n'
    printf '    system-rules        List all system firewall rules\n'
    printf '    import FILE         Import rules from config file\n'
    printf '    export FILE         Export rules to config file\n'
    printf '    backup [LABEL]      Create a backup\n'
    printf '    restore FILE        Restore from backup\n'
    printf '    install FW_NAME     Install a firewall\n'
    printf '    update FW_NAME      Update a firewall\n\n'
    printf '  %bDocumentation:%b See docs/ directory or wiki at docs/wiki/\n\n' "${COLOR_BOLD}" "${COLOR_RESET}"

    printf '  Press Enter to continue...'
    read -r </dev/tty 2>/dev/null || true
}
