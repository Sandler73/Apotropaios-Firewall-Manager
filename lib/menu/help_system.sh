#!/usr/bin/env bash
# ==============================================================================
# File:         lib/menu/help_system.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Progressive layered help system
# Description:  Provides detailed, context-specific help for every CLI command.
#               Implements a 3-tier help architecture:
#                 Tier 1: Global help (--help) — command overview and options
#                 Tier 2: Command help (COMMAND --help) — full detail per command
#                 Tier 3: Interactive menu help — in-app guidance
#               Each command help includes: synopsis, description, options/args,
#               examples, related commands, and operational notes.
# Notes:        - Requires lib/core/constants.sh, lib/core/utils.sh
#               - Help text uses terminal colors when available
#               - All help functions follow help_cmd_COMMAND() naming convention
#               - No external dependencies
# Version:      1.1.5
# ==============================================================================

[[ -n "${_APOTROPAIOS_HELP_SYSTEM_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_HELP_SYSTEM_LOADED=1

# ==============================================================================
# _help_header() [INTERNAL]
# Description:  Print a standardized help header for a command.
# Parameters:   $1 - Command name
#               $2 - One-line synopsis
# ==============================================================================
_help_header() {
    local cmd="$1"
    local synopsis="$2"
    printf '\n%b%s — %s%b\n' "${COLOR_BOLD}" "${cmd}" "${synopsis}" "${COLOR_RESET}"
    printf '%b%s v%s%b\n' "${COLOR_DIM}" "${APOTROPAIOS_FULL_NAME}" "${APOTROPAIOS_VERSION}" "${COLOR_RESET}"
    util_print_separator "─" 70
}

# ==============================================================================
# _help_section() [INTERNAL]
# Description:  Print a section heading within help output.
# Parameters:   $1 - Section title
# ==============================================================================
_help_section() {
    printf '\n%b%s%b\n' "${COLOR_BOLD}" "$1" "${COLOR_RESET}"
}

# ==============================================================================
# _help_tip() [INTERNAL]
# Description:  Print a tip/note callout.
# Parameters:   $1 - Tip text
# ==============================================================================
_help_tip() {
    printf '  %bTip:%b %s\n' "${COLOR_CYAN}" "${COLOR_RESET}" "$1"
}

# ==============================================================================
# _help_related() [INTERNAL]
# Description:  Print related commands section.
# Parameters:   $@ - Related command strings
# ==============================================================================
_help_related() {
    printf '\n%bRelated Commands:%b\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    local cmd
    for cmd in "$@"; do
        printf '  %s\n' "${cmd}"
    done
}

# ==============================================================================
# help_dispatch()
# Description:  Route to the correct per-command help function.
# Parameters:   $1 - Command name
# Returns:      0 if help displayed, 1 if no help for that command
# ==============================================================================
help_dispatch() {
    local cmd="${1:-}"
    local func_name="help_cmd_${cmd//-/_}"

    if declare -f "${func_name}" &>/dev/null; then
        "${func_name}"
        return 0
    fi

    printf 'No detailed help available for: %s\n' "${cmd}" >&2
    printf 'Run: %s --help  for general usage\n' "$(basename "$0")" >&2
    return 1
}

# ==============================================================================
# help_cmd_menu()
# ==============================================================================
help_cmd_menu() {
    local me
    me="$(basename "$0")"
    _help_header "menu" "Launch the interactive menu interface"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] menu\n' "${me}"
    printf '  %s [OPTIONS]         %b(menu is the default command)%b\n' "${me}" "${COLOR_DIM}" "${COLOR_RESET}"

    _help_section "Description"
    printf '  Launches the full-screen interactive menu-driven interface.\n'
    printf '  The menu provides guided access to all framework features\n'
    printf '  organized into functional categories.\n'

    _help_section "Menu Structure"
    printf '  1. Firewall Management   — Select backend, start/stop, status, list rules\n'
    printf '  2. Rule Management       — Create, list, remove, activate/deactivate rules\n'
    printf '                              Import/export, expiry watcher\n'
    printf '  3. Quick Actions         — One-click block-all or allow-all traffic\n'
    printf '  4. Backup & Recovery     — Create backups, restore, immutable snapshots\n'
    printf '  5. System Information    — OS details, firewall status, framework info\n'
    printf '  6. Install & Update      — Install or update firewall packages\n'
    printf '  7. Help & Documentation  — In-app help reference\n'
    printf '  8. Exit                  — Clean shutdown\n'

    _help_section "Options"
    printf '  --log-level LEVEL   Set verbosity for the session\n'
    printf '  --backend NAME      Pre-select the active firewall backend\n'

    _help_section "Examples"
    printf '  sudo %s                               # Default: launch menu\n' "${me}"
    printf '  sudo %s menu                           # Explicit: launch menu\n' "${me}"
    printf '  sudo %s --backend iptables menu        # Pre-select backend\n' "${me}"
    printf '  sudo %s --log-level trace menu         # Debug mode\n' "${me}"

    _help_section "Navigation"
    printf '  Enter the number of your choice and press Enter.\n'
    printf '  Press Ctrl+C at any time to exit (cleanup handlers will fire).\n'
    printf '  Type "b" or "back" in submenus to return to the previous menu.\n'

    _help_tip "The menu is the recommended starting point for new users."
    _help_tip "All menu operations are also available as CLI commands."

    _help_related \
        "${me} detect              — Quick system scan without entering menu" \
        "${me} --help              — Show all available commands"
    printf '\n'
}

# ==============================================================================
# help_cmd_detect()
# ==============================================================================
help_cmd_detect() {
    local me
    me="$(basename "$0")"
    _help_header "detect" "Detect operating system and installed firewalls"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] detect\n' "${me}"

    _help_section "Description"
    printf '  Performs a comprehensive scan of the system to identify:\n'
    printf '    - Operating system (ID, name, version, family, package manager)\n'
    printf '    - All 5 supported firewall backends with install/version/running status\n'
    printf '  Detection uses multiple fallback methods:\n'
    printf '    1. /etc/os-release (preferred)\n'
    printf '    2. /etc/lsb-release (Ubuntu/Debian fallback)\n'
    printf '    3. /etc/redhat-release (RHEL family fallback)\n'
    printf '    4. uname (last resort)\n'

    _help_section "Output Fields"
    printf '  OS ID             — Canonical identifier (ubuntu, kali, debian, rocky, etc.)\n'
    printf '  OS Name           — Human-readable name\n'
    printf '  OS Version        — Full version string\n'
    printf '  OS Family         — debian, rhel, or arch\n'
    printf '  Package Manager   — apt, dnf, or pacman\n'
    printf '  Supported         — Yes if in the supported OS list\n'
    printf '  Firewall Status   — Installed, version, running/stopped, enabled/disabled\n'

    _help_section "Examples"
    printf '  sudo %s detect\n' "${me}"
    printf '  sudo %s --log-level trace detect   # See all detection steps\n' "${me}"

    _help_tip "Run detect first on a new system to see what is available."
    _help_tip "Detection results inform which backends can be used for rules."

    _help_related \
        "${me} status             — Show detailed status of active backend" \
        "${me} install FW_NAME    — Install a missing firewall"
    printf '\n'
}

# ==============================================================================
# help_cmd_status()
# ==============================================================================
help_cmd_status() {
    local me
    me="$(basename "$0")"
    _help_header "status" "Show detailed status of the active firewall backend"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] status\n' "${me}"
    printf '  %s --backend NAME status\n' "${me}"

    _help_section "Description"
    printf '  Displays the full status and current rule configuration of the\n'
    printf '  active firewall backend. The output format varies by backend:\n'
    printf '    - iptables: Chain listing with packet/byte counters\n'
    printf '    - nftables: Full ruleset in nft syntax\n'
    printf '    - firewalld: Active zone configuration and services\n'
    printf '    - ufw: Status table with numbered rules\n'
    printf '    - ipset: Active sets with member counts\n'

    _help_section "Prerequisites"
    printf '  - Root privileges required (firewall queries need elevated access)\n'
    printf '  - A backend must be selected (auto or via --backend)\n'

    _help_section "Examples"
    printf '  sudo %s status                        # Status of auto-selected backend\n' "${me}"
    printf '  sudo %s --backend iptables status      # Explicit backend\n' "${me}"
    printf '  sudo %s --backend nftables status      # nftables ruleset\n' "${me}"

    _help_tip "Use --backend to check any installed backend, not just the active one."

    _help_related \
        "${me} detect             — Discover all installed backends" \
        "${me} list-rules         — Show Apotropaios-tracked rules" \
        "${me} system-rules       — Audit all native rules across all backends"
    printf '\n'
}

# ==============================================================================
# help_cmd_add_rule()
# ==============================================================================
help_cmd_add_rule() {
    local me
    me="$(basename "$0")"
    _help_header "add-rule" "Create and apply a firewall rule"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] add-rule [RULE-OPTIONS]\n' "${me}"

    _help_section "Description"
    printf '  Creates a new firewall rule, validates all parameters, generates a\n'
    printf '  unique UUID for tracking, applies the rule via the active backend,\n'
    printf '  and records it in the persistent rule index.\n\n'
    printf '  The rule is tagged with a comment (apotropaios:<UUID>) in the backend\n'
    printf '  for targeted management without affecting other rules.\n'

    _help_section "Rule Options"
    printf '  %-22s %s\n' "--direction DIR" "Traffic direction: inbound, outbound, forward [inbound]"
    printf '  %-22s %s\n' "--protocol PROTO" "Protocol: tcp, udp, icmp, icmpv6, sctp, all [tcp]"
    printf '  %-22s %s\n' "--src-ip IP" "Source IP address or CIDR notation"
    printf '  %-22s %s\n' "--dst-ip IP" "Destination IP address or CIDR notation"
    printf '  %-22s %s\n' "--src-port PORT" "Source port number or range (e.g., 1024-65535)"
    printf '  %-22s %s\n' "--dst-port PORT" "Destination port number or range (e.g., 80 or 8080-8090)"
    printf '  %-22s %s\n' "--action ACTION" "Rule action: accept, drop, reject, log, masquerade, return"
    printf '  %-22s %s\n' "" "Compound: log,drop  log,accept  log,reject"
    printf '  %-22s %s\n' "--interface IFACE" "Network interface (e.g., eth0, ens33)"
    printf '  %-22s %s\n' "--duration TYPE" "Rule duration: permanent, temporary [permanent]"
    printf '  %-22s %s\n' "--ttl SECONDS" "Time-to-live for temporary rules (60-2592000)"
    printf '  %-22s %s\n' "--description TEXT" "Human-readable description for the rule"

    _help_section "Connection Tracking"
    printf '  %-22s %s\n' "--conn-state STATES" "Conntrack states: new, established, related, invalid"
    printf '  %-22s %s\n' "" "Comma-separated for multiple: new,established,related"

    _help_section "Logging Options (when action includes log)"
    printf '  %-22s %s\n' "--log-prefix TEXT" "Log message prefix (max 29 chars)"
    printf '  %-22s %s\n' "--log-level LEVEL" "Syslog level: emerg/alert/crit/err/warning/notice/info/debug"

    _help_section "Rate Limiting"
    printf '  %-22s %s\n' "--limit RATE" "Rate limit: N/second, N/minute, N/hour, N/day"
    printf '  %-22s %s\n' "--limit-burst N" "Max burst before limit applies [5]"

    _help_section "Backend-Specific Options"
    printf '  %-22s %s\n' "--zone ZONE" "Firewalld zone name [public]"
    printf '  %-22s %s\n' "--chain CHAIN" "iptables/nftables chain (auto-set from direction if omitted)"
    printf '  %-22s %s\n' "--table TABLE" "iptables table (filter/nat/mangle/raw) or nftables table name"

    _help_section "Validation Rules"
    printf '  - Ports must be 1-65535 (or valid range like 8080-8090)\n'
    printf '  - IPs must be valid IPv4, IPv6, or CIDR notation\n'
    printf '  - Protocols must be from the allowed set\n'
    printf '  - Shell metacharacters are rejected in all fields\n'
    printf '  - TTL must be between 60 seconds and 30 days (2592000s)\n'

    _help_section "Examples"
    printf '  # Allow HTTPS inbound\n'
    printf '  sudo %s add-rule --protocol tcp --dst-port 443 --action accept\n\n' "${me}"
    printf '  # Block a specific IP\n'
    printf '  sudo %s add-rule --src-ip 203.0.113.50 --action drop \\\n' "${me}"
    printf '      --description "Block suspicious host"\n\n'
    printf '  # Allow SSH from a subnet only\n'
    printf '  sudo %s add-rule --protocol tcp --dst-port 22 \\\n' "${me}"
    printf '      --src-ip 10.0.1.0/24 --action accept --description "SSH mgmt"\n\n'
    printf '  # Temporary DNS rule (2 hours)\n'
    printf '  sudo %s add-rule --protocol udp --dst-port 53 --action accept \\\n' "${me}"
    printf '      --duration temporary --ttl 7200 --description "DNS 2h"\n\n'
    printf '  # Allow port range for an application\n'
    printf '  sudo %s --backend iptables add-rule --protocol tcp \\\n' "${me}"
    printf '      --dst-port 8080-8090 --action accept --table filter\n'

    _help_section "Interactive Alternative"
    printf '  For guided rule creation with backend-specific prompts, use:\n'
    printf '    sudo %s menu  →  Rule Management  →  Create new rule\n' "${me}"
    printf '  The interactive wizard walks through 5 steps with validation.\n'

    _help_tip "Temporary rules auto-expire. Monitor via: menu > Rule Management > Rule expiry watcher"
    _help_tip "Rules are tracked by UUID. Use list-rules to see all tracked rules."

    _help_related \
        "${me} list-rules         — Show all Apotropaios-tracked rules" \
        "${me} remove-rule ID     — Remove a rule by its UUID" \
        "${me} activate-rule ID   — Re-activate a deactivated rule" \
        "${me} deactivate-rule ID — Deactivate without deleting" \
        "${me} import FILE        — Bulk-import rules from a file"
    printf '\n'
}

# ==============================================================================
# help_cmd_remove_rule()
# ==============================================================================
help_cmd_remove_rule() {
    local me
    me="$(basename "$0")"
    _help_header "remove-rule" "Remove a tracked firewall rule by UUID"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] remove-rule RULE_ID\n' "${me}"

    _help_section "Description"
    printf '  Removes a firewall rule from both the backend firewall and the\n'
    printf '  Apotropaios rule index. The rule is identified by its UUID which\n'
    printf '  was assigned during creation. The backend-specific removal uses\n'
    printf '  the embedded comment tag (apotropaios:<UUID>) to ensure only the\n'
    printf '  target rule is affected — other rules are never impacted.\n'

    _help_section "Arguments"
    printf '  RULE_ID   UUID of the rule to remove (from list-rules output)\n'

    _help_section "Examples"
    printf '  sudo %s list-rules                                     # Find the UUID\n' "${me}"
    printf '  sudo %s remove-rule 41db4e27-0dbc-49de-b635-e1d943b604d7\n' "${me}"

    _help_tip "Use deactivate-rule to disable a rule without deleting it from the index."
    _help_tip "Deactivated rules can be re-activated later without re-entering parameters."

    _help_related \
        "${me} list-rules         — Find rule UUIDs" \
        "${me} deactivate-rule ID — Disable without deleting" \
        "${me} activate-rule ID   — Re-enable a deactivated rule"
    printf '\n'
}

# ==============================================================================
# help_cmd_activate_rule()
# ==============================================================================
help_cmd_activate_rule() {
    local me
    me="$(basename "$0")"
    _help_header "activate-rule" "Re-activate a previously deactivated rule"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] activate-rule RULE_ID\n' "${me}"

    _help_section "Description"
    printf '  Re-applies a deactivated or expired rule to the firewall backend.\n'
    printf '  The rule parameters are read from the persistent index — no need\n'
    printf '  to re-enter them. The backend is automatically selected based on\n'
    printf '  the original rule creation context.\n'

    _help_section "Arguments"
    printf '  RULE_ID   UUID of the rule to re-activate\n'

    _help_section "Examples"
    printf '  sudo %s activate-rule 41db4e27-0dbc-49de-b635-e1d943b604d7\n' "${me}"

    _help_related \
        "${me} deactivate-rule ID — Disable a rule" \
        "${me} list-rules         — Show rules and their states"
    printf '\n'
}

# ==============================================================================
# help_cmd_deactivate_rule()
# ==============================================================================
help_cmd_deactivate_rule() {
    local me
    me="$(basename "$0")"
    _help_header "deactivate-rule" "Deactivate a rule without removing from index"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] deactivate-rule RULE_ID\n' "${me}"

    _help_section "Description"
    printf '  Removes a rule from the active firewall backend but retains it in\n'
    printf '  the Apotropaios rule index with state "inactive". The rule can be\n'
    printf '  re-activated later with activate-rule using the same UUID.\n\n'
    printf '  This is useful for temporarily disabling a rule during testing or\n'
    printf '  maintenance without losing the rule configuration.\n'

    _help_section "Arguments"
    printf '  RULE_ID   UUID of the rule to deactivate\n'

    _help_section "Examples"
    printf '  sudo %s deactivate-rule 41db4e27-0dbc-49de-b635-e1d943b604d7\n' "${me}"

    _help_related \
        "${me} activate-rule ID   — Re-enable the rule" \
        "${me} remove-rule ID     — Permanently delete the rule"
    printf '\n'
}

# ==============================================================================
# help_cmd_list_rules()
# ==============================================================================
help_cmd_list_rules() {
    local me
    me="$(basename "$0")"
    _help_header "list-rules" "List all Apotropaios-tracked firewall rules"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] list-rules\n' "${me}"

    _help_section "Description"
    printf '  Displays a formatted table of all rules created and tracked by\n'
    printf '  Apotropaios. Each rule shows its UUID, backend, direction, action,\n'
    printf '  protocol, destination port, state, and description.\n\n'
    printf '  Rule states are color-coded:\n'
    printf '    %bactive%b    — Rule is enforced by the firewall\n' "${COLOR_GREEN}" "${COLOR_RESET}"
    printf '    %binactive%b  — Rule removed from firewall, kept in index\n' "${COLOR_YELLOW}" "${COLOR_RESET}"
    printf '    %bexpired%b   — Temporary rule past TTL\n' "${COLOR_RED}" "${COLOR_RESET}"

    _help_section "Examples"
    printf '  sudo %s list-rules\n' "${me}"

    _help_tip "This shows only Apotropaios-managed rules. For ALL system rules, use system-rules."

    _help_related \
        "${me} system-rules       — List all native firewall rules across all backends" \
        "${me} add-rule           — Create a new rule" \
        "${me} remove-rule ID     — Remove a tracked rule"
    printf '\n'
}

# ==============================================================================
# help_cmd_system_rules()
# ==============================================================================
help_cmd_system_rules() {
    local me
    me="$(basename "$0")"
    _help_header "system-rules" "Audit all native system firewall rules"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] system-rules\n' "${me}"

    _help_section "Description"
    printf '  Scans every installed firewall backend and displays all currently\n'
    printf '  active rules in their native format. This includes rules created\n'
    printf '  by Apotropaios AND rules created manually, by other tools, or by\n'
    printf '  the operating system defaults.\n\n'
    printf '  Output is organized by backend:\n'
    printf '    - iptables: iptables -L -n --line-numbers\n'
    printf '    - nftables: nft list ruleset\n'
    printf '    - firewalld: firewall-cmd --list-all\n'
    printf '    - ufw: ufw status numbered verbose\n'
    printf '    - ipset: ipset list -t\n'

    _help_section "Prerequisites"
    printf '  Root privileges required to query firewall backends.\n'

    _help_section "Examples"
    printf '  sudo %s system-rules\n' "${me}"

    _help_tip "Use this before deploying changes to audit the full firewall state."

    _help_related \
        "${me} list-rules         — Show only Apotropaios-tracked rules" \
        "${me} detect             — Show firewall install/version status" \
        "${me} status             — Show detailed status of one backend"
    printf '\n'
}

# ==============================================================================
# help_cmd_block_all()
# ==============================================================================
help_cmd_block_all() {
    local me
    me="$(basename "$0")"
    _help_header "block-all" "Block all inbound and outbound network traffic"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] block-all\n' "${me}"

    _help_section "Description"
    printf '  Immediately blocks ALL inbound, outbound, and forwarded traffic\n'
    printf '  through the active firewall backend. Loopback (127.0.0.1) is\n'
    printf '  preserved to prevent system service failures.\n\n'
    printf '  %bWARNING:%b This will terminate all active network connections\n' "${COLOR_RED}" "${COLOR_RESET}"
    printf '  including SSH sessions. Ensure you have console access before\n'
    printf '  running this command on a remote system.\n\n'
    printf '  A restore point backup is automatically created before blocking.\n'

    _help_section "Backend Behavior"
    printf '  iptables:  Sets default policies to DROP on INPUT/OUTPUT/FORWARD\n'
    printf '  nftables:  Creates drop-policy chains in apotropaios table\n'
    printf '  firewalld: Activates panic mode\n'
    printf '  ufw:       Sets default deny on incoming/outgoing/routed\n'
    printf '  ipset:     Creates 0.0.0.0/0 blocklist set + iptables rules\n'

    _help_section "Examples"
    printf '  sudo %s block-all                      # Block everything\n' "${me}"
    printf '  sudo %s allow-all                      # Undo: allow everything\n' "${me}"

    _help_tip "The auto-created restore point can be used to restore previous state."

    _help_related \
        "${me} allow-all          — Reverse: allow all traffic" \
        "${me} backup             — Create a manual backup first" \
        "${me} restore FILE       — Restore from a previous backup"
    printf '\n'
}

# ==============================================================================
# help_cmd_allow_all()
# ==============================================================================
help_cmd_allow_all() {
    local me
    me="$(basename "$0")"
    _help_header "allow-all" "Allow all inbound and outbound network traffic"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] allow-all\n' "${me}"

    _help_section "Description"
    printf '  Removes all firewall restrictions through the active backend,\n'
    printf '  allowing all network traffic. This is the inverse of block-all.\n\n'
    printf '  %bWARNING:%b This removes all firewall protection. The system\n' "${COLOR_RED}" "${COLOR_RESET}"
    printf '  will be fully exposed to network traffic.\n'

    _help_section "Examples"
    printf '  sudo %s allow-all\n' "${me}"

    _help_related \
        "${me} block-all          — Block all traffic" \
        "${me} restore FILE       — Restore a specific configuration"
    printf '\n'
}

# ==============================================================================
# help_cmd_import()
# ==============================================================================
help_cmd_import() {
    local me
    me="$(basename "$0")"
    _help_header "import" "Import firewall rules from a configuration file"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] import FILE\n' "${me}"

    _help_section "Description"
    printf '  Reads a rule configuration file and creates/applies each rule\n'
    printf '  through the active backend. Each line is validated individually\n'
    printf '  before application. Invalid lines are skipped with warnings.\n\n'
    printf '  If a .sha256 sidecar file exists alongside the config file,\n'
    printf '  integrity is verified before processing.\n'

    _help_section "Arguments"
    printf '  FILE      Path to the rules configuration file\n'

    _help_section "Configuration File Format"
    printf '  # Lines starting with # are comments\n'
    printf '  direction=inbound action=accept protocol=tcp dst_port=443 description="HTTPS"\n'
    printf '  direction=inbound action=drop src_ip=10.0.0.0/8 description="Block RFC1918"\n'
    printf '  direction=outbound action=accept protocol=udp dst_port=53 duration_type=temporary ttl=7200\n'

    _help_section "Supported Fields"
    printf '  direction, action, protocol, src_ip, dst_ip, src_port, dst_port,\n'
    printf '  duration_type, ttl, description\n'

    _help_section "Interactive Alternative"
    printf '  The interactive menu offers a dry-run validation mode:\n'
    printf '    menu > Rule Management > Import rules from file\n'
    printf '  This validates all entries first, then asks for confirmation.\n'

    _help_section "Examples"
    printf '  sudo %s import /path/to/rules.conf\n' "${me}"
    printf '  sudo %s --backend nftables import /etc/apotropaios/prod-rules.conf\n' "${me}"

    _help_tip "Always run 'export' to back up current rules before importing."
    _help_tip "The interactive import offers dry-run validation before applying."

    _help_related \
        "${me} export FILE        — Export current rules to a file" \
        "${me} list-rules         — Verify imported rules" \
        "${me} backup             — Back up before importing"
    printf '\n'
}

# ==============================================================================
# help_cmd_export()
# ==============================================================================
help_cmd_export() {
    local me
    me="$(basename "$0")"
    _help_header "export" "Export Apotropaios rules to a configuration file"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] export FILE\n' "${me}"

    _help_section "Description"
    printf '  Writes all rules from the Apotropaios index to a portable\n'
    printf '  configuration file in key=value format. A SHA-256 checksum\n'
    printf '  sidecar file (.sha256) is generated for integrity verification.\n\n'
    printf '  The exported file can be imported on another system or used\n'
    printf '  as a backup of rule definitions.\n'

    _help_section "Arguments"
    printf '  FILE      Output file path for the exported rules\n'

    _help_section "Examples"
    printf '  sudo %s export /tmp/my-rules.conf\n' "${me}"
    printf '  sudo %s export /etc/apotropaios/production.conf\n' "${me}"

    _help_section "Output Format"
    printf '  direction=inbound action=accept protocol=tcp dst_port=443 ...\n'
    printf '  (One rule per line, with all parameters as key=value pairs)\n'

    _help_related \
        "${me} import FILE        — Import rules from a file" \
        "${me} list-rules         — See rules before exporting" \
        "${me} backup             — Full config backup (all backends)"
    printf '\n'
}

# ==============================================================================
# help_cmd_backup()
# ==============================================================================
help_cmd_backup() {
    local me
    me="$(basename "$0")"
    _help_header "backup" "Create a configuration backup archive"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] backup [LABEL]\n' "${me}"

    _help_section "Description"
    printf '  Creates a timestamped, compressed backup archive (.tar.gz) of all\n'
    printf '  firewall configurations plus the Apotropaios rule index and state.\n'
    printf '  A SHA-256 checksum is generated for integrity verification.\n\n'
    printf '  Backups capture:\n'
    printf '    - iptables rules (via iptables-save)\n'
    printf '    - nftables ruleset (via nft list ruleset)\n'
    printf '    - firewalld zone configuration\n'
    printf '    - ufw status and /etc/ufw configuration\n'
    printf '    - ipset definitions (via ipset save)\n'
    printf '    - Apotropaios rule index and state files\n'
    printf '    - JSON manifest with system metadata\n'

    _help_section "Arguments"
    printf '  LABEL     Optional label for the backup (default: "manual")\n'
    printf '            Labels appear in the backup filename for identification.\n'

    _help_section "Retention"
    printf '  Maximum %d backups are retained. Oldest are auto-deleted.\n' "${BACKUP_MAX_RETAINED}"

    _help_section "Examples"
    printf '  sudo %s backup                         # Default label\n' "${me}"
    printf '  sudo %s backup pre-deployment          # Custom label\n' "${me}"
    printf '  sudo %s backup "2026-Q1-audit"         # Descriptive label\n' "${me}"

    _help_tip "Backups are auto-created before block-all, reset, install, and restore."
    _help_tip "For tamper-proof backups, use: menu > Backup & Recovery > Immutable snapshot"

    _help_related \
        "${me} restore FILE       — Restore from a backup archive" \
        "${me} export FILE        — Export just the rule definitions"
    printf '\n'
}

# ==============================================================================
# help_cmd_restore()
# ==============================================================================
help_cmd_restore() {
    local me
    me="$(basename "$0")"
    _help_header "restore" "Restore firewall configuration from a backup"

    _help_section "Synopsis"
    printf '  %s [OPTIONS] restore FILE\n' "${me}"

    _help_section "Description"
    printf '  Restores firewall configurations from a previously created backup\n'
    printf '  archive. Before restoring, a safety backup of the current state\n'
    printf '  is automatically created.\n\n'
    printf '  The restore process:\n'
    printf '    1. Verifies archive integrity (SHA-256 checksum)\n'
    printf '    2. Creates pre-restore safety backup\n'
    printf '    3. Extracts archive to temporary directory\n'
    printf '    4. Restores each backend configuration\n'
    printf '    5. Reloads rule index and state\n'

    _help_section "Arguments"
    printf '  FILE      Path to the backup archive (.tar.gz)\n'

    _help_section "Examples"
    printf '  sudo %s restore data/backups/apotropaios_backup_pre-deploy_2026-03-21.tar.gz\n' "${me}"

    _help_tip "List available backups: menu > Backup & Recovery > List backups"

    _help_related \
        "${me} backup [LABEL]     — Create a new backup" \
        "${me} detect             — Verify system state after restore"
    printf '\n'
}

# ==============================================================================
# help_cmd_install()
# ==============================================================================
help_cmd_install() {
    local me
    me="$(basename "$0")"
    _help_header "install" "Install a firewall package"

    _help_section "Synopsis"
    printf '  %s install FW_NAME\n' "${me}"

    _help_section "Description"
    printf '  Installs a firewall package using the system package manager.\n'
    printf '  Automatically detects the OS and uses the correct package name.\n'
    printf '  Creates a restore point before installation and verifies success.\n'

    _help_section "Arguments"
    printf '  FW_NAME   Firewall to install: firewalld, ipset, iptables, nftables, ufw\n'

    _help_section "Package Mapping"
    printf '  %-12s %-15s %-15s %-15s\n' "Firewall" "apt (Deb/Ubuntu)" "dnf (RHEL)" "pacman (Arch)"
    printf '  %-12s %-15s %-15s %-15s\n' "firewalld" "firewalld" "firewalld" "firewalld"
    printf '  %-12s %-15s %-15s %-15s\n' "ipset" "ipset" "ipset" "ipset"
    printf '  %-12s %-15s %-15s %-15s\n' "iptables" "iptables" "iptables" "iptables"
    printf '  %-12s %-15s %-15s %-15s\n' "nftables" "nftables" "nftables" "nftables"
    printf '  %-12s %-15s %-15s %-15s\n' "ufw" "ufw" "ufw" "ufw"

    _help_section "Examples"
    printf '  sudo %s install ufw\n' "${me}"
    printf '  sudo %s install nftables\n' "${me}"

    _help_tip "After installing, the firewall is auto-configured with safe defaults."

    _help_related \
        "${me} update FW_NAME     — Update an installed firewall" \
        "${me} detect             — Check what is installed"
    printf '\n'
}

# ==============================================================================
# help_cmd_update()
# ==============================================================================
help_cmd_update() {
    local me
    me="$(basename "$0")"
    _help_header "update" "Update an installed firewall package"

    _help_section "Synopsis"
    printf '  %s update FW_NAME\n' "${me}"

    _help_section "Description"
    printf '  Updates an installed firewall package to the latest version\n'
    printf '  available in the system repository. Creates a restore point\n'
    printf '  before updating.\n'

    _help_section "Arguments"
    printf '  FW_NAME   Firewall to update: firewalld, ipset, iptables, nftables, ufw\n'

    _help_section "Examples"
    printf '  sudo %s update iptables\n' "${me}"

    _help_related \
        "${me} install FW_NAME    — Install a new firewall" \
        "${me} detect             — Check current versions"
    printf '\n'
}

# ==============================================================================
# help_list_commands()
# Description:  List all commands that have detailed help available.
# ==============================================================================
help_list_commands() {
    printf '\n%bCommands with detailed help:%b\n\n' "${COLOR_BOLD}" "${COLOR_RESET}"
    printf '  %-22s %s\n' "menu" "Interactive menu interface"
    printf '  %-22s %s\n' "detect" "OS and firewall detection"
    printf '  %-22s %s\n' "status" "Firewall backend status"
    printf '  %-22s %s\n' "add-rule" "Create a firewall rule (full option reference)"
    printf '  %-22s %s\n' "remove-rule" "Remove a rule by UUID"
    printf '  %-22s %s\n' "activate-rule" "Re-activate a deactivated rule"
    printf '  %-22s %s\n' "deactivate-rule" "Deactivate a rule"
    printf '  %-22s %s\n' "list-rules" "List Apotropaios-tracked rules"
    printf '  %-22s %s\n' "system-rules" "Audit all native system rules"
    printf '  %-22s %s\n' "block-all" "Block all network traffic"
    printf '  %-22s %s\n' "allow-all" "Allow all network traffic"
    printf '  %-22s %s\n' "import" "Import rules from config file"
    printf '  %-22s %s\n' "export" "Export rules to config file"
    printf '  %-22s %s\n' "backup" "Create configuration backup"
    printf '  %-22s %s\n' "restore" "Restore from backup"
    printf '  %-22s %s\n' "install" "Install a firewall package"
    printf '  %-22s %s\n' "update" "Update a firewall package"
    printf '\n  Usage: %s COMMAND --help\n\n' "$(basename "$0")"
}
