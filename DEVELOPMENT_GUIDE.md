# Apotropaios — Development Guide

> Guide for contributors and developers working on the Apotropaios framework.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Development Workflow](#development-workflow)
3. [Coding Standards](#coding-standards)
4. [Testing](#testing)
5. [Security Testing](#security-testing)
6. [Known Pitfalls](#known-pitfalls)
7. [Adding a New Firewall Backend](#adding-a-new-firewall-backend)
8. [Adding a New Validator](#adding-a-new-validator)
9. [Makefile Reference](#makefile-reference)
10. [CI/CD Pipeline](#cicd-pipeline)
11. [Release Process](#release-process)

---

## Getting Started

```bash
# Clone the repository
git clone https://github.com/Sandler73/Apotropaios-Firewall-Manager.git
cd apotropaios

# Automated setup (installs BATS, checks ShellCheck)
make dev-setup

# Or manual setup:
git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats
sudo /tmp/bats/install.sh /usr/local

# Install ShellCheck
sudo apt-get install shellcheck    # Debian/Ubuntu/Kali
sudo dnf install ShellCheck        # RHEL family
sudo pacman -S shellcheck          # Arch

# Run the full test suite
make test              # 380 tests: lint + unit + integration + security

# Check all dependencies
make check-deps

# View project metrics
make metrics
```

---

## Development Workflow

1. Create a feature branch from `develop`
2. Make changes following the coding standards below
3. Run `make lint` — fix all ShellCheck issues
4. Run `make test` — all 380 tests must pass
5. Add tests for new functionality (unit, integration, or security as appropriate)
6. Update documentation: `docs/changelog.md`, `docs/wiki/Changelog.md`, help text, README if user-facing
7. Update `tasks/sync_function.md` if module dependencies changed
8. Submit a pull request to `develop` using the PR template

---

## Coding Standards

### Shell Compatibility

- Target: Bash 4.0+
- Use `#!/usr/bin/env bash` shebang
- Use `set -euo pipefail` in the main entry point only
- All arithmetic under `set -e` must use `|| true`: `((count++)) || true`
- Never use brace expansion in Makefiles or `/bin/sh` context
- Never use complex regex character classes in `[[ =~ ]]` — they have version-dependent behavior (BUG-009). Use whitelist regex or glob patterns instead.

### Naming Conventions

| Pattern | Usage | Example |
|:--------|:------|:--------|
| `fw_BACKEND_action()` | Firewall backend functions | `fw_iptables_add_rule()` |
| `rule_action()` | Rule engine functions | `rule_create()` |
| `validate_type()` | Input validators | `validate_port()` |
| `log_level()` | Logging functions | `log_info()` |
| `security_action()` | Security functions | `security_generate_uuid()` |
| `util_action()` | Utility functions | `util_trim()` |
| `_internal_func()` | Private/internal functions | `_fw_require_backend()` |
| `UPPER_CASE` | Readonly constants | `E_SUCCESS` |
| `_UPPER_CASE` | Private globals | `_CLEANUP_STACK` |

### Function Design

- Single responsibility per function
- Parameter validation at the top: `local param="${1:?function_name requires param}"`
- Return codes as contracts: 0=success, non-zero=specific error code from constants
- Use `return` in library functions, never `exit` (except in entry point)
- Document with header block:

```bash
# ==============================================================================
# function_name()
# Description:  What this function does.
# Parameters:   $1 - Parameter description
#               $2 - Optional parameter (default: value)
# Returns:      0 on success, E_CODE on failure
# ==============================================================================
```

### Input Validation

- Validate at the boundary — the moment user input enters the code
- Whitelist patterns, never blacklists
- Shell metacharacters detected via `_contains_shell_meta()` using portable glob patterns
- Never interpolate raw input into commands or file paths
- All firewall commands built using bash arrays, never string interpolation

### Source Guards

Every library module must prevent double-sourcing:

```bash
[[ -n "${_APOTROPAIOS_MODULE_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_MODULE_LOADED=1
```

The main entry point uses:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### Variable Quoting

Quote every variable expansion. The only exception is intentional word splitting, which must be commented.

### Logging

- Log before and after significant operations
- Include context (module name) in every log call
- Never log sensitive data (passwords, keys, tokens are auto-masked)
- Use structured format: `[timestamp] [LEVEL] [context] [cid:ID] message`

### Error Handling

- Trap EXIT, not just signals
- Preserve exit codes in cleanup handlers
- Use idempotent cleanup (safe to call multiple times)
- Register cleanup functions via `error_register_cleanup()`
- Menu functions must validate input BEFORE calling engine functions (engine uses `${1:?}` which exits the shell on empty params)

### ShellCheck Compliance

- All code must pass ShellCheck with zero warnings
- Use `.shellcheckrc` for project-wide suppression with documented rationale
- Never suppress a warning you don't understand

---

## Testing

### Test Organization

```
tests/
├── helpers/
│   └── test_helper.bash       # Sources libs at FILE level, resets globals in setup()
├── fixtures/
│   ├── sample_rules.conf      # 5 valid rules for import testing
│   └── invalid_rules.conf     # 5 invalid entries for rejection testing
├── unit/                       # Pure function tests (234 tests, 8 files)
├── integration/                # Multi-function flow tests (98 tests, 4 files)
└── security/                   # CWE-mapped security tests (48 tests, 1 file)
```

### Test Rules

1. Unit tests test pure functions directly — no stubs needed
2. No test depends on another test's state
3. Each test file loads the helper: `load '../helpers/test_helper'`
4. Fixtures are read-only — copy to temp before modifying
5. Test names follow `function: behavior` format
6. Test the contract (return codes, output), not implementation details

### Writing Tests

```bash
# Simple return code test
@test "validate_port: rejects port above 65535" {
    run validate_port "70000"
    [ "$status" -eq 1 ]
}

# Output verification
@test "security_generate_uuid: returns 36-character UUID" {
    local uuid
    uuid="$(security_generate_uuid)"
    [ "${#uuid}" -eq 36 ]
}
```

For functions that modify global state, avoid `run` (which creates a subshell):

```bash
@test "rule_state_set: tracks active state" {
    rule_state_set "${test_id}" "active" "permanent" "0" 2>/dev/null
    local state
    state="$(rule_state_get "${test_id}")"
    [ "${state}" = "active" ]
}
```

### Test Coverage Expectations

| Change Type | Required Tests |
|:------------|:---------------|
| New function | Unit tests: valid input, invalid input, edge cases |
| Bug fix | Regression test that would have caught the bug |
| Security change | Tests in `tests/security/` mapped to CWE IDs |
| New CLI flag | CLI integration test |
| Menu changes | Help system test (if help text updated) |

---

## Security Testing

Security tests in `tests/security/injection.bats` are mapped to CWE IDs:

```bash
@test "CWE-78: sanitize_input strips semicolons" {
    run sanitize_input "safe;whoami"
    [[ "$output" != *";"* ]]
}

@test "CWE-732: security_create_temp_file has 600 permissions" {
    local tmpf
    tmpf="$(security_create_temp_file "test")"
    local perms
    perms="$(stat -c '%a' "${tmpf}")"
    [ "${perms}" = "600" ]
    rm -f "${tmpf}" 2>/dev/null || true
}
```

### CWE Coverage

| CWE | Category | Tests |
|:----|:---------|------:|
| CWE-78 | OS Command Injection | 12 |
| CWE-22 | Path Traversal | 5 |
| CWE-20 | Input Validation | 14 |
| CWE-117/532 | Log Injection / Sensitive Data | 6 |
| CWE-732 | Insecure Permissions | 4 |
| CWE-377 | Insecure Temp File | 2 |
| CWE-200 | Information Disclosure | 1 |
| — | Cryptographic Integrity | 2 |
| — | Advisory Locking | 2 |

### Static Analysis

```bash
make security-scan    # 6 pattern checks (no external tools beyond grep)
```

Checks for: eval with variable expansion, hardcoded /tmp paths, permissive file modes, unquoted variables in firewall commands, insecure downloads, hardcoded credentials.

---

## Known Pitfalls

### BATS Associative Arrays

Source libraries at **file level** in `test_helper.bash`, not inside `setup()`. Sourcing inside `setup()` creates arrays local to that function — they lose the `-A` attribute when setup returns.

Reset associative arrays in `setup()` with `unset VAR; declare -gA VAR=()`, never `VAR=()` (which strips the `-A` attribute in subshells).

### Menu Input Validation

Menu functions must validate input (UUID format, file path existence) BEFORE calling engine functions. Engine functions use `${1:?message}` which causes bash to **exit the entire shell** on empty parameters — not just return.

Pattern: `func args && _rc=0 || _rc=$?` to catch errors without propagation.

### Regex Portability

Never use complex regex character classes like `[;|&\`$(){}\\<>!#]` in `[[ =~ ]]` — they have version-dependent behavior across bash ERE engines. Use:
- **Whitelist regex** for path validation: `[[ "${path}" =~ ^[a-zA-Z0-9/_.-]+$ ]]`
- **Glob patterns** for metacharacter detection: `[[ "${s}" == *";"* ]]` (per-character)

### Compound Actions

When adding features that map to different native implementations per backend, validate the superset at the engine layer, then let each backend adapter translate to its native form. Never force one backend's limitations on the validation layer.

When a function creates multiple system resources (e.g., iptables creates separate LOG + terminal rules for `log,drop`), the corresponding removal function MUST remove ALL of them.

### tr Character Class Hyphen Placement (BUG-010)

In `tr` character classes, hyphen (`-`) MUST be the first or last character to be treated as literal. Between any two characters, it creates a range. If the range is descending (higher ASCII → lower), GNU tr rejects the entire class and produces **empty output** — silently destroying all input data.

```bash
# WRONG — /-+ is a descending range (ASCII 47→43), tr errors out
tr -cd 'a-zA-Z0-9 .,_:/-+=@~%'

# CORRECT — hyphen at end is always literal
tr -cd 'a-zA-Z0-9 .,_:/+=@~%-'
```

### eval Usage

Avoid `eval` for file descriptor operations. Use literal FD numbers: `exec 3>>"${file}"` instead of `eval "exec ${FD}>>'${file}'"`. The eval form embeds the file path inside an evaluated string where special characters (single quotes) can break quoting.

### nft File Mode (-f)

Never write user-influenced data to a file processed by `nft -f`. In file mode, nft interprets semicolons and newlines as command separators, creating a command injection vector. Use direct argument-based execution only.

### Security Test Integrity

Never use `|| fallback` in security tests. If the function under test doesn't exist or fails to execute, the test must fail — not silently degrade to an untested code path.

### Subshell Capture and /dev/tty Reads

Never use `result="$(func_that_reads_tty)"` — the `$()` creates a subshell where `read -r var </dev/tty` has I/O issues (prompt may not display, read may hang indefinitely). Use **nameref** parameters instead: `func_that_reads_tty result_var "label"` with `local -n _ref="$1"` inside the function.

### Confirmation Prompts in Menu Context

`util_confirm()` writes its prompt to stderr. In the interactive menu, all wizard prompts write to stdout. If confirmation is mixed in, the stderr prompt is invisible — the user sees a hang. Use `_wizard_read` or direct stdout `printf` for all prompts within the wizard flow.

### Port-less Rules Require Extended Syntax

Both firewalld and ufw have "simple" rule paths that require a port. When no destination port is specified, always force the rich rule (firewalld) or extended syntax (ufw) path. Without this guard, the rule builder produces structurally invalid commands that the backend rejects.

### Firewalld Protocol Element

Firewalld rich rules require at least one filtering element between the family declaration and the action. When no port is specified, add `protocol value="tcp"` (or udp/sctp). Without this, the rule `rule family="ipv4" accept` is rejected as structurally invalid.

---

## Adding a New Firewall Backend

1. Create `lib/firewall/newfw.sh` with source guard
2. Implement all required functions following the naming convention `fw_newfw_*`:
   - `fw_newfw_add_rule`, `fw_newfw_remove_rule`, `fw_newfw_list_rules`
   - `fw_newfw_enable`, `fw_newfw_disable`, `fw_newfw_status`
   - `fw_newfw_block_all`, `fw_newfw_allow_all`, `fw_newfw_reset`
   - `fw_newfw_save`, `fw_newfw_reload`, `fw_newfw_export_config`
3. Handle compound actions natively (see iptables vs nftables patterns)
4. Handle connection tracking, log options, and rate limiting
5. Add to arrays in `constants.sh`: `SUPPORTED_FW_LIST`, `SUPPORTED_FW_BINARIES`, `SUPPORTED_FW_SERVICES`, `SUPPORTED_FW_PACKAGES`
6. Source the module in `apotropaios.sh`
7. Add detection logic in `fw_detect.sh`
8. Add backend config menu in `menu_main.sh`
9. Write unit tests
10. Update documentation

---

## Adding a New Validator

1. Add the function to `lib/core/validation.sh` with a documentation header
2. If it validates against a constant list, add the list to `constants.sh`
3. Add the validation call to `rule_create()` in `rule_engine.sh` if it's a rule field
4. Add the field to the menu wizard in `menu_main.sh`
5. Add the CLI flag to `apotropaios.sh`
6. Add the field to the rule record in `rule_engine.sh`
7. Update `help_cmd_add_rule()` in `help_system.sh`
8. Write tests in `tests/unit/validation.bats`
9. Update `tasks/sync_function.md`

---

## Makefile Reference

```bash
make help              # Full target listing with descriptions
make test              # Full suite: lint + unit + integration + security (380 tests)
make test-quick        # Unit only (fast feedback)
make test-report       # Detailed per-file pass/fail counts
make test-count        # Quick count without execution
make test-list         # List all test names
make test-sec          # Security tests only (48 tests)
make security-scan     # Static pattern analysis (6 checks)
make lint              # Syntax check + ShellCheck
make dist              # Build runtime distribution tarball
make dist-full         # Build full distribution (includes tests, CI, tasks)
make dist-venv         # Build venv package (portable, activate/deactivate)
make release           # Build ALL packages + unified SHA256SUMS.txt
make install           # Install to /opt/apotropaios (root required)
make uninstall         # Remove installation (preserves data)
make verify            # Check installed version
make dev-setup         # Install BATS + check ShellCheck
make check-deps        # Show all tool availability
make info              # Quick project summary
make metrics           # Detailed statistics
make clean             # Remove build artifacts
make clean-all         # Deep clean including all data
```

---

## CI/CD Pipeline

### CI Stages (ci.yml — runs on push and PR)

| Stage | Description | Depends On |
|:------|:------------|:-----------|
| 1. Syntax | `bash -n` on 25 shell files | — |
| 2. Lint | ShellCheck static analysis | Syntax |
| 3. Security Scan | Pattern detection + 48 security tests | Lint |
| 4. Unit Tests | Matrix: Ubuntu 22.04, 24.04 | Lint |
| 5. Integration Tests | Matrix: Ubuntu 22.04, 24.04 | Lint |
| 6. Distro Tests | Containers: Debian 12, Kali, Rocky 9, Alma 9, Arch | Lint |
| 7. Summary | Aggregated results, all-jobs gate | All above |

### Release Pipeline (release.yml — runs on version tags)

1. Version tag verification (tag must match `APOTROPAIOS_VERSION` in constants.sh)
2. Full test suite + security gate
3. `make release` — build all distribution packages (runtime, full, venv) with unified SHA-256 checksums
4. GitHub Release with auto-generated notes and artifacts

### Key CI Design Decisions

- `fail-fast: false` — all matrix entries run even if one fails
- `--allowerasing` for RHEL minimal container images
- `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` for action compatibility
- Test artifacts uploaded on all runs (14/30/90 day retention)
- `make` targets as single source of truth — CI never duplicates Makefile logic
- Concurrency control: cancel-in-progress for same-branch pushes

---

## Release Process

1. Update `APOTROPAIOS_VERSION` in `lib/core/constants.sh`
2. Update version in lifecycle test: `tests/integration/lifecycle.bats`
3. Update `docs/changelog.md` and `docs/wiki/Changelog.md`
4. Run full test suite: `make test`
5. Run security scan: `make security-scan`
6. Update `tasks/todo.md` and `tasks/todo_complete.md`
7. Commit: `git commit -m "release: v1.x.x"`
8. Tag: `git tag v1.x.x`
9. Push: `git push origin main --tags`
10. The release workflow automatically builds packages and creates a GitHub Release
