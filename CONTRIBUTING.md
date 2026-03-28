# Contributing to Apotropaios

Thank you for your interest in contributing to Apotropaios. This guide covers how to participate effectively and what we expect from contributions.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Ways to Contribute](#ways-to-contribute)
- [Getting Started](#getting-started)
- [Development Environment](#development-environment)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Security Requirements](#security-requirements)
- [Commit Guidelines](#commit-guidelines)
- [Pull Request Process](#pull-request-process)
- [Issue Guidelines](#issue-guidelines)
- [Documentation](#documentation)
- [Recognition](#recognition)

## Code of Conduct

This project adheres to the [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold these standards. Please report unacceptable behavior via the channels described in that document.

## Ways to Contribute

- **Bug Reports** — File detailed reports with reproduction steps using the [Bug Report template](https://github.com/apotropaios-project/apotropaios/issues/new?template=bug_report.yml)
- **Feature Requests** — Propose new capabilities with use cases using the [Feature Request template](https://github.com/apotropaios-project/apotropaios/issues/new?template=feature_request.yml)
- **Security Reports** — See [SECURITY.md](SECURITY.md) for vulnerability reporting procedures
- **Code Contributions** — Submit pull requests for bugs, features, or improvements
- **Documentation** — Improve guides, wiki pages, code comments, or help text
- **Testing** — Run the framework on new distributions and report compatibility results
- **Review** — Review open pull requests and provide constructive feedback

## Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:
   ```bash
   git clone https://github.com/YOUR-USERNAME/apotropaios.git
   cd apotropaios
   ```
3. **Create a branch** from `develop`:
   ```bash
   git checkout develop
   git checkout -b feature/your-feature-name
   ```
4. **Set up** the development environment (see below)
5. **Make changes**, following the coding standards
6. **Test** your changes thoroughly
7. **Submit** a pull request to `develop`

## Development Environment

### Prerequisites

- Bash 4.0+ (`bash --version`)
- Git
- [BATS](https://github.com/bats-core/bats-core) (test framework)
- [ShellCheck](https://www.shellcheck.net/) (linter)

### Setup

```bash
# Install BATS
git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats
sudo /tmp/bats/install.sh /usr/local

# Install ShellCheck
sudo apt-get install shellcheck    # Debian/Ubuntu/Kali
sudo dnf install ShellCheck        # RHEL family
sudo pacman -S shellcheck          # Arch

# Verify the setup
make test
```

### Project Structure

```
apotropaios/
├── apotropaios.sh          # Entry point (CLI parsing, initialization)
├── lib/
│   ├── core/               # Foundation: constants, logging, errors, validation, security, utils
│   ├── detection/          # OS and firewall detection
│   ├── firewall/           # Backend implementations (iptables, nftables, firewalld, ufw, ipset)
│   ├── rules/              # Rule engine, index, state, import/export
│   ├── backup/             # Backup, restore, immutable snapshots
│   ├── install/            # Package installation/update
│   └── menu/               # Interactive menus and help system
├── tests/
│   ├── unit/               # Pure function tests
│   ├── integration/        # Multi-function flow tests
│   └── security/           # CWE-focused security tests
├── docs/                   # Documentation and wiki
└── .github/                # CI/CD, templates, funding
```

## Coding Standards

### Source Guards

Every module must prevent double-sourcing:

```bash
[[ -n "${_APOTROPAIOS_MODULE_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_MODULE_LOADED=1
```

### Function Headers

Every function must have a documentation block:

```bash
# ==============================================================================
# function_name()
# Description:  What this function does.
# Parameters:   $1 - Parameter description
#               $2 - Optional parameter (default: value)
# Returns:      0 on success, E_CODE on failure
# ==============================================================================
```

### Variable Quoting

Quote every variable expansion. No exceptions unless intentional word splitting (must be commented).

### Arithmetic Safety

Under `set -e`, all `(( ))` arithmetic must append `|| true`:

```bash
((count++)) || true
```

### Input Validation

- Validate at every trust boundary using `validate_*` functions
- Use whitelist patterns, never blacklists
- Shell metacharacters detected via `_contains_shell_meta()` (portable glob-based)
- Never interpolate raw input into commands or paths

### Naming Conventions

| Pattern | Usage | Example |
|---------|-------|---------|
| `fw_BACKEND_action()` | Firewall backend functions | `fw_iptables_add_rule()` |
| `rule_action()` | Rule engine functions | `rule_create()` |
| `validate_type()` | Input validators | `validate_port()` |
| `log_level()` | Logging functions | `log_info()` |
| `security_action()` | Security functions | `security_generate_uuid()` |
| `util_action()` | Utility functions | `util_trim()` |
| `_internal_func()` | Private/internal functions | `_fw_require_backend()` |
| `UPPER_CASE` | Readonly constants | `E_SUCCESS` |

## Testing Requirements

All contributions must pass the full test suite:

```bash
make test              # Lint + unit + integration + security (375 tests)
make test-quick        # Unit tests only (fast feedback)
make test-sec          # Security tests only
make security-scan     # Static pattern analysis
```

### Writing Tests

- Unit tests in `tests/unit/`, integration in `tests/integration/`, security in `tests/security/`
- **Source at file level** in test helper — never inside `setup()`
- **Reset associative arrays** with `unset VAR; declare -gA VAR=()` — never `VAR=()`
- Test the contract (return codes, output), not implementation details

### Coverage Expectations

- New functions: unit tests covering valid input, invalid input, and edge cases
- Bug fixes: regression test that would have caught the bug
- Security changes: tests in `tests/security/` mapped to CWE IDs

## Security Requirements

All code changes must satisfy the security checklist in the [PR template](.github/PULL_REQUEST_TEMPLATE.md):

- All user input validated through `validate_*` functions
- No raw input interpolated into commands or file paths
- File operations use secure permissions (600/700)
- Sensitive data never written to logs
- Error messages do not leak internal paths
- Temporary files cleaned up in all exit paths
- No new shell metacharacter injection vectors

See [SECURITY.md](SECURITY.md) for the full security architecture.

## Commit Guidelines

### Format

```
type(scope): short description

Longer description if needed. Explain the what and why,
not the how (the code shows the how).

Fixes #123
```

### Types

| Type | Usage |
|------|-------|
| `feat` | New feature |
| `fix` | Bug fix |
| `sec` | Security fix or hardening |
| `docs` | Documentation only |
| `test` | Test additions or changes |
| `refactor` | Code change with no functional difference |
| `ci` | CI/CD pipeline changes |
| `chore` | Maintenance, cleanup, dependency updates |

### Scope Examples

`validation`, `iptables`, `nftables`, `rule-engine`, `menu`, `help`, `backup`, `detection`, `cli`

## Pull Request Process

1. **Branch** from `develop` (not `main`)
2. **Name** branches descriptively: `fix/ipset-set-name`, `feat/rule-expiry-watcher`
3. **Fill out** the PR template completely
4. **Ensure** all CI checks pass before requesting review
5. **Respond** to review feedback promptly
6. **Squash** commits if requested

### Size Guidelines

- One logical change per PR
- Large features should be broken into reviewable increments
- PRs over 500 lines should be split if possible

## Issue Guidelines

### Before Opening

1. Search existing issues for duplicates
2. Check the [Troubleshooting Guide](docs/wiki/Troubleshooting-Guide.md) and [FAQ](docs/wiki/Frequently-Asked-Questions.md)
3. Reproduce with `--log-level trace` for diagnostics

### Bug Reports

Include: version, OS, bash version, full error output, reproduction steps, and log entries.

### Feature Requests

Include: problem statement, proposed solution with examples, alignment with security-first design.

## Documentation

Documentation changes are as valuable as code changes:

- **Code comments**: Every function needs a header block
- **Help text**: Update `--help` and per-command help in `help_system.sh`
- **Changelog**: Add entries to `docs/changelog.md` and `docs/wiki/Changelog.md`
- **Wiki**: Update relevant pages in `docs/wiki/`
- **Sync map**: Update `tasks/sync_function.md` when dependencies change

## Recognition

Contributors are recognized in release notes, changelog entries, and the contributor list. Security vulnerability reporters are credited in advisories unless anonymity is requested. Significant contributions may result in invitation to the maintainer team.

---

Thank you for contributing to Apotropaios. Your efforts help keep systems secure.
