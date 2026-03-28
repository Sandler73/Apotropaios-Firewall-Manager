#!/usr/bin/env bash
# ==============================================================================
# File:         lib/core/constants.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Readonly constants, version information, and configuration defaults
# Description:  Defines all immutable constants used throughout the Apotropaios
#               framework including version strings, supported operating systems,
#               supported firewall backends, directory paths, exit codes, log
#               levels, validation patterns, and security-related constants.
#               All values are declared readonly to prevent accidental mutation.
# Notes:        - Must be sourced before any other library module
#               - All constants use UPPERCASE_WITH_UNDERSCORES naming convention
#               - Grouped by functional domain for maintainability
#               - No external dependencies
# Version:      1.1.5
# ==============================================================================

# Prevent double-sourcing
[[ -n "${_APOTROPAIOS_CONSTANTS_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_CONSTANTS_LOADED=1

# ==============================================================================
# Version & Identity
# ==============================================================================
readonly APOTROPAIOS_VERSION="1.1.5"
readonly APOTROPAIOS_NAME="Apotropaios"
readonly APOTROPAIOS_FULL_NAME="Apotropaios - Firewall Manager"
readonly APOTROPAIOS_MIN_BASH_VERSION="4.0"

# ==============================================================================
# Directory Paths (relative to APOTROPAIOS_BASE_DIR, set at runtime)
# ==============================================================================
readonly APOTROPAIOS_LIB_DIR_REL="lib"
readonly APOTROPAIOS_CONF_DIR_REL="conf"
readonly APOTROPAIOS_DATA_DIR_REL="data"
readonly APOTROPAIOS_LOGS_DIR_REL="data/logs"
readonly APOTROPAIOS_RULES_DIR_REL="data/rules"
readonly APOTROPAIOS_BACKUPS_DIR_REL="data/backups"
readonly APOTROPAIOS_TEMP_DIR_REL="data/.tmp"

# ==============================================================================
# File Names
# ==============================================================================
readonly APOTROPAIOS_CONF_FILE="apotropaios.conf"
readonly APOTROPAIOS_RULE_INDEX_FILE="rule_index.dat"
readonly APOTROPAIOS_RULE_STATE_FILE="rule_state.dat"
readonly APOTROPAIOS_LOCK_FILE="apotropaios.lock"
readonly APOTROPAIOS_PID_FILE="apotropaios.pid"

# ==============================================================================
# Supported Operating Systems
# Canonical identifiers used for OS detection matching
# ==============================================================================
readonly -a SUPPORTED_OS_LIST=(
    "ubuntu"
    "kali"
    "debian"
    "rocky"
    "almalinux"
    "arch"
)

# Human-readable OS names (parallel array)
readonly -a SUPPORTED_OS_NAMES=(
    "Ubuntu"
    "Kali Linux"
    "Debian 12"
    "Rocky Linux 9"
    "AlmaLinux 9"
    "Arch Linux"
)

# Package manager mapping (parallel array)
readonly -a SUPPORTED_OS_PKG_MANAGERS=(
    "apt"
    "apt"
    "apt"
    "dnf"
    "dnf"
    "pacman"
)

# ==============================================================================
# Supported Firewall Backends
# ==============================================================================
readonly -a SUPPORTED_FW_LIST=(
    "firewalld"
    "ipset"
    "iptables"
    "nftables"
    "ufw"
)

# Firewall binary names (parallel array)
readonly -a SUPPORTED_FW_BINARIES=(
    "firewall-cmd"
    "ipset"
    "iptables"
    "nft"
    "ufw"
)

# Firewall service names (parallel array)
readonly -a SUPPORTED_FW_SERVICES=(
    "firewalld"
    ""
    "iptables"
    "nftables"
    "ufw"
)

# Package names per OS family: apt-based, dnf-based, pacman-based
# Format: "apt_pkg:dnf_pkg:pacman_pkg"
readonly -a SUPPORTED_FW_PACKAGES=(
    "firewalld:firewalld:firewalld"
    "ipset:ipset:ipset"
    "iptables:iptables:iptables"
    "nftables:nftables:nftables"
    "ufw:ufw:ufw"
)

# ==============================================================================
# Exit Codes
# ==============================================================================
readonly E_SUCCESS=0
readonly E_GENERAL=1
readonly E_USAGE=2
readonly E_PERMISSION=3
readonly E_OS_UNSUPPORTED=10
readonly E_FW_NOT_FOUND=11
readonly E_FW_NOT_RUNNING=12
readonly E_FW_INSTALL_FAIL=13
readonly E_RULE_INVALID=20
readonly E_RULE_EXISTS=21
readonly E_RULE_NOT_FOUND=22
readonly E_RULE_APPLY_FAIL=23
readonly E_RULE_REMOVE_FAIL=24
readonly E_RULE_IMPORT_FAIL=25
readonly E_BACKUP_FAIL=30
readonly E_RESTORE_FAIL=31
readonly E_BACKUP_NOT_FOUND=32
readonly E_VALIDATION_FAIL=40
readonly E_INPUT_SANITIZE_FAIL=41
readonly E_LOG_FAIL=50
readonly E_LOG_HANDLE_LOST=51
readonly E_LOCK_FAIL=60
readonly E_LOCK_TIMEOUT=61
readonly E_INTEGRITY_FAIL=70
readonly E_MEMORY_FAIL=71
readonly E_SIGNAL_RECEIVED=80
readonly E_CLEANUP_FAIL=81

# ==============================================================================
# Log Levels (numeric for comparison)
# ==============================================================================
readonly LOG_LEVEL_TRACE=0
readonly LOG_LEVEL_DEBUG=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_WARNING=3
readonly LOG_LEVEL_ERROR=4
readonly LOG_LEVEL_CRITICAL=5
readonly LOG_LEVEL_NONE=99

# Log level names (for display/parsing)
readonly -A LOG_LEVEL_NAMES=(
    [0]="TRACE"
    [1]="DEBUG"
    [2]="INFO"
    [3]="WARNING"
    [4]="ERROR"
    [5]="CRITICAL"
    [99]="NONE"
)

# Reverse mapping: name to number
readonly -A LOG_LEVEL_NUMBERS=(
    ["TRACE"]=0
    ["DEBUG"]=1
    ["INFO"]=2
    ["WARNING"]=3
    ["ERROR"]=4
    ["CRITICAL"]=5
    ["NONE"]=99
    ["trace"]=0
    ["debug"]=1
    ["info"]=2
    ["warning"]=3
    ["error"]=4
    ["critical"]=5
    ["none"]=99
)

# Default log level
readonly DEFAULT_LOG_LEVEL="${LOG_LEVEL_INFO}"

# ==============================================================================
# Validation Patterns (POSIX Extended Regular Expressions)
# Security: Whitelist patterns — reject everything that doesn't match
# ==============================================================================

# IPv4 address: 0-255.0-255.0-255.0-255
readonly PATTERN_IPV4='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

# IPv6 address (simplified — allows compressed notation)
readonly PATTERN_IPV6='^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$'

# CIDR notation: IP/prefix
readonly PATTERN_CIDR_V4='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
readonly PATTERN_CIDR_V6='^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}/[0-9]{1,3}$'

# Port number: 1-65535
readonly PATTERN_PORT='^[0-9]{1,5}$'

# Port range: port-port or port:port
readonly PATTERN_PORT_RANGE='^[0-9]{1,5}[-:][0-9]{1,5}$'

# Protocol: tcp, udp, icmp, sctp, all
readonly PATTERN_PROTOCOL='^(tcp|udp|icmp|icmpv6|sctp|all)$'

# Hostname: RFC 1123 compliant
readonly PATTERN_HOSTNAME='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'

# Interface name: alphanumeric with limited special chars
readonly PATTERN_INTERFACE='^[a-zA-Z][a-zA-Z0-9._-]{0,14}$'

# Zone name (firewalld): alphanumeric with hyphens
readonly PATTERN_ZONE='^[a-zA-Z][a-zA-Z0-9_-]{0,31}$'

# Chain name: alphanumeric with underscores
readonly PATTERN_CHAIN='^[a-zA-Z][a-zA-Z0-9_-]{0,63}$'

# Table name: alphanumeric with underscores
readonly PATTERN_TABLE='^[a-zA-Z][a-zA-Z0-9_]{0,31}$'

# IPSet name: alphanumeric with underscores and hyphens
readonly PATTERN_IPSET_NAME='^[a-zA-Z][a-zA-Z0-9_-]{0,30}$'

# Rule ID: UUID format (generated by framework)
readonly PATTERN_RULE_ID='^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'

# File path: restricted to safe characters, no traversal
# Allows alphanumeric, slashes, hyphens, underscores, dots, tildes, spaces
readonly PATTERN_SAFE_PATH='^[a-zA-Z0-9/_. ~:+-]+$'

# Directory path: same as safe path (used for log/data directory validation)
readonly PATTERN_SAFE_DIR='^[a-zA-Z0-9/_. ~:+-]+$'

# Shell metacharacter detection (BLACKLIST for rejection — used on user input only)
# Note: Use individual character tests for portability across bash versions
# rather than a single complex character class which has version-dependent behavior
readonly PATTERN_SHELL_META_SEMICOLONS=';'
readonly PATTERN_SHELL_META_PIPES='[|]'
readonly PATTERN_SHELL_META_AMPS='[&]'
readonly PATTERN_SHELL_META_BACKTICKS='[`]'
readonly PATTERN_SHELL_META_DOLLARS='[$]'
readonly PATTERN_SHELL_META_PARENS='[()]'
readonly PATTERN_SHELL_META_BRACES='[{}]'
readonly PATTERN_SHELL_META_REDIRECTS='[<>]'
readonly PATTERN_SHELL_META_BANGS='[!]'
readonly PATTERN_SHELL_META_HASHES='[#]'

# Numeric only
readonly PATTERN_NUMERIC='^[0-9]+$'

# Alphanumeric with hyphens/underscores
readonly PATTERN_ALNUM_SAFE='^[a-zA-Z0-9_-]+$'

# ==============================================================================
# Security Constants
# ==============================================================================
readonly SECURE_UMASK="077"
readonly SECURE_DIR_PERMS="700"
readonly SECURE_FILE_PERMS="600"
readonly SECURE_EXEC_PERMS="700"
readonly MAX_INPUT_LENGTH=4096
readonly MAX_PATH_LENGTH=4096
readonly MAX_RULE_DESCRIPTION_LENGTH=256
readonly MAX_LOG_FILE_SIZE_BYTES=104857600    # 100MB
readonly MAX_LOG_FILES_RETAINED=10
readonly LOCK_TIMEOUT_SECONDS=30
readonly LOCK_RETRY_INTERVAL=1

# ==============================================================================
# Firewall Rule Constants
# ==============================================================================
readonly -a RULE_ACTIONS=("accept" "drop" "reject" "log" "masquerade" "snat" "dnat" "return")
readonly -a RULE_TERMINAL_ACTIONS=("accept" "drop" "reject" "masquerade" "snat" "dnat" "return")
readonly -a RULE_NON_TERMINAL_ACTIONS=("log")
readonly -a RULE_DIRECTIONS=("inbound" "outbound" "forward")
readonly -a RULE_STATES=("active" "inactive" "pending" "expired")
readonly -a RULE_DURATION_TYPES=("permanent" "temporary")

# Connection tracking states (conntrack/state module)
readonly -a RULE_CONN_STATES=("new" "established" "related" "invalid" "untracked")

# Log levels (syslog severity)
readonly -a RULE_LOG_LEVELS=("emerg" "alert" "crit" "err" "warning" "notice" "info" "debug")

# Temporary rule minimum/maximum TTL in seconds
readonly RULE_MIN_TTL_SECONDS=60          # 1 minute
readonly RULE_MAX_TTL_SECONDS=2592000     # 30 days

# ==============================================================================
# Backup Constants
# ==============================================================================
readonly BACKUP_PREFIX="apotropaios_backup"
readonly BACKUP_EXTENSION=".tar.gz"
readonly BACKUP_MANIFEST_FILE="manifest.json"
readonly BACKUP_MAX_RETAINED=20
readonly BACKUP_INTEGRITY_ALGORITHM="sha256"

# ==============================================================================
# Performance Constants
# ==============================================================================
readonly MAX_CONCURRENT_OPERATIONS=4
readonly OPERATION_TIMEOUT_SECONDS=300     # 5 minutes
readonly BATCH_SIZE=50                     # Rules per batch operation

# ==============================================================================
# Terminal Colors (only when stdout is a terminal)
# ==============================================================================
if [[ -t 1 ]]; then
    readonly COLOR_RESET='\033[0m'
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_MAGENTA='\033[0;35m'
    readonly COLOR_CYAN='\033[0;36m'
    readonly COLOR_WHITE='\033[0;37m'
    readonly COLOR_BOLD='\033[1m'
    readonly COLOR_DIM='\033[2m'
else
    readonly COLOR_RESET=''
    readonly COLOR_RED=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
    readonly COLOR_BLUE=''
    readonly COLOR_MAGENTA=''
    readonly COLOR_CYAN=''
    readonly COLOR_WHITE=''
    readonly COLOR_BOLD=''
    readonly COLOR_DIM=''
fi
