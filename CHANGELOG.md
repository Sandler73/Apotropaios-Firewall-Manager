# Changelog

All notable changes to the Apotropaios Firewall Manager are documented here.

## [1.1.10] - 2026-03-29

### Automatic Rule Expiry and Proactive Alerts
- **Background expiry monitor (`_expiry_monitor_loop`):** Runs every 30 seconds while the interactive menu is active. Auto-deactivates expired temporary rules without requiring manual intervention. Writes terminal alerts to `/dev/tty` for rules within 10 minutes of expiring, including rule ID, description, and time remaining.
- **Inline expiry alerts (`_menu_check_expiry_alerts`):** Every time the main menu renders, scans for near-expiry (< 10 minutes) and already-expired temporary rules. Displays color-coded warnings inline in the menu with guidance to extend via the Rule Expiry Watcher.
- **Per-iteration expiry check:** `rule_check_expired()` now runs on every main menu loop iteration in addition to the background monitor, ensuring expired rules are deactivated within seconds of returning to the main menu.
- **Clean lifecycle:** Monitor starts on menu entry (`_expiry_monitor_start`), stops on exit (`_expiry_monitor_stop`), and is registered with the framework's cleanup stack (`error_register_cleanup`) for signal-safe termination.
- **Double-start guard:** `_expiry_monitor_start()` checks if a monitor is already running before launching a second instance.

## [1.1.9] - 2026-03-29

### Bug Fixes
- **Firewalld status showed only default zone:** `fw_firewalld_status()` used `firewall-cmd --list-all` which displays only the default zone. Replaced with `--get-active-zones` + `--list-all-zones` to show full configuration across all zones.
- **Firewalld config submenu zone selector hung:** `_firewalld_select_zone()` ran inside `$()` command substitution which creates a subshell — the `read` from `/dev/tty` inside a subshell had I/O issues causing the prompt to not display and the function to appear to hang. Fix: rewrote with nameref parameter (no subshell). Also added cancel keyword detection (`q`/`quit`/`cancel`/`back`/`b`) — previously "q" passed through as a zone name to `firewall-cmd` producing "Error: INVALID_ZONE: q".
- **UFW rule creation failed without destination port:** Simple syntax path produced `ufw allow comment apotropaios:UUID` which UFW rejected (requires at least a port). Root cause: same as previous firewalld fix — no guard for port-less rules. Fix: forced extended syntax path (`ufw allow in proto tcp from any to any`) when no destination port is given. Extended syntax handles protocol-only rules correctly.
- **UFW error logging:** Replaced `2>/dev/null` with stderr capture on add/remove operations. Failed rules now log the actual `ufw` error message.

## [1.1.8] - 2026-03-28

### Firewalld Full Zone Support
- **Dynamic zone selection in rule wizard:** Replaced freeform text input with numbered zone list from `firewall-cmd --get-zones`. Default zone highlighted. Accepts zone number or name. Falls back to text input if firewall-cmd unavailable.
- **Reset function cleans all zones:** `fw_firewalld_reset()` now iterates all available zones instead of hardcoding "public". Removes ports and rich rules from every zone before reload.
- **Config submenu zone-aware (6→8 options):** Options 4 (services), 5 (rich rules), 6 (full config), and 7 (runtime vs permanent) now prompt for zone selection via `_firewalld_select_zone()` helper. New option 8: Change default zone. All queries use `--zone=` parameter.
- **`_firewalld_select_zone()` helper:** Reusable zone picker used by both the config submenu and the rule wizard. Shows numbered list with default zone marker.

### iptables Config Submenu Table Selection
- **Option 5 rewritten:** "Show active table summary" (filter-only) replaced with "Show rules in table" — presents numbered table selector (filter/nat/mangle/raw/security) then shows full rules for the selected table
- **Option 7 added:** "Show all tables (full)" — iterates all 5 tables with full `iptables -L -n --line-numbers` output per table. Previous option 6 (chain policies summary) retained for quick overview.

## [1.1.7] - 2026-03-28

### Bug Fixes
- **Immutable snapshot verify false positive:** `immutable_verify()` reported "All snapshots verified" when no snapshots existed. Root cause: function returned 0 (success) when `checked=0` and `failed=0`, and menu interpreted return 0 as verified. Fix: function now detects empty snapshot directory/no integrity files and returns 2 with explicit "No immutable snapshots exist" message. Menu handles all 3 return codes (0=verified, 1=failed, 2=none exist).
- **Immutable snapshot list empty state:** `immutable_list()` now shows "No immutable snapshots exist" when the directory is empty, instead of printing a header with count 0 and no entries.
- **Rule creation confirmation invisible:** `util_confirm()` wrote the "Apply this rule?" prompt to stderr while all wizard prompts wrote to stdout. In the menu context, the stderr prompt was invisible — the user saw a hang after the summary, and pressing Enter triggered the default "n" → "Rule creation cancelled." Fix: replaced `util_confirm` with `_wizard_read` for the confirmation step, keeping all prompts on stdout.
- **Expired rules check reported "Done":** Menu option 9 (Check expired rules) printed "Done" regardless of whether expired rules existed. Now prints "No expired rules." (green) when none found, or "Processed expired rules." when some were deactivated.
- **Firewalld rich rule builder missing protocol element:** Rules created without a destination port produced invalid rich rules like `rule family="ipv4" accept` (no filtering element). Root cause: the builder only added protocol for ICMP, not for tcp/udp/sctp. Fix: added `protocol value="${protocol}"` element for all non-port, non-all protocols. Also forced the rich rule path for all port-less rules (the simple `--add-port` path silently did nothing without a port).
- **Firewalld error logging:** Replaced `2>/dev/null` with stderr capture on all three `firewall-cmd` invocations (add rich rule, add port, remove rule). Failed rules now log the actual error message.

### Rule Creation Wizard Cancel Support
- **`_wizard_read()` helper:** New cancel-aware input function detects `q`, `quit`, `cancel`, `back`, or `b` (case-insensitive) at any wizard prompt
- All 29 input prompts across all 5 backend paths (including the final confirmation) route through `_wizard_read()` — no partial rules are created on cancellation
- Cancel hint shown at wizard start: "Type q, quit, cancel, or back at any prompt to abort"
- Cancellation prints "Rule creation cancelled." and returns cleanly to the Rule Management menu

## [1.1.6] - 2026-03-28

### Interactive Mode Flag
- **`--interactive`:** New global CLI flag provides explicit separation between interactive menu mode and direct CLI command execution
- Mutually exclusive with `--non-interactive` (clear error: "mutually exclusive") and CLI commands (clear error: "cannot be combined with a command")
- Three ways to launch menu (priority order): `--interactive` (preferred), `menu` subcommand (backward compatible), no arguments (backward compatible)
- Help system updated with Operation Modes section explaining both modes
- `_show_usage()` updated with Operation Modes display and `--interactive` in global options and examples

### ShellCheck Compliance
- **SC2015:** Replaced 4 `A && B || C` patterns with proper if/then/else (backup.sh, firewalld.sh, menu_main.sh)
- **SC2261:** Fixed competing stderr redirections in logging.sh — `>&"${FD}"` → `1>&"${FD}"`
- **SC2155:** Separated `local` declaration from command substitution in logging.sh
- **SC1125:** Fixed invalid shellcheck directive (em dash broke key=value parsing) in nftables.sh
- **SC2120:** Added disable directive for intentionally optional parameter in security.sh
- **SC2183:** Added missing printf color arguments in menu_main.sh
- **SC1091:** Added global disable for cross-file source resolution in .shellcheckrc

### CI/CD Updates
- **Node.js 24 migration:** `actions/checkout` v5→v6, `actions/upload-artifact` v4→v6, `actions/download-artifact` v4→v6
- **Security scan refinement:** CI pattern scan rewritten with file-based eval exclusions (audited files: security.sh, errors.sh, utils.sh) and context-aware command substitution filtering
- **`softprops/action-gh-release@v2`:** Remains at v2 (no Node 24 build available); `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` env var ensures compatibility

### Packaging Expansion
- **`make dist-venv`:** New target generates portable virtual environment package with `activate.sh` and `bin/apotropaios` wrapper
- **`make release`:** New unified target builds all 3 packages (runtime, full, venv) with single SHA256SUMS.txt
- **`dist-full` fix:** Now generates its own SHA256SUMS.txt (was using `>>` append which failed standalone)
- **release.yml:** Updated to use `make release`, attaches all 3 packages, adds checksum verification step
- **Makefile:** 40 targets (was 38)

### Testing (380 tests — all passing)
- CLI: 34 (was 29 — 5 new `--interactive` flag validation tests)
- Unit: 234, Integration: 98, Security: 48

### Documentation
- README.md rewritten to 1,070+ lines matching production-quality reference standard
- CODE_OF_CONDUCT.md expanded to 441 lines (responsible use policy, contributor rights, appeal process, IP provisions)
- LICENSE merged to 412 lines with 12 supplementary sections (firewall disclaimer, assumption of risk, export compliance)
- All repository URLs updated to `Sandler73/Apotropaios-Firewall-Manager`

## [1.1.5] - 2026-03-27

### Security Audit Fixes (4 Critical, 6 High — all resolved)

#### Critical Fixes
- **C1: Compound action removal left orphaned iptables LOG rules.** `fw_iptables_remove_rule()` rewritten to parse compound actions and issue separate `-D` commands for both LOG and terminal rules, mirroring add logic. Also re-validates all parameters from index before constructing commands.
- **C2: Security tests CWE-117/532 were false passes.** Tests called `_log_sanitize()` (nonexistent) — the `|| fallback` silently used unsanitized data. Fixed to call `_log_sanitize_message()`. All 6 tests verified genuinely passing.
- **C3: nftables `table_family` parameter not validated.** Added `validate_table_family()` accepting only `inet/ip/ip6/arp/bridge/netdev`. Wired into `fw_nftables_add_rule()`.
- **C4: nftables `-f` file fallback was a command injection vector.** In file mode, nft interprets semicolons as command separators. Removed fallback entirely — nft now runs via direct command only.

#### High Fixes
- **H1: Eliminated all `eval` from logging.** Replaced 6 `eval "exec FD"` callsites with literal `exec 3>>` / `exec 3>&-`. Zero eval remaining in logging module.
- **H2: Race condition in lock acquisition.** Lock acquisition now uses `flock(1)` when available for atomic locking (no TOCTOU race). Falls back to noclobber with PID validation.
- **H3: `sanitize_input()` used blacklist instead of whitelist.** Rewritten from `tr -d 'bad_chars'` to `tr -cd 'good_chars'` — keeps only known-safe characters (alphanumeric, space, dot, hyphen, underscore, colon, slash, comma, plus, equals, at, tilde, percent).
- **H4: `fw_iptables_remove_rule()` did not re-validate parameters.** Combined with C1 — all parameters from the rule index are now re-validated before constructing `-D` commands.
- **H5: `make security-scan` had false positives.** Rewrote all 6 checks to capture grep output to variable before testing (fixed `head -5` returning 0 on empty input). Also excluded log sanitization patterns and log_info messages from triggers. Now reports 4 passed, 2 legitimate warnings.
- **H6: `_log_sanitize_message()` pattern coverage incomplete.** Expanded with 4 pattern families: key=value, key="quoted value", JSON (`"key": "value"`), HTTP Authorization headers (`Bearer/Basic/Digest/Token`). Added 3 new security tests.

### Testing (375 tests — all passing at time of v1.1.5 release)
- Security: 48 (was 45 — 3 new log sanitization tests for quoted values, JSON, HTTP headers)
- Validation: 88 (was 69 — 9 validate_table_family + 10 sanitize_input whitelist preservation)
- Unit: 234, Integration: 93

### Regression Fix
- **BUG-010:** Fixed critical regression from H3 audit fix — `sanitize_input()` whitelist `tr -cd` class had misplaced hyphen (`/-+`) causing GNU `tr` to fail and return empty string on ALL inputs. Every menu selection returned "Invalid option." Fix: hyphen moved to last position in tr class (`%-`). Removed `\n\t` from single-quoted string (were literal backslash+n, not actual newline/tab).

## [1.1.4] - 2026-03-25

### Bug Fixes
- **BUG-009**: Fixed critical startup crash: "Invalid log directory path: path rejected by security check"
  - Root cause: PATTERN_SHELL_META regex `[;|&\`$(){}\\<>!#]` has version-dependent behavior across bash ERE engines — on Kali 2026.1 it rejected every path including the framework's own data/logs directory
  - Fix (3-layer):
    1. Constants: replaced fragile regex with PATTERN_SAFE_DIR whitelist (`^[a-zA-Z0-9/_. ~:+-]+$`)
    2. Logging: log_init() uses whitelist validation; error messages now include the actual rejected path
    3. Validation: new portable `_contains_shell_meta()` helper using glob patterns instead of regex character classes — fully portable across all bash versions
  - All 3 callsites converted: hostname, file path, and description validators
  - PATTERN_SAFE_PATH expanded to allow spaces, tildes, colons, plus signs for real-world paths

### Security Testing (45 new tests)
- New test suite: `tests/security/injection.bats` with 45 CWE-mapped security tests
  - CWE-78 (OS Command Injection): 12 tests — sanitize_input strips semicolons, backticks, dollar signs, pipes, ampersands, parentheses, braces, redirects; _contains_shell_meta detection coverage
  - CWE-22 (Path Traversal): 5 tests — validates rejection of ../ traversal patterns while allowing dots in filenames
  - CWE-20 (Input Validation): 14 tests — boundary testing for ports (0, 65536, negative, non-numeric), IP octets > 255, injection in IPs, CIDR prefix > 32, invalid protocols, non-UUID rule IDs, dual terminal actions, invalid connection states, log prefix length, rate limit format
  - CWE-117/532 (Log Injection / Sensitive Data): 3 tests — password field masking, token field masking, non-sensitive data preservation
  - CWE-732 (Insecure Permissions): 4 tests — temp file 600, temp dir 700, security_secure_file sets 600, security_secure_dir sets 700
  - CWE-377 (Insecure Temp File): 2 tests — uniqueness and non-predictability of temp file paths
  - CWE-200 (Information Disclosure): 1 test — validate_file_path does not leak system paths in output
  - Cryptographic Integrity: 2 tests — SHA-256 checksum format validation, tamper detection
  - Advisory Locking: 2 tests — stale lock cleanup (dead PID), lock file PID verification

### CI/CD Pipeline Expansion
- CI workflow (`ci.yml`) rewritten with 6 stages:
  1. Syntax Check (fastest gate)
  2. ShellCheck Lint
  3. Security Scan — dangerous pattern detection + security test execution with artifact upload
  4. Unit Tests — matrix across Ubuntu 22.04 and 24.04
  5. Integration Tests — matrix across Ubuntu 22.04 and 24.04
  6. Multi-Distro Container Tests — Debian 12, Kali Rolling, Rocky 9, AlmaLinux 9, Arch; runs unit + integration + security on all distros
  7. Test Summary — aggregated results in GitHub Step Summary
- Release workflow (`release.yml`) — version tag verification, full test suite + security gate, distribution build, GitHub Release with auto-generated release notes
- Concurrency control: cancel-in-progress for same-branch pushes
- Security-events write permission for scan result uploads
- Test artifact upload on all runs with 14/30/90 day retention

### GitHub Community Files
- Issue templates (4 templates + config):
  - Bug Report (`bug_report.yml`): 174 lines, 14 form fields (version, OS dropdown, bash version, backend, severity, component, description, steps, expected/actual, logs, environment, checklist)
  - Feature Request (`feature_request.yml`): 108 lines, 10 fields (category, priority, problem, solution, alternatives, use case, willingness to implement, additional context, checklist)
  - Security Vulnerability (`security_vulnerability.yml`): 116 lines, 10 fields (severity with private reporting redirect, CWE category dropdown, affected versions, description, PoC, impact, remediation, references, checklist)
  - Documentation (`documentation.yml`): 99 lines, 7 fields (doc type dropdown with 25+ targets, issue type, section, description, suggestion, checklist)
  - Config (`config.yml`): Contact links to wiki, private security advisories, discussions
- FUNDING.yml: 92 lines covering all 12 GitHub-supported platforms (github, patreon, open_collective, ko_fi, buy_me_a_coffee, liberapay, issuehunt, polar, community_bridge, tidelift, thanks_dev, custom) with descriptions and configuration reference
- Pull Request Template: 105 lines, 10 sections (description, type of change with 10 categories, related issues, changes made, security checklist with 8 items, testing with 7-platform matrix, documentation checklist, code quality standards, backward compatibility, pre-merge checklist)

### Community Standards
- CONTRIBUTING.md: 270 lines, 12 sections — code of conduct reference, ways to contribute, getting started workflow, development environment setup, coding standards (source guards, function headers, quoting, arithmetic safety, input validation, naming conventions table), testing requirements with coverage expectations, security requirements, commit format guidelines (type/scope), pull request process with size guidelines, issue guidelines, documentation requirements, recognition policy
- CODE_OF_CONDUCT.md: 104 lines — Contributor Covenant v2.1 adapted for Apotropaios with security-specific provisions (coordinated disclosure requirement, malicious contribution policy, honest representation mandate), 4-tier enforcement ladder (correction → warning → temporary ban → permanent ban)
- SECURITY.md: 137 lines (existing — verified comprehensive)

### LICENSE Expansion
- MIT License with 11 supplementary sections (208 lines total):
  1. Disclaimer of Warranty — AS-IS/AS-AVAILABLE, no implied warranties, jurisdictional savings clause
  2. Limitation of Liability — no indirect/consequential/punitive damages, aggregate cap at $0
  3. Indemnification — user indemnifies authors against claims
  4. Security and Firewall Disclaimer — no guarantee of breach prevention, recommends independent verification
  5. Assumption of Risk — user acknowledges inherent risks, has necessary expertise
  6. Third-Party Software — not responsible for iptables/nftables/firewalld/ufw/ipset behavior
  7. No Professional Advice — not security/legal/compliance advice
  8. Export Compliance — user's responsibility
  9. Governing Law — primary copyright holder's jurisdiction
  10. Severability — invalid provisions modified to minimum enforceable extent
  11. Entire Agreement

### README.md
- 372 lines, 15 sections with back-to-top links on every section
- 35 shield badges: CI status (2), ShellCheck, version, license, bash version, test counts (3), maintenance, PRs welcome, last commit, issues, zero dependencies, platforms, firewalls, documentation, discussions, security
- Platform table: 7 distributions with individual distro shield badges, version, family, package manager, CI status
- Firewall table: 5 backends with individual shield badges and support status
- Full test breakdown table with category counts
- Security standards alignment table
- Documentation links table
- Support section with shields, help links, issue template links, diagnostic commands

### Makefile Expansion
- 38 targets organized into 7 sections with Unicode box-drawing headers
- New targets: `dist-full` (includes tests/CI/tasks), `uninstall` (preserves data directory), `dev-setup` (installs BATS + checks ShellCheck), `check-deps` (required/development/runtime tools), `info` (quick project summary), `metrics` (detailed statistics: code lines, net code lines, test count, wiki pages, CI workflows, issue templates, Makefile targets), `test-count` (quick count without execution), `test-list` (list all test names), `clean-all` (deep clean including all generated state), `test-help-system`, `test-sec`, `test-sec-injection`, `security-scan` (6 static pattern checks)
- Default target changed to `help` for discoverability
- Help output includes test counts per suite
- `dist` target now includes community files (README, LICENSE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY)
- `install` target now copies docs, creates /etc/apotropaios config directory, preserves existing config
- `verify` target shows version mismatch warnings

### Testing Summary (353 tests — all passing)
- Unit: 215 (validation 69, logging 28, os_detect 20, fw_detect 18, security 23, errors 24, rule_engine 19, backup 14)
- Integration: 98 (lifecycle 22, import_export 10, cli 29, help_system 32)
- Security: 45 (injection.bats — CWE-mapped)
- Across 13 test files

## [1.1.3] - 2026-03-23

### Features
- Compound firewall actions: rules now support comma-separated actions (e.g., log,drop log,accept log,reject)
  - iptables: creates separate LOG + terminal rules (correct iptables pattern)
  - nftables: combines in single rule expression (correct nft pattern)
  - firewalld: rich rule log clause + terminal action
  - ufw: extracts terminal action, enables logging separately
- Connection tracking state support: new,established,related,invalid,untracked
  - iptables: -m conntrack --ctstate; nftables: ct state expression
  - CLI: --conn-state flag; Menu: connection state prompt in wizard
- Log options: --log-prefix (max 29 chars), --log-level (syslog levels)
- Rate limiting: --limit (N/second|minute|hour|day), --limit-burst
- UFW backend config expanded: enable/disable app profiles with detection, set logging level (off/low/medium/high/full), set default policies

### Validation
- validate_rule_action: compound action support with terminal action count enforcement
- validate_conn_state: comma-separated connection state validation
- validate_log_prefix: 1-29 char alphanumeric validation
- validate_rate_limit: N/unit format validation

### Testing (308 tests)
- 22 new validation tests: compound actions (7), connection states (6), log prefix (3), rate limits (5), additional action types (1)
- Total: 308 tests across 12 files (215 unit + 98 integration)

## [1.1.2] - 2026-03-23

### Bug Fixes
- Fixed framework crash/exit when invalid input provided in Rule Management options 4-8
  - Root cause: `${1:?msg}` in engine functions causes bash to exit the shell (not return) on empty params
  - Fix: All menu functions now validate input format before calling engine functions
  - _menu_remove_rule: UUID format validation with descriptive red error messages
  - _menu_activate_rule: UUID validation + error code classification (not found, apply fail)
  - _menu_deactivate_rule: UUID validation + error code classification
  - _menu_import_rules: File existence/readability validation before calling rule_import_file
  - _menu_export_rules: Path validation, parent directory check, overwrite confirmation

### Enhancements
- Firewall Management option 1 renamed from "Select active backend" to "Select active firewall backend"
- New Firewall Management option 8 "Backend configuration" with 5 backend-specific submenus:
  - ipset (7 options): Check/view/save/load config, list active sets, create set, flush sets
  - iptables (7 options): Check/view/save/restore rules, table selector, chain policies, full table view
  - nftables (5 options): Check/view/save config, list tables, list chains
  - firewalld (8 options): Default zone, list/active zones, zone-aware services/rich rules/config/runtime-vs-permanent, change default zone
  - ufw (5 options): Check/view defaults, app profiles, logging level, config files
- Import rules: New sub-option to scan and list available rule files from directory
  - Supports .conf, .rules, .txt file types with size/date display
  - Default scan path: Apotropaios data/rules directory
- Export rules: Default output path to Apotropaios data/rules directory with timestamped filename
  - Auto-creates parent directory with confirmation
  - Overwrite protection with confirmation prompt

## [1.1.1] - 2026-03-23

### Features
- Progressive layered help system with 3 tiers:
  - Tier 1: Enhanced global help (--help) with categorized commands and color-coded output
  - Tier 2: Per-command help (COMMAND --help) for all 17 commands with Synopsis, Description, Options, Examples, Tips, Related Commands
  - Tier 3: In-app interactive menu help (existing)
- Per-command help bypasses framework initialization for instant response
- New module: lib/menu/help_system.sh with 17 detailed help pages
- help_dispatch() routing via naming convention (help_cmd_COMMAND)

### Testing
- Total: 286 tests across 12 test files (from 97 in v1.0.0)
- New unit tests: os_detect (20), fw_detect (18), security (23), errors (24), rule_engine (19), backup (14)
- New integration tests: import_export (10), cli (29), help_system (32)
- Added test fixtures: sample_rules.conf (5 valid rules), invalid_rules.conf (5 invalid entries)
- Expanded Makefile with 18 targets including per-suite test execution and test-report

### CI/CD
- Expanded CI pipeline: syntax check, ShellCheck lint, unit tests (2 Ubuntu versions), integration tests (2 Ubuntu versions), distro matrix (Debian 12, Kali, Rocky 9, AlmaLinux 9, Arch), final status gate
- Expanded release pipeline: version verification, full test gate, package build, GitHub Release
- Added feature and fix branch triggers, workflow_dispatch for manual runs
- Test artifacts uploaded on all runs with 30-day retention

### Infrastructure
- Added comprehensive .gitignore (editors, OS files, security credentials, runtime data, build artifacts)
- Added .gitkeep files for tracked empty directories

## [1.1.0] - 2026-03-22

### Bug Fixes
- Fixed ASCII banner displaying "Apptropaios" instead of "Apotropaios"
- Firewall detection now displays all 5 backends with installed/not-installed status
- Fixed rule creation failing on ipset backend (missing set_name prompt)
- Fixed Firewall Management status and list commands with permission error handling
- Changed default log level from DEBUG to INFO (suppresses cleanup debug messages on exit)
- System Information now re-detects firewall status on each display

### Enhancements
- Rule creation wizard: 5-step guided process with backend selection and backend-specific fields
- Renamed "List all rules" to "List all Apotropaios rules" for clarity
- Added "List existing System rules" — audits all installed firewall backends
- Added Rule Expiry Watcher with color-coded time remaining and timer extension
- Verified expired rule cleanup uses UUID-targeted removal
- Added comprehensive GitHub wiki documentation (15 pages with mermaid diagrams)
- Added `system-rules` CLI command
- Expanded test suite: 254 tests across 11 test files (8 unit + 3 integration)
- Expanded CI/CD: per-module test targets, test report generation, syntax-check stage
- Added comprehensive .gitignore
- Progressive layered help system: Tier 1 (global --help), Tier 2 (COMMAND --help for all 17 commands)
- Per-command help bypasses initialization for instant response
- help_system.sh: 17 detailed help pages with Synopsis, Description, Options, Examples, Tips, Related Commands

### Testing (286 tests)
- Unit: validation (47), logging (28), os_detect (20), fw_detect (18), security (23), errors (24), rule_engine (19), backup (14)
- Integration: lifecycle (22), import_export (10), cli (29)
- Test fixtures: sample_rules.conf, invalid_rules.conf

## [1.0.0] - 2026-03-21

### Added
- **Core Infrastructure:** Constants, structured logging (FD tracking, rotation, sanitization), error handling (signal traps, cleanup stack, retry/fallback), input validation (25+ whitelist validators), security controls (UUID, checksums, locking, variable scrubbing), common utilities
- **OS Detection:** Multi-method detection for Ubuntu, Kali, Debian 12, Rocky 9, AlmaLinux 9, Arch Linux with 4 fallback methods
- **Firewall Detection:** Version extraction and status check for firewalld, ipset, iptables, nftables, ufw
- **Firewall Backends:** Full implementations for iptables, nftables, firewalld, ufw, ipset with unified dispatch interface
- **Rule Engine:** Rule creation/removal/activation/deactivation with UUID tracking, persistent index, TTL-based temporary rules, automatic expiry checking
- **Rule Import/Export:** Configuration file import with validation (dry-run support), export with SHA-256 checksum sidecar
- **Backup System:** Timestamped compressed archives, automatic restore points, retention management, immutable snapshots with `chattr +i`
- **Installer:** Package installation and update via apt/dnf/pacman with automatic detection
- **Interactive Menu:** Full menu-driven interface with guided rule creation wizard
- **CLI Interface:** Complete command-line interface with sub-commands for all operations
- **Testing:** BATS test suite (unit + integration), ShellCheck linting
- **CI/CD:** GitHub Actions pipeline with multi-distro matrix (7 platforms), release automation
- **Documentation:** README, Usage Guide, Setup Guide, Developer Guide, Development Guide

### Security
- Whitelist input validation on all user-supplied data (OWASP CRG, CWE-20)
- Shell metacharacter injection protection
- Path traversal detection and rejection
- Secure file permissions (600/700) on all data files
- Advisory locking with stale lock detection and timeout
- Sensitive variable scrubbing on exit
- Log message sanitization (passwords, tokens masked)
- SHA-256 integrity verification on backups and imports
- Immutable filesystem attributes on critical snapshots
