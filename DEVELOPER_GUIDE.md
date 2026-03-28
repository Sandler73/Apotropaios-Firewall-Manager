# Apotropaios — Developer Guide

> Complete reference catalog of all code components, modules, functions, and their relationships.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Source Order and Dependencies](#source-order-and-dependencies)
3. [Module Reference — Core (Layer 1)](#module-reference--core-layer-1)
4. [Module Reference — Detection (Layer 2)](#module-reference--detection-layer-2)
5. [Module Reference — Firewall Backends (Layer 3)](#module-reference--firewall-backends-layer-3)
6. [Module Reference — Rules, Backup, Install (Layer 4)](#module-reference--rules-backup-install-layer-4)
7. [Module Reference — Menu and Help (Layer 5)](#module-reference--menu-and-help-layer-5)
8. [Entry Point](#entry-point)
9. [Global Variable Conventions](#global-variable-conventions)
10. [Error Code Reference](#error-code-reference)
11. [Constants Reference](#constants-reference)
12. [Testing Architecture](#testing-architecture)
13. [CI/CD Pipeline](#cicd-pipeline)

---

## Architecture Overview

Apotropaios follows a strict layered architecture. Each layer depends only on layers below it, never above.

```
┌─────────────────────────────────────────────┐
│             apotropaios.sh                  │  Entry point, CLI parsing
├─────────────────────────────────────────────┤
│   lib/menu/menu_main.sh                     │  Interactive menu UI
│   lib/menu/help_system.sh                   │  Progressive help (17 pages)
├─────────────────────────────────────────────┤
│   lib/rules/      lib/backup/               │  Rule engine, backup/restore
│   lib/install/                              │  Package management
├─────────────────────────────────────────────┤
│             lib/firewall/                   │  Backend dispatch + 5 backends
├─────────────────────────────────────────────┤
│             lib/detection/                  │  OS + firewall detection
├─────────────────────────────────────────────┤
│             lib/core/                       │  Constants, logging, errors,
│                                             │  validation, security, utils
└─────────────────────────────────────────────┘
```

**25 shell modules, ~288 functions, ~11,000 lines of code.**

---

## Source Order and Dependencies

Source order in `apotropaios.sh` is critical. Lower layers must be sourced first:

```
1. lib/core/constants.sh     (no dependencies)
2. lib/core/logging.sh       (← constants)
3. lib/core/errors.sh        (← constants, logging)
4. lib/core/validation.sh    (← constants, logging)
5. lib/core/security.sh      (← constants, logging, errors)
6. lib/core/utils.sh         (← constants, logging)
7. lib/detection/os_detect.sh   (← core/*)
8. lib/detection/fw_detect.sh   (← core/*, os_detect)
9. lib/firewall/common.sh       (← core/*, detection/*)
10-14. lib/firewall/{iptables,nftables,firewalld,ufw,ipset}.sh (← common)
15. lib/rules/rule_engine.sh    (← core/*, firewall/*)
16. lib/rules/rule_index.sh     (← core/*)
17. lib/rules/rule_state.sh     (← core/*)
18. lib/rules/rule_import.sh    (← core/*, rule_engine, rule_index)
19. lib/backup/backup.sh        (← core/*, detection/*)
20. lib/backup/restore.sh       (← core/*, backup)
21. lib/backup/immutable.sh     (← core/*, backup)
22. lib/install/installer.sh    (← core/*, detection/*)
23. lib/menu/help_system.sh     (← core/constants — minimal deps)
24. lib/menu/menu_main.sh       (← all of the above)
```

Every module uses a source guard to prevent double-sourcing:
```bash
[[ -n "${_APOTROPAIOS_MODULE_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_MODULE_LOADED=1
```

---

## Module Reference — Core (Layer 1)

### lib/core/constants.sh

**Purpose:** Readonly constants, version, patterns, exit codes, colors.

**Key exports:**
- `APOTROPAIOS_VERSION` — Current version string
- `SUPPORTED_OS_LIST[]` — Supported OS identifiers
- `SUPPORTED_FW_LIST[]` — Supported firewall backends
- `RULE_ACTIONS[]` — Valid rule actions (accept, drop, reject, log, masquerade, snat, dnat, return)
- `RULE_TERMINAL_ACTIONS[]` — Terminal actions (max 1 per compound)
- `RULE_NON_TERMINAL_ACTIONS[]` — Non-terminal actions (log)
- `RULE_CONN_STATES[]` — Connection tracking states (new, established, related, invalid, untracked)
- `RULE_LOG_LEVELS[]` — Syslog severity levels
- `E_*` — Exit codes (see [Error Code Reference](#error-code-reference))
- `LOG_LEVEL_*` — Log level numeric constants
- `PATTERN_*` — Validation regex patterns (PATTERN_SAFE_DIR, PATTERN_SAFE_PATH, PATTERN_NUMERIC, etc.)
- `COLOR_*` — Terminal ANSI color codes

**Dependencies:** None (must be sourced first).

### lib/core/logging.sh — 20 functions

**Purpose:** Structured logging with file + console output, FD tracking, rotation, sanitization.

| Function | Description |
|:---------|:------------|
| `log_init(dir, level)` | Initialize logging: create directory, open FD, set level |
| `log_shutdown()` | Close FD, clean shutdown |
| `log_set_level(level)` | Change runtime log level |
| `log_trace(ctx, msg)` | Log at TRACE level |
| `log_debug(ctx, msg)` | Log at DEBUG level |
| `log_info(ctx, msg)` | Log at INFO level |
| `log_warning(ctx, msg)` | Log at WARNING level |
| `log_error(ctx, msg)` | Log at ERROR level |
| `log_critical(ctx, msg)` | Log at CRITICAL level |
| `log_generate_correlation_id()` | Generate UUID-like correlation ID |
| `log_get_file()` | Return current log file path |
| `log_get_level()` | Return current log level name |

**Internal:** `_log_write()`, `_log_verify_handle()`, `_log_recover_handle()`, `_log_rotate()`, `_log_sanitize_message()`, `_log_console()`, `_log_sanitize()`

**Security:** Automatic masking of sensitive data in 4 formats: key=value, key="quoted", JSON, and HTTP Authorization headers via `_log_sanitize_message()`. Control character stripping prevents CWE-117 log injection. Zero `eval` in entire logging module — all FD operations use literal `exec 3>>`.

### lib/core/errors.sh — 13 functions

**Purpose:** Signal traps, LIFO cleanup stack, retry logic, graceful degradation.

| Function | Description |
|:---------|:------------|
| `error_init()` | Register signal traps (EXIT, SIGTERM, SIGINT, SIGHUP, ERR) |
| `error_register_cleanup(func)` | Push cleanup handler onto LIFO stack |
| `error_unregister_cleanup(func)` | Remove specific handler |
| `error_retry(max, delay, cmd...)` | Retry with exponential backoff |
| `error_with_fallback(primary, fallback, ctx)` | Try/fallback pattern |
| `error_die(msg, code)` | Fatal exit with cleanup |
| `error_assert(desc, cmd...)` | Assertion with failure message |
| `error_safe_exec(var, cmd...)` | Execute without triggering set -e |

### lib/core/validation.sh — 28 functions

**Purpose:** Whitelist input validation for all user-supplied data.

| Function | Description |
|:---------|:------------|
| `validate_port(port)` | TCP/UDP port 1-65535 |
| `validate_port_range(range)` | Port range (e.g., 8080-8090) |
| `validate_ipv4(ip)` | IPv4 dotted quad |
| `validate_ipv6(ip)` | IPv6 address |
| `validate_ip(ip)` | IPv4 or IPv6 |
| `validate_cidr(cidr)` | CIDR notation |
| `validate_protocol(proto)` | tcp, udp, icmp, icmpv6, sctp, all |
| `validate_hostname(host)` | RFC-compliant hostname |
| `validate_interface(iface)` | Network interface name |
| `validate_file_path(path)` | Safe path (no traversal, no metacharacters) |
| `validate_zone(zone)` | Firewalld zone name |
| `validate_chain(chain)` | iptables/nftables chain |
| `validate_table(table)` | iptables/nftables table |
| `validate_table_family(family)` | nftables table family (inet/ip/ip6/arp/bridge/netdev) |
| `validate_ipset_name(name)` | IPSet set name |
| `validate_rule_id(uuid)` | UUID format |
| `validate_rule_action(action)` | Single or compound action (log,drop) |
| `validate_rule_direction(dir)` | inbound, outbound, forward |
| `validate_conn_state(states)` | Comma-separated conntrack states |
| `validate_log_prefix(prefix)` | 1-29 chars, safe characters only |
| `validate_rate_limit(limit)` | N/second, N/minute, N/hour, N/day |
| `validate_duration_type(type)` | permanent or temporary |
| `validate_ttl(ttl)` | 60-2592000 seconds |
| `validate_log_level(level)` | Syslog severity levels |
| `validate_numeric(n, min, max)` | Integer within optional bounds |
| `validate_description(desc)` | Safe text, max length |
| `sanitize_input(str)` | Strip metacharacters, enforce max length |
| `_contains_shell_meta(str)` | Portable glob-based metachar detection (14 chars) |

### lib/core/security.sh — 18 functions

**Purpose:** Security controls, locking, checksums, temp file management, variable scrubbing.

| Function | Description |
|:---------|:------------|
| `security_init()` | Initialize security subsystem (umask 077) |
| `security_check_root()` | Verify running as root |
| `security_create_temp_file(prefix)` | Secure mktemp with 600 permissions |
| `security_create_temp_dir(prefix)` | Secure mktemp -d with 700 permissions |
| `security_register_sensitive_var(var)` | Register for scrubbing on exit |
| `security_scrub_vars()` | Overwrite registered variables |
| `security_file_checksum(path)` | SHA-256 of file contents |
| `security_verify_checksum(path, expected)` | Compare checksums |
| `security_acquire_lock(lockfile, timeout)` | Advisory lock: uses flock(1) when available (atomic), noclobber fallback with stale PID detection |
| `security_release_lock(lockfile)` | Release advisory lock |
| `security_secure_dir(path)` | Set 700 permissions |
| `security_secure_file(path)` | Set 600 permissions |
| `security_validate_binary(name)` | Verify binary exists and is executable |
| `security_generate_uuid()` | Generate v4-format UUID |

### lib/core/utils.sh — 20 functions

**Purpose:** Common helpers — timestamps, arrays, KV files, parallel execution, formatting.

| Function | Description |
|:---------|:------------|
| `util_timestamp()` | ISO 8601 UTC timestamp |
| `util_timestamp_epoch()` | Unix epoch seconds |
| `util_to_lower(str)` | Lowercase conversion |
| `util_to_upper(str)` | Uppercase conversion |
| `util_trim(str)` | Strip leading/trailing whitespace |
| `util_is_command_available(cmd)` | Check if command exists |
| `util_array_contains(array, value)` | Search array for value |
| `util_confirm(prompt)` | Interactive y/n confirmation |
| `util_human_duration(seconds)` | "2h 30m 15s" format |
| `util_human_bytes(bytes)` | "1.5 MB" format |
| `util_parallel_exec(...)` | Run commands in parallel with wait |
| `util_print_banner()` | ASCII art banner |
| `util_print_separator(char, width)` | Repeated character line |
| `util_print_kv(key, value, width)` | Aligned key-value output |
| `util_read_kv_file(path)` | Parse key=value file |
| `util_write_kv_file(path, ...)` | Write key=value file |

---

## Module Reference — Detection (Layer 2)

### lib/detection/os_detect.sh — 8 functions

**Purpose:** OS identification via 4 fallback methods.

**Key exports:** `OS_DETECTED_ID`, `OS_DETECTED_NAME`, `OS_DETECTED_VERSION`, `OS_DETECTED_FAMILY`, `OS_DETECTED_PKG_MANAGER`, `OS_DETECTED_SUPPORTED`

**Detection methods (in order):** `/etc/os-release`, `/etc/lsb-release`, `/etc/redhat-release`, `uname -s`

### lib/detection/fw_detect.sh — 15 functions

**Purpose:** Firewall discovery, version extraction, status check across all 5 backends.

**Key exports:** `FW_DETECTED_INSTALLED[]`, `FW_DETECTED_VERSION[]`, `FW_DETECTED_BINARY[]`, `FW_DETECTED_RUNNING[]`, `FW_DETECTED_ENABLED[]`, `FW_DETECTED_COUNT`

| Function | Description |
|:---------|:------------|
| `fw_detect_all()` | Scan all 5 backends |
| `fw_detect_single(backend)` | Scan specific backend |
| `fw_get_installed()` | List installed backends |
| `fw_get_info()` | Display all backends with status |
| `fw_is_installed(backend)` | Check if specific backend exists |
| `fw_is_running(backend)` | Check if backend is active |

---

## Module Reference — Firewall Backends (Layer 3)

### lib/firewall/common.sh — 17 functions

**Purpose:** Unified dispatch layer routing operations to the active backend.

| Function | Description |
|:---------|:------------|
| `fw_set_backend(name)` | Set active backend |
| `fw_get_backend()` | Get active backend name |
| `fw_add_rule(rule_array)` | Dispatch add_rule to active backend |
| `fw_remove_rule(rule_array)` | Dispatch remove_rule |
| `fw_list_rules()` | Dispatch list_rules |
| `fw_enable()` | Enable/start firewall |
| `fw_disable()` | Disable/stop firewall |
| `fw_status()` | Backend status |
| `fw_block_all()` | Set all policies to DROP |
| `fw_allow_all()` | Set all policies to ACCEPT |
| `fw_reset()` | Reset to defaults |
| `fw_save()` | Save configuration |
| `fw_reload()` | Reload configuration |
| `fw_export_config()` | Export for backup |

### lib/firewall/{iptables,nftables,firewalld,ufw,ipset}.sh

Each backend implements the standard interface. Key per-backend details:

**iptables.sh (12 functions):** Compound actions create separate LOG + terminal rules; removal mirrors this by deleting both rules. Supports `-m conntrack --ctstate`, `-m limit`, `--log-prefix`, `--log-level`. Commands built as arrays — never string interpolation. All parameters re-validated from index before removal.

**nftables.sh (14 functions):** Compound actions combined in single nft expression (e.g., `log prefix "..." drop`). Supports `ct state`, `limit rate`. Table family validated via `validate_table_family()`. Direct command execution only — no `nft -f` file mode (removed as injection vector).

**firewalld.sh (13 functions):** Rich rule builder (`_firewalld_build_rich_rule`) with 12 parameters including log clause, compound actions, and rate limits. Auto-selects rich rule vs simple port add.

**ufw.sh (12 functions):** Compound action extracts terminal for ufw verb, enables logging separately. Extended syntax auto-detection for source/destination rules. Backend config: 9 options including app profile enable/disable, logging level control, default policy management.

**ipset.sh (14 functions):** Set creation/management plus iptables integration rules. Supports hash:ip, hash:net, hash:ip,port set types.

---

## Module Reference — Rules, Backup, Install (Layer 4)

### lib/rules/rule_engine.sh — 7 functions

**Purpose:** Rule lifecycle orchestration.

| Function | Description |
|:---------|:------------|
| `rule_create(params)` | Validate, apply, index a new rule. Returns UUID. |
| `rule_remove(uuid)` | Remove from firewall and index |
| `rule_deactivate(uuid)` | Remove from firewall, keep in index |
| `rule_activate(uuid)` | Re-apply deactivated rule |
| `rule_block_all_traffic()` | Emergency block with restore point |
| `rule_allow_all_traffic()` | Remove all restrictions |
| `rule_check_expired()` | Process expired temporary rules |

**Compound action handling:** Engine validates the compound action format (max 1 terminal), normalizes to lowercase, and passes to the backend which translates natively.

**Rule record fields (26):** rule_id, backend, direction, action, protocol, src_ip, dst_ip, src_port, dst_port, interface, chain, table, zone, set_name, conn_state, log_prefix, log_level, limit, limit_burst, duration_type, ttl, description, state, created_at, updated_at, checksum.

### lib/rules/rule_index.sh — 12 functions

**Purpose:** Persistent pipe-delimited rule tracking.

### lib/rules/rule_state.sh — 13 functions

**Purpose:** Activation state and TTL tracking.

### lib/rules/rule_import.sh — 4 functions

**Purpose:** Configuration file import/export with validation and SHA-256 integrity.

### lib/backup/{backup,restore,immutable}.sh — 13 functions

**Purpose:** Timestamped compressed archives, automatic restore points, `chattr +i` immutable snapshots.

### lib/install/installer.sh — 7 functions

**Purpose:** Firewall package installation via apt/dnf/pacman with auto-detection.

---

## Module Reference — Menu and Help (Layer 5)

### lib/menu/menu_main.sh — 25 functions

**Purpose:** Interactive menu-driven interface with guided wizards.

Key internal functions:
- `_menu_create_rule()` — 5-step rule creation wizard with compound action, connection state, log options, rate limit prompts
- `_menu_remove_rule()`, `_menu_activate_rule()`, `_menu_deactivate_rule()` — UUID validation before engine calls
- `_menu_import_rules()` — File scanner + validation
- `_menu_export_rules()` — Default path, overwrite protection
- `_menu_list_system_rules()` — Multi-backend audit
- `_menu_rule_watcher()` — Color-coded TTL display with extension
- `_menu_backend_config()` — Dispatch to per-backend config menus
- `_menu_backend_config_{iptables,nftables,firewalld,ufw,ipset}()` — Backend-specific submenus

### lib/menu/help_system.sh — 23 functions

**Purpose:** Progressive 3-tier help system with 17 per-command help pages.

| Function | Description |
|:---------|:------------|
| `help_dispatch(command)` | Route to per-command help via naming convention |
| `help_global()` | Enhanced global help with categorized commands |
| `help_cmd_detect()` | Per-command: detect |
| `help_cmd_status()` | Per-command: status |
| `help_cmd_add_rule()` | Per-command: add-rule (full options reference) |
| `help_cmd_remove_rule()` | Per-command: remove-rule |
| ... | (17 total per-command help pages) |

**Design:** Per-command help bypasses `_initialize()` for instant response — no root required, no firewall detection.

---

## Entry Point

### apotropaios.sh

**Purpose:** CLI parsing, initialization, command dispatch.

**Flow:**
1. Determine script location (`APOTROPAIOS_BASE_DIR`)
2. Source all 24 library modules in dependency order
3. Parse global options (`--backend`, `--log-level`, `--help`, `--version`)
4. Check for per-command `--help` (bypass initialization)
5. Call `_initialize()` — logging, security, detection, rule index, backup
6. Dispatch to command handler or interactive menu

**CLI flags added in v1.1.3:** `--conn-state`, `--log-prefix`, `--log-level`, `--limit`, `--limit-burst`

---

## Global Variable Conventions

| Pattern | Usage | Example |
|:--------|:------|:--------|
| `APOTROPAIOS_*` | Framework config/state | `APOTROPAIOS_VERSION`, `APOTROPAIOS_LOG_FILE` |
| `OS_DETECTED_*` | OS detection results | `OS_DETECTED_ID`, `OS_DETECTED_PKG_MANAGER` |
| `FW_DETECTED_*` | Firewall detection (assoc arrays) | `FW_DETECTED_INSTALLED[iptables]` |
| `FW_ACTIVE_BACKEND` | Currently selected backend | `iptables` |
| `RULE_CREATE_ID` | Last created rule UUID | UUID string |
| `E_*` | Exit codes (readonly) | `E_SUCCESS`, `E_RULE_INVALID` |
| `LOG_LEVEL_*` | Log level constants (readonly) | `LOG_LEVEL_INFO` |
| `PATTERN_*` | Validation patterns (readonly) | `PATTERN_SAFE_DIR` |
| `COLOR_*` | Terminal colors (readonly) | `COLOR_RED`, `COLOR_RESET` |
| `_*` | Internal/private (not public API) | `_CLEANUP_STACK` |

---

## Error Code Reference

| Code | Constant | Meaning |
|:-----|:---------|:--------|
| 0 | `E_SUCCESS` | Operation succeeded |
| 1 | `E_GENERAL` | General error |
| 2 | `E_USAGE` | Usage/argument error |
| 3 | `E_PERMISSION` | Insufficient privileges |
| 10 | `E_OS_UNSUPPORTED` | OS not in supported list |
| 11 | `E_FW_NOT_FOUND` | Firewall not installed |
| 12 | `E_FW_NOT_RUNNING` | Firewall not active |
| 13 | `E_FW_INSTALL_FAIL` | Installation failed |
| 20 | `E_RULE_INVALID` | Rule validation failed |
| 21 | `E_RULE_EXISTS` | Duplicate rule |
| 22 | `E_RULE_NOT_FOUND` | Rule not in index |
| 23 | `E_RULE_APPLY_FAIL` | Backend application failed |
| 24 | `E_RULE_REMOVE_FAIL` | Backend removal failed |
| 25 | `E_RULE_IMPORT_FAIL` | Import failed |
| 30 | `E_BACKUP_FAIL` | Backup creation failed |
| 31 | `E_RESTORE_FAIL` | Restore failed |
| 40 | `E_VALIDATION_FAIL` | Input validation failed |
| 50 | `E_LOG_FAIL` | Logging initialization failed |
| 51 | `E_LOG_HANDLE_LOST` | Log file descriptor lost |
| 60 | `E_LOCK_FAIL` | Lock acquisition failed |
| 70 | `E_INTEGRITY_FAIL` | Checksum mismatch |

---

## Constants Reference

### Rule Constants

| Constant | Values |
|:---------|:-------|
| `RULE_ACTIONS[]` | accept, drop, reject, log, masquerade, snat, dnat, return |
| `RULE_TERMINAL_ACTIONS[]` | accept, drop, reject, masquerade, snat, dnat, return |
| `RULE_NON_TERMINAL_ACTIONS[]` | log |
| `RULE_CONN_STATES[]` | new, established, related, invalid, untracked |
| `RULE_LOG_LEVELS[]` | emerg, alert, crit, err, warning, notice, info, debug |
| `RULE_DIRECTIONS[]` | inbound, outbound, forward |
| `RULE_STATES[]` | active, inactive, pending, expired |
| `RULE_DURATION_TYPES[]` | permanent, temporary |
| `RULE_MIN_TTL_SECONDS` | 60 (1 minute) |
| `RULE_MAX_TTL_SECONDS` | 2592000 (30 days) |

### Security Constants

| Constant | Value | Description |
|:---------|:------|:------------|
| `SECURE_UMASK` | 077 | Default umask |
| `SECURE_DIR_PERMS` | 700 | Directory permissions |
| `SECURE_FILE_PERMS` | 600 | File permissions |
| `MAX_INPUT_LENGTH` | 4096 | Maximum input string length |
| `PATTERN_SAFE_DIR` | `^[a-zA-Z0-9/_. ~:+-]+$` | Whitelist for directory paths |
| `PATTERN_SAFE_PATH` | `^[a-zA-Z0-9/_. ~:+-]+$` | Whitelist for file paths |

---

## Testing Architecture

### Test Organization

```
tests/
├── helpers/
│   └── test_helper.bash       # Sourced at FILE level (not in setup)
├── unit/                       # Pure function tests (234 tests)
│   ├── validation.bats (88)
│   ├── logging.bats (28)
│   ├── os_detect.bats (20)
│   ├── fw_detect.bats (18)
│   ├── security.bats (23)
│   ├── errors.bats (24)
│   ├── rule_engine.bats (19)
│   └── backup.bats (14)
├── integration/                # Multi-function flow tests (93 tests)
│   ├── lifecycle.bats (22)
│   ├── import_export.bats (10)
│   ├── cli.bats (29)
│   └── help_system.bats (32)
├── security/                   # CWE-mapped security tests (48 tests)
│   └── injection.bats (48)
└── fixtures/
    ├── sample_rules.conf
    └── invalid_rules.conf
```

**Total: 375 tests across 13 files**

### Critical Test Patterns

- Source libraries at **file level** in test_helper.bash, never inside `setup()`
- Reset associative arrays with `unset VAR; declare -gA VAR=()`, never `VAR=()`
- Security tests are CWE-mapped: each test name starts with the CWE ID it verifies

---

## CI/CD Pipeline

### CI Stages (ci.yml)

1. **Syntax Check** — `bash -n` on all 25 shell files
2. **ShellCheck Lint** — Static analysis at warning severity
3. **Security Scan** — Dangerous pattern detection + 48 security tests
4. **Unit Tests** — Matrix: Ubuntu 22.04, 24.04
5. **Integration Tests** — Matrix: Ubuntu 22.04, 24.04
6. **Distro Tests** — Containers: Debian 12, Kali, Rocky 9, AlmaLinux 9, Arch (all test categories)
7. **Test Summary** — Aggregated results in GitHub Step Summary

### Release Pipeline (release.yml)

1. Version tag verification (tag must match constants.sh)
2. Full test suite + security gate
3. Distribution build (`make dist`)
4. GitHub Release with auto-generated notes
