<a id="top"></a>

<p align="center">

```
    _                _                         _
   / \   _ __   ___ | |_ _ __ ___  _ __   __ _(_) ___  ___
  / _ \ | '_ \ / _ \| __| '__/ _ \| '_ \ / _` | |/ _ \/ __|
 / ___ \| |_) | (_) | |_| | | (_) | |_) | (_| | | (_) \__ \
/_/   \_\ .__/ \___/ \__|_|  \___/| .__/ \__,_|_|\___/|___/
        |_|                       |_|
```

  <h1 align="center">Apotropaios — Firewall Manager</h1>
  <p align="center">
    A unified, security-focused firewall management framework for Linux<br>supporting five backends with zero external dependencies.
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.1.5-blue?style=flat-square" alt="Version 1.1.5">
  <img src="https://img.shields.io/badge/shell-bash%204.0%2B-4EAA25?style=flat-square&logo=gnubash&logoColor=white" alt="Bash 4.0+">
  <img src="https://img.shields.io/badge/platform-linux-FCC624?style=flat-square&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa?style=flat-square" alt="Code of Conduct">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/ShellCheck-passing-7B68EE?style=flat-square&logo=gnubash&logoColor=white" alt="ShellCheck">
  <img src="https://github.com/apotropaios-project/apotropaios/actions/workflows/ci.yml/badge.svg" alt="CI Tests">
  <img src="https://img.shields.io/badge/BATS-375%20tests-blue?style=flat-square" alt="375 BATS Tests">
  <img src="https://img.shields.io/badge/security-48%20CWE%20checks-blueviolet?style=flat-square" alt="48 CWE Checks">
</p>

<p align="center">
  <img src="https://img.shields.io/github/last-commit/apotropaios-project/apotropaios?style=flat-square&color=FF6F3C&label=last%20commit" alt="Last Commit">
  <img src="https://img.shields.io/badge/maintained-yes-brightgreen?style=flat-square" alt="Maintained">
  <img src="https://img.shields.io/badge/PRs-welcome-azure?style=flat-square" alt="PRs Welcome">
  <img src="https://img.shields.io/badge/dependencies-zero-brightgreen?style=flat-square" alt="Zero Dependencies">
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> ·
  <a href="#cli-command-reference">Commands</a> ·
  <a href="docs/USAGE_GUIDE.md">Usage Guide</a> ·
  <a href="docs/changelog.md">Changelog</a> ·
  <a href="SECURITY.md">Security</a> ·
  <a href="#testing">Testing</a> ·
  <a href="#contributing">Contributing</a>
</p>

---

## Table of Contents

- [Overview](#overview)
- [Key Highlights](#key-highlights)
- [Features](#features)
  - [Core Capabilities](#core-capabilities)
  - [Input Validation and Security](#input-validation-and-security)
  - [Logging and Audit](#logging-and-audit)
- [Architecture](#architecture)
  - [Layer Model](#layer-model)
  - [Rule Lifecycle](#rule-lifecycle)
  - [Compound Action Translation](#compound-action-translation)
- [Supported Platforms](#supported-platforms)
- [Supported Firewalls](#supported-firewalls)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [CLI Examples](#cli-examples)
- [CLI Command Reference](#cli-command-reference)
  - [detect](#detect)
  - [add-rule](#add-rule)
  - [remove-rule](#remove-rule)
  - [list-rules](#list-rules)
  - [activate-rule / deactivate-rule](#activate-rule--deactivate-rule)
  - [import / export](#import--export)
  - [backup / restore](#backup--restore)
  - [block-all / allow-all](#block-all--allow-all)
  - [install / update](#install--update)
  - [status / system-rules](#status--system-rules)
  - [menu](#menu)
- [Global Options](#global-options)
- [Rule Lifecycle](#rule-lifecycle-1)
- [Compound Actions](#compound-actions)
- [Connection Tracking](#connection-tracking)
- [Rate Limiting](#rate-limiting)
- [Backup and Recovery](#backup-and-recovery)
- [Logging](#logging)
- [Directory Structure](#directory-structure)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)
- [Testing](#testing)
- [Contributing](#contributing)
- [Documentation](#documentation)
- [Version History](#version-history)
- [Acknowledgments](#acknowledgments)
- [License](#license)
- [Support](#support)

---

## Overview

Apotropaios (from Greek *apotropaios* — "turning away evil") is a zero-dependency bash framework for unified firewall management across multiple backends and Linux distributions. It wraps the complexity of five different firewall tools — **iptables**, **nftables**, **firewalld**, **ufw**, and **ipset** — into a single, consistent interface with UUID-tracked rule lifecycle management, comprehensive backup/recovery, and defense-in-depth security controls at every layer.

Every firewall rule created through Apotropaios receives a unique **UUID**, is tracked in a persistent rule index, and supports full lifecycle operations: create, activate, deactivate, remove, and automatic TTL-based expiry. The framework handles the translation between its unified rule model and each backend's native syntax — compound actions like `log,drop` become separate LOG + terminal rules in iptables, single expressions in nftables, rich rule log clauses in firewalld, and extracted terminal actions in ufw.

The framework emphasizes security at every layer: 28 whitelist input validators, shell injection prevention via portable glob patterns, secure file permissions (600/700), atomic locking via `flock(1)`, cryptographic integrity verification, and automatic masking of sensitive data in logs across four format families.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Key Highlights

| | Feature | Description |
|---|---------|-------------|
| 🔥 | **Five Firewall Backends** | iptables, nftables, firewalld, ufw, ipset — auto-detected and selectable |
| 🆔 | **UUID Rule Tracking** | Every rule gets a UUID for lifecycle management: create, activate, deactivate, remove, expire |
| 🔀 | **Compound Actions** | `log,drop` and `log,accept` translated natively per backend — no wrapper scripts |
| 📊 | **Connection Tracking** | `new`, `established`, `related`, `invalid`, `untracked` states on any rule |
| ⏱️ | **Rate Limiting** | `5/minute`, `10/second`, `100/hour` with configurable burst — per-rule granularity |
| 🖥️ | **Interactive Menu** | 7-category guided interface with validation, cancel support, and per-backend config menus |
| 💾 | **Backup & Recovery** | Timestamped compressed archives, immutable `chattr +i` snapshots, SHA-256 verification |
| 📦 | **Import / Export** | Portable rule configurations with integrity verification and dry-run preview |
| 🛡️ | **Security-First Design** | 28 whitelist validators, CWE-mapped test suite, OWASP/NIST-aligned controls |
| 📝 | **Structured Logging** | NIST SP 800-92 format, correlation IDs, 4-family sensitive data masking |
| ❓ | **Progressive Help** | Three-tier: global `--help`, per-command `COMMAND --help` (17 commands), interactive menu help |
| ⚡ | **Zero Dependencies** | Pure bash 4.0+ with only core system utilities — no Python, Ruby, or Node.js |

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Features

### Core Capabilities

- **Unified multi-backend management**: Consistent CLI and menu across iptables, nftables, firewalld, ufw, and ipset
- **Automatic backend detection**: Scans installed firewalls, auto-selects the best available, or lets you choose with `--backend`
- **UUID rule lifecycle**: Create, activate, deactivate, remove, and automatic TTL-based expiry with full audit trail
- **Compound actions**: `log,drop`, `log,accept`, `log,reject` — translated to each backend's native representation
- **Connection state tracking**: `--conn-state new,established,related` on any rule, mapped to conntrack/ct state per backend
- **Rate limiting**: `--limit 5/minute --limit-burst 10` for traffic shaping, translated to `-m limit` (iptables), `limit rate` (nftables), or rich rule limit (firewalld)
- **Configuration portability**: Import/export rule sets with SHA-256 integrity verification and dry-run preview
- **Backup and recovery**: Automatic restore points before destructive operations, timestamped compressed archives, and immutable `chattr +i` snapshots
- **Backend-specific configuration**: Per-backend management menus for zones, services, chain policies, set management, application profiles, logging levels, and default policies
- **17 CLI commands**: Each with `--help` providing synopsis, options, examples, and related commands
- **Interactive menu**: 7-category guided interface with input validation and cancel support
- **System-native rules**: View raw backend rules via `system-rules` (iptables -L, nft list, firewall-cmd --list-all, etc.)

### Input Validation and Security

- 28 whitelist validators for all user-supplied data types (ports, IPs, CIDRs, protocols, hostnames, paths, chains, tables, table families, zones, interfaces, rule IDs, actions, connection states, rate limits, log levels, log prefixes)
- Whitelist-based input sanitization — `sanitize_input()` keeps only known-safe characters via `tr -cd`
- Shell metacharacter rejection via portable glob-based detection (`_contains_shell_meta()`)
- Path traversal detection and rejection on all file path parameters
- Maximum input length enforcement (4096 characters)
- nftables table family validation (inet, ip, ip6, arp, bridge, netdev)
- Parameter re-validation from rule index before removal operations
- No `eval` of user-supplied data; zero `eval` in the logging subsystem
- No file-based command execution (nft -f removed as injection vector)

See [SECURITY.md](SECURITY.md) for the full threat model, implemented controls, CWE coverage, and secure deployment guidelines.

### Logging and Audit

- Structured log format compliant with OWASP Logging Cheat Sheet and NIST SP 800-92
- Per-execution correlation IDs for tracing operations across log entries
- Six log levels: TRACE, DEBUG, INFO, WARNING, ERROR, CRITICAL
- Dual output: color-coded console (stderr) and structured file (FD 3)
- Automatic log rotation at 100MB with configurable retention (default: 10 files)
- Sensitive data masking across four format families: key=value, key="quoted", JSON (`"key": "value"`), and HTTP Authorization headers
- Control character stripping prevents CWE-117 log injection
- Log files written with 600 permissions, log directories with 700

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Architecture

### Layer Model

```
┌──────────────────────────────────────────────────────────────────┐
│                    Layer 5: User Interface                        │
│    apotropaios.sh (CLI)  ·  menu_main.sh  ·  help_system.sh     │
├──────────────────────────────────────────────────────────────────┤
│                    Layer 4: Rule Engine                           │
│    rule_engine.sh  ·  rule_index.sh  ·  rule_state.sh            │
│    rule_import.sh  ·  backup.sh  ·  restore.sh  ·  immutable.sh │
├──────────────────────────────────────────────────────────────────┤
│                    Layer 3: Firewall Backends                     │
│    common.sh (dispatch)                                          │
│    iptables.sh · nftables.sh · firewalld.sh · ufw.sh · ipset.sh │
├──────────────────────────────────────────────────────────────────┤
│                    Layer 2: Detection                             │
│    os_detect.sh  ·  fw_detect.sh                                 │
├──────────────────────────────────────────────────────────────────┤
│                    Layer 1: Core Infrastructure                   │
│    constants.sh · validation.sh · logging.sh · errors.sh         │
│    security.sh  · utils.sh                                       │
└──────────────────────────────────────────────────────────────────┘
```

**Key design decisions:**

1. **Whitelist-first validation**: Every user input passes through whitelist pattern matching before reaching any system command. The validation layer uses regex for format checks and glob patterns for metacharacter detection — both are portable across all bash 4.0+ versions.

2. **Array-based command construction**: All firewall commands are built using bash arrays (`cmd_args+=("-p" "${protocol}")`), never string interpolation. This prevents shell injection regardless of input content.

3. **Backend-native translation**: The rule engine validates the superset of options, then each backend adapter translates to its native syntax. Compound actions, connection tracking, and rate limiting are expressed differently across backends but validated identically.

4. **Atomic locking**: `flock(1)` is used when available for race-condition-free file locking. When flock is unavailable, the framework falls back to `noclobber` file creation with PID validation and stale lock detection.

5. **Defense-in-depth logging**: Sensitive data is masked before writing to logs. FD operations use literal `exec 3>>` (no `eval`). Control characters are stripped. Log files have restricted permissions.

### Rule Lifecycle

```
                    ┌──────────┐
                    │  CREATE   │
                    │ (UUID)    │
                    └────┬─────┘
                         │
                    ┌────▼─────┐
              ┌─────│  ACTIVE   │─────┐
              │     └────┬─────┘     │
              │          │           │
         ┌────▼───┐  ┌──▼────┐  ┌──▼──────┐
         │DEACTIVE│  │EXPIRED│  │ REMOVED  │
         │(index) │  │ (TTL) │  │(backend  │
         └────┬───┘  └───────┘  │ + index) │
              │                  └──────────┘
         ┌────▼─────┐
         │REACTIVATE│
         └────┬─────┘
              │
         ┌────▼─────┐
         │  ACTIVE   │
         └──────────┘
```

Every rule passes through: **validation** (28 validators) → **engine** (UUID assignment, index registration) → **backend adapter** (native command construction) → **kernel** (firewall rule applied). Deactivation removes from the kernel but preserves the index entry for reactivation. Removal deletes from both.

### Compound Action Translation

A compound action like `log,drop` is expressed differently by each backend:

| Backend | Native Translation |
|:--------|:-------------------|
| **iptables** | Two separate rules: `-j LOG --log-prefix "..." --log-level info` followed by `-j DROP` |
| **nftables** | Single expression: `log prefix "..." level info drop` |
| **firewalld** | Rich rule with log clause: `rule ... log prefix "..." level info drop` |
| **ufw** | Terminal action extracted for ufw verb; logging enabled via `ufw logging` |

Removal mirrors the add logic exactly — for iptables, both the LOG rule and the terminal rule are deleted to prevent orphaned kernel rules.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Supported Platforms

Tested in CI on every commit across 7 platforms:

| Distribution | Version | Family | Package Manager | CI Status |
|:-------------|:--------|:-------|:----------------|:----------|
| **Ubuntu** | 22.04 LTS | Debian | apt | ✅ Verified |
| **Ubuntu** | 24.04 LTS | Debian | apt | ✅ Verified |
| **Kali Linux** | Rolling | Debian | apt | ✅ Verified |
| **Debian** | 12 (Bookworm) | Debian | apt | ✅ Verified |
| **Rocky Linux** | 9 | RHEL | dnf | ✅ Verified |
| **AlmaLinux** | 9 | RHEL | dnf | ✅ Verified |
| **Arch Linux** | Rolling | Arch | pacman | ✅ Verified |

**Also expected to work** on any Linux distribution with bash 4.0+ and standard coreutils, including Fedora, openSUSE, Amazon Linux 2023, and Raspberry Pi OS. RHEL 8/9 are supported via the binary-compatible Rocky Linux and AlmaLinux test coverage.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Supported Firewalls

| Backend | Binary | Description | Status |
|:--------|:-------|:------------|:-------|
| **iptables** | `iptables` | Legacy netfilter packet filtering with compound action support | ✅ Full Support |
| **nftables** | `nft` | Modern netfilter framework with native compound expressions | ✅ Full Support |
| **firewalld** | `firewall-cmd` | Dynamic firewall with zones and rich rules | ✅ Full Support |
| **ufw** | `ufw` | Uncomplicated Firewall with application profiles | ✅ Full Support |
| **ipset** | `ipset` | IP set management with iptables integration | ✅ Full Support |

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Prerequisites

### Required

| Dependency | Purpose | Install |
|------------|---------|---------|
| **bash** 4.0+ | Script execution (associative arrays, namerefs) | Pre-installed on all supported distributions |
| **coreutils** | `date`, `chmod`, `mkdir`, `mktemp`, `sha256sum`, `tr`, `sed` | Pre-installed on all supported distributions |
| **At least one firewall** | Backend for rule management | See [install command](#install--update) |

### Optional

| Dependency | Purpose | Install |
|------------|---------|---------|
| **util-linux** (`flock`) | Atomic file locking (preferred over noclobber fallback) | Pre-installed on most distributions |
| **procps** (`ps`) | Process status for lock PID validation | Pre-installed on most distributions |
| **chattr** (e2fsprogs) | Immutable backup snapshots | `sudo apt install e2fsprogs` |

### System Requirements

- Root/sudo access for firewall operations (kernel-level packet filtering)
- Bash 4.0+ for associative arrays and nameref variables
- No external dependencies — no Python, Ruby, Node.js, or third-party packages

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Quick Start

```bash
# 1. Clone or download
git clone https://github.com/apotropaios-project/apotropaios.git
cd apotropaios
chmod +x apotropaios.sh

# 2. Detect your system
sudo ./apotropaios.sh detect

# 3. Launch the interactive menu
sudo ./apotropaios.sh

# Or use the CLI directly:
sudo ./apotropaios.sh add-rule --dst-port 443 --action accept --protocol tcp
sudo ./apotropaios.sh list-rules
sudo ./apotropaios.sh backup pre-deploy
```

**Interactive menu**: Running with no arguments (or `menu`) launches a guided, 7-category menu-driven interface with validated input, cancel support, and per-backend configuration submenus.

**Direct CLI**: All 17 commands work directly — `add-rule`, `remove-rule`, `list-rules`, `backup`, `restore`, `import`, `export`, etc. Every command supports `--help` for detailed usage. Full CLI reference in the [Usage Guide](docs/USAGE_GUIDE.md).

**Alternative install methods**: See [SETUP_GUIDE.md](docs/SETUP_GUIDE.md) for system-wide installation via `make install`, configuration file setup, and first-run instructions.

### CLI Examples

Quick copy-paste examples for common operations. See the [Usage Guide](docs/USAGE_GUIDE.md) for complete options and operational scenarios.

**Add rules** — Create firewall rules with various options:
```bash
sudo ./apotropaios.sh add-rule --dst-port 443 --action accept --protocol tcp
sudo ./apotropaios.sh add-rule --src-ip 10.0.0.0/8 --action drop --direction inbound
sudo ./apotropaios.sh add-rule --dst-port 22 --action log,drop --conn-state new --limit 3/minute
sudo ./apotropaios.sh add-rule --dst-port 80 --action accept --duration temporary --ttl 3600
```

**Manage rules** — Lifecycle operations on existing rules:
```bash
sudo ./apotropaios.sh list-rules                    # Show all tracked rules
sudo ./apotropaios.sh remove-rule <UUID>            # Remove a specific rule
sudo ./apotropaios.sh deactivate-rule <UUID>        # Deactivate (keep in index)
sudo ./apotropaios.sh activate-rule <UUID>          # Reactivate a deactivated rule
```

**Import / Export** — Portable rule configurations:
```bash
sudo ./apotropaios.sh export /tmp/my-rules.conf     # Export current rules
sudo ./apotropaios.sh import /tmp/my-rules.conf     # Import rules from file
```

**Backup / Restore** — Protect your configuration:
```bash
sudo ./apotropaios.sh backup pre-deploy             # Create a named backup
sudo ./apotropaios.sh restore                       # Restore from latest backup
```

**Quick actions** — Emergency operations:
```bash
sudo ./apotropaios.sh block-all                     # Block all traffic (loopback preserved)
sudo ./apotropaios.sh allow-all                     # Allow all traffic
```

**System information** — Diagnostics:
```bash
sudo ./apotropaios.sh detect                        # Scan OS and firewalls
sudo ./apotropaios.sh status                        # Show backend status
sudo ./apotropaios.sh system-rules                  # Show raw backend rules
```

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## CLI Command Reference

### detect

Scan the system for installed operating system, firewall backends, and their current status.

```bash
sudo ./apotropaios.sh detect
```

Outputs: detected OS, available package manager, installed firewalls (with binary paths and service status), and auto-selected backend.

### add-rule

Create and apply a new firewall rule. The rule is validated, assigned a UUID, applied to the active backend, and registered in the rule index.

```bash
sudo ./apotropaios.sh add-rule [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--protocol <PROTO>` | Protocol: tcp, udp, icmp, icmpv6, sctp, all (default: tcp) |
| `--src-ip <IP/CIDR>` | Source IP address or CIDR |
| `--dst-ip <IP/CIDR>` | Destination IP address or CIDR |
| `--src-port <PORT>` | Source port or port range |
| `--dst-port <PORT>` | Destination port or port range |
| `--action <ACTION>` | Rule action: accept, drop, reject, log, masquerade, snat, dnat, return, or compound (log,drop) |
| `--direction <DIR>` | Traffic direction: inbound, outbound, forward |
| `--conn-state <STATES>` | Connection tracking: new, established, related, invalid, untracked (comma-separated) |
| `--limit <RATE>` | Rate limit: N/second, N/minute, N/hour, N/day |
| `--limit-burst <N>` | Burst allowance for rate limiting |
| `--log-prefix <PREFIX>` | Log prefix string (max 29 chars) |
| `--log-level <LEVEL>` | Syslog level: emerg, alert, crit, err, warning, notice, info, debug |
| `--zone <ZONE>` | Firewalld zone name |
| `--interface <IFACE>` | Network interface |
| `--chain <CHAIN>` | Custom chain name (iptables/nftables) |
| `--table <TABLE>` | Custom table name (iptables/nftables) |
| `--duration <TYPE>` | Duration: permanent or temporary |
| `--ttl <SECONDS>` | Time-to-live for temporary rules (60–2592000 seconds) |
| `--description <TEXT>` | Human-readable rule description |

### remove-rule

Remove a rule by its UUID. Deletes from both the firewall backend and the rule index.

```bash
sudo ./apotropaios.sh remove-rule <UUID>
```

### list-rules

Display all rules tracked in the rule index with their UUIDs, parameters, and current state.

```bash
sudo ./apotropaios.sh list-rules
```

### activate-rule / deactivate-rule

Toggle a rule's active state. Deactivation removes the rule from the firewall backend but preserves it in the index for later reactivation.

```bash
sudo ./apotropaios.sh deactivate-rule <UUID>
sudo ./apotropaios.sh activate-rule <UUID>
```

### import / export

Transfer rule configurations between systems or environments. Export produces a portable configuration file with SHA-256 integrity checksum. Import validates the checksum before applying.

```bash
sudo ./apotropaios.sh export /path/to/rules.conf
sudo ./apotropaios.sh import /path/to/rules.conf
```

Import supports `--dry-run` to preview rules without applying them.

### backup / restore

Create and restore timestamped backup archives of the complete framework state (rule index, state tracking, configuration).

```bash
sudo ./apotropaios.sh backup [LABEL]         # Create backup with optional label
sudo ./apotropaios.sh restore [BACKUP_FILE]  # Restore from specific or latest backup
```

Backups are compressed tar.gz archives with SHA-256 checksums. Up to 20 backups are retained (configurable). Immutable snapshots can be created via the interactive menu.

### block-all / allow-all

Emergency actions that set default chain policies across the active backend.

```bash
sudo ./apotropaios.sh block-all     # DROP all traffic (loopback preserved)
sudo ./apotropaios.sh allow-all     # ACCEPT all traffic
```

**Warning**: `block-all` will block all network traffic including SSH. Ensure you have out-of-band access before using this on remote systems.

### install / update

Install or update firewall packages via the system package manager.

```bash
sudo ./apotropaios.sh install <FIREWALL>    # Install a firewall backend
sudo ./apotropaios.sh update <FIREWALL>     # Update a firewall backend
```

Supported targets: `firewalld`, `iptables`, `nftables`, `ufw`, `ipset`. The framework auto-detects your package manager (apt, dnf, pacman).

### status / system-rules

Display the active backend's current status or raw system rules.

```bash
sudo ./apotropaios.sh status          # Backend service status
sudo ./apotropaios.sh system-rules    # Raw rules (iptables -L, nft list, etc.)
```

### menu

Launch the interactive menu-driven interface. This is the default command when no arguments are provided.

```bash
sudo ./apotropaios.sh menu
sudo ./apotropaios.sh              # Same — menu is the default
```

The menu provides seven categories: Firewall Management, Rule Management, Quick Actions, Backup & Recovery, System Information, Install & Update, and Help & Documentation.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Global Options

These options are available on all commands:

| Option | Description |
|--------|-------------|
| `--backend <NAME>` | Select firewall backend: iptables, nftables, firewalld, ufw, ipset |
| `--log-level <LEVEL>` | Set log verbosity: trace, debug, info, warning, error, critical |
| `--non-interactive` | Suppress interactive prompts (for scripting) |
| `-v, --version` | Show version string and exit |
| `-h, --help` | Show context-sensitive help (global or per-command) |

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Rule Lifecycle

Every rule created through Apotropaios follows a managed lifecycle:

1. **Validation**: All 28 validators run against every parameter (ports, IPs, CIDRs, protocols, actions, states, limits, etc.)
2. **UUID Assignment**: A cryptographically random UUID v4 is generated from `/dev/urandom`
3. **Index Registration**: The rule is recorded in the persistent rule index with all parameters, timestamps, and backend association
4. **Backend Application**: The rule engine dispatches to the active backend adapter, which translates to native syntax and executes
5. **State Tracking**: The rule's state (active/inactive), duration type (permanent/temporary), and TTL are tracked independently

Temporary rules are automatically checked for expiry. Expired rules are removed from both the backend and the index. The `rule_check_expired` function runs on framework startup.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Compound Actions

Compound actions combine a non-terminal action (like `log`) with a terminal action (like `drop`) in a single logical rule:

```bash
sudo ./apotropaios.sh add-rule --dst-port 22 --action log,drop
sudo ./apotropaios.sh add-rule --dst-port 80 --action log,accept --log-prefix "HTTP: "
sudo ./apotropaios.sh add-rule --src-ip 10.0.0.0/8 --action log,reject --log-level warning
```

The framework validates that compound actions contain exactly one terminal action and one or more non-terminal actions. Removal operations mirror the add logic exactly to prevent orphaned rules in the kernel.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Connection Tracking

Connection state tracking filters packets based on their relationship to established connections:

```bash
sudo ./apotropaios.sh add-rule --dst-port 443 --action accept --conn-state new,established
sudo ./apotropaios.sh add-rule --action drop --conn-state invalid
```

| State | Description |
|-------|-------------|
| `new` | First packet of a new connection |
| `established` | Packet belonging to an already established connection |
| `related` | Packet related to an established connection (e.g., FTP data) |
| `invalid` | Packet that does not match any known connection |
| `untracked` | Packet not tracked by conntrack |

Multiple states can be comma-separated. The framework translates to: `-m conntrack --ctstate` (iptables), `ct state` (nftables), or rich rule state clause (firewalld).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Rate Limiting

Per-rule rate limiting controls the frequency of matched packets:

```bash
sudo ./apotropaios.sh add-rule --dst-port 22 --action log,drop --limit 3/minute --limit-burst 5
sudo ./apotropaios.sh add-rule --action accept --limit 10/second
```

| Parameter | Format | Examples |
|-----------|--------|----------|
| `--limit` | N/unit | `5/second`, `30/minute`, `100/hour`, `1000/day` |
| `--limit-burst` | N | `5`, `10`, `20` (packets allowed before rate limiting kicks in) |

Translated to: `-m limit --limit N/unit --limit-burst N` (iptables), `limit rate N/unit burst N packets` (nftables), or rich rule `limit value="N/unit"` (firewalld).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Backup and Recovery

The framework provides three levels of configuration protection:

1. **Automatic restore points**: Created before destructive operations (block-all, allow-all, import)
2. **Manual backups**: Timestamped compressed archives with optional labels
3. **Immutable snapshots**: `chattr +i` protected files that cannot be modified or deleted without explicit unlock

```bash
sudo ./apotropaios.sh backup pre-deploy     # Create labeled backup
sudo ./apotropaios.sh backup                # Create timestamped backup
sudo ./apotropaios.sh restore               # Restore from latest
sudo ./apotropaios.sh restore specific.tar.gz  # Restore from specific backup
```

Backups include: rule index, rule state tracking, framework configuration, and backup manifest with SHA-256 checksums. Up to 20 backups are retained with automatic rotation of older archives.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Logging

### Log Types

| Log | Path | Description |
|-----|------|-------------|
| Execution log | `data/logs/apotropaios-<timestamp>.log` | All operations for the current session |
| Console output | stderr | Color-coded severity levels (TRACE through CRITICAL) |

### Log Format

Execution logs use structured format compliant with OWASP Logging Cheat Sheet and NIST SP 800-92:

```
[2026-03-27T14:30:00.123Z] [INFO] [rule_engine] [cid:a1b2c3d4e5f6] Rule created and applied: 550e8400-... | backend=iptables direction=inbound action=log,drop
```

### Sensitive Data Masking

All log messages are automatically sanitized before writing. The following patterns are masked:

| Format | Example | Masked Output |
|--------|---------|---------------|
| Key=value | `password=secret123` | `password=***MASKED***` |
| Quoted value | `token="my secret"` | `token="***MASKED***"` |
| JSON | `"apikey": "abc123"` | `"apikey": "***MASKED***"` |
| HTTP header | `Authorization: Bearer eyJ...` | `Authorization: Bearer ***MASKED***` |

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Directory Structure

```
apotropaios/                          # Repository root
├── apotropaios.sh                    # Main entry point (chmod +x)
├── Makefile                          # 38 targets: build, test, install, security-scan
├── .shellcheckrc                     # ShellCheck configuration with source-path
├── .gitignore                        # Git ignore rules
├── conf/
│   └── apotropaios.conf              # Framework configuration
├── lib/
│   ├── core/                         # Layer 1: Infrastructure (6 modules)
│   │   ├── constants.sh              #   Immutable constants, patterns, exit codes
│   │   ├── validation.sh             #   28 whitelist validators
│   │   ├── logging.sh                #   Structured logging with FD 3
│   │   ├── errors.sh                 #   Signal traps, LIFO cleanup stack, retry
│   │   ├── security.sh               #   Locks, checksums, temp files, scrubbing
│   │   └── utils.sh                  #   Timestamps, formatting, parallel exec
│   ├── detection/                    # Layer 2: Detection (2 modules)
│   │   ├── os_detect.sh              #   OS family, version, package manager
│   │   └── fw_detect.sh              #   Installed firewalls, binary paths, status
│   ├── firewall/                     # Layer 3: Backend Adapters (6 modules)
│   │   ├── common.sh                 #   Unified dispatch to active backend
│   │   ├── iptables.sh               #   Compound actions, conntrack, rate limit
│   │   ├── nftables.sh               #   Native expressions, table family validation
│   │   ├── firewalld.sh              #   Rich rule builder (12 params)
│   │   ├── ufw.sh                    #   Extended syntax, app profiles, logging
│   │   └── ipset.sh                  #   Set creation, membership, iptables rules
│   ├── rules/                        # Layer 4: Rule Engine (4 modules)
│   │   ├── rule_engine.sh            #   Create, remove, activate, deactivate
│   │   ├── rule_index.sh             #   Persistent UUID-keyed rule storage
│   │   ├── rule_state.sh             #   State tracking, TTL, expiry
│   │   └── rule_import.sh            #   Import/export with integrity verify
│   ├── backup/                       # Layer 4: Backup (3 modules)
│   │   ├── backup.sh                 #   Create, rotate, manifest generation
│   │   ├── restore.sh                #   Restore from archive
│   │   └── immutable.sh              #   chattr +i snapshot management
│   ├── install/
│   │   └── installer.sh              #   Package installation across pkg managers
│   └── menu/                         # Layer 5: User Interface (2 modules)
│       ├── menu_main.sh              #   7-category interactive menu + rule wizard
│       └── help_system.sh            #   17 per-command help pages
├── tests/                            # BATS test suite (375 tests, 13 files)
│   ├── helpers/test_helper.bash      #   Shared setup/teardown
│   ├── fixtures/                     #   Test data (sample rules, invalid configs)
│   ├── unit/                         #   234 tests across 8 files
│   ├── integration/                  #   93 tests across 4 files
│   └── security/                     #   48 CWE-mapped tests
├── .github/
│   ├── workflows/ci.yml              #   6-stage CI: lint, security, tests, 5-distro matrix
│   ├── workflows/release.yml         #   Release with security gate
│   ├── ISSUE_TEMPLATE/               #   4 templates: bug, feature, security, docs
│   ├── PULL_REQUEST_TEMPLATE.md      #   10-section PR checklist
│   └── FUNDING.yml                   #   12-platform funding configuration
├── docs/
│   ├── SETUP_GUIDE.md                #   Installation and first-run instructions
│   ├── USAGE_GUIDE.md                #   Complete CLI and menu reference
│   ├── DEVELOPER_GUIDE.md            #   Code component catalog
│   ├── DEVELOPMENT_GUIDE.md          #   Contributing and coding standards
│   ├── changelog.md                  #   Detailed version history
│   └── wiki/                         #   15-page comprehensive wiki
├── SECURITY.md                       #   Security policy and CWE coverage
├── CONTRIBUTING.md                   #   Contribution guidelines
├── CODE_OF_CONDUCT.md                #   Contributor Covenant v2.1
└── LICENSE                           #   MIT License with 12 supplementary sections
```

Runtime directories (`data/logs/`, `data/rules/`, `data/backups/`, `data/.tmp/`) are created automatically on first run and excluded from version control by `.gitignore`.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Security Considerations

### Input Validation

- All ports validated as integers in range 1-65535 with leading zero rejection
- All IPs validated against IPv4 octet ranges (0-255) and IPv6 compressed notation
- CIDR prefixes validated per address family (0-32 for IPv4, 0-128 for IPv6)
- Shell metacharacters (`;|&\`$(){}\\<>!#`) blocked via portable glob patterns
- Path traversal (`..`) and null bytes blocked in all file path parameters
- Rule IDs validated as UUID v4 format (8-4-4-4-12 hex characters)
- Connection states validated against conntrack whitelist
- Rate limit formats validated as N/unit with valid units (second, minute, hour, day)
- nftables table families validated against kernel whitelist (inet, ip, ip6, arp, bridge, netdev)
- All sanitized inputs pass through whitelist `tr -cd` keeping only known-safe characters

### Command Construction

- All firewall commands built using bash arrays — never string interpolation
- No `eval` of user-supplied data; zero `eval` in the logging subsystem
- No file-based command execution (nft -f removed as injection vector in v1.1.5)
- Parameters re-validated from rule index before removal operations

### File and Process Security

- umask 077 enforced at initialization
- Data files: 600 permissions (owner read/write only)
- Data directories: 700 permissions (owner only)
- Temporary files created via `mktemp` with secure defaults
- Atomic file locking via `flock(1)` when available
- Sensitive variables scrubbed from memory on exit
- Cleanup handlers fire on EXIT, SIGTERM, SIGINT, SIGHUP

### What This Tool Does NOT Do

- Does not replace professional security review of firewall policies
- Does not guarantee prevention of all network attacks or breaches
- Does not provide intrusion detection or intrusion prevention
- Does not monitor or alert on traffic anomalies
- Does not manage firewall rules created outside the framework
- Self-generated UUIDs may not meet all regulatory compliance requirements

For the full security policy, threat model, CWE coverage table, implemented controls, and secure deployment guidelines, see [SECURITY.md](SECURITY.md).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Troubleshooting

### Framework fails to start with "command not found"

Ensure bash 4.0+ is available and the script is executable:

```bash
bash --version                          # Check bash version (need 4.0+)
chmod +x apotropaios.sh                 # Make executable
sudo ./apotropaios.sh detect            # Test with detect command
```

### "Invalid option" in the interactive menu

Ensure you are running version 1.1.5 or later. Earlier versions had a sanitization bug (BUG-010) that caused all menu input to be rejected:

```bash
sudo ./apotropaios.sh --version         # Should show v1.1.5+
```

### "Root privileges required"

Firewall operations require root access. Run with `sudo`:

```bash
sudo ./apotropaios.sh status
```

### Rule creation fails with "Invalid action"

Compound actions must use comma separation with no spaces, and must contain exactly one terminal action:

```bash
# Correct
sudo ./apotropaios.sh add-rule --action log,drop --dst-port 22
# Wrong — space after comma
sudo ./apotropaios.sh add-rule --action "log, drop" --dst-port 22
# Wrong — two terminal actions
sudo ./apotropaios.sh add-rule --action drop,reject --dst-port 22
```

### No firewall backends detected

Install at least one supported firewall:

```bash
sudo ./apotropaios.sh install iptables    # Debian/Ubuntu
sudo ./apotropaios.sh install nftables    # Modern alternative
sudo ./apotropaios.sh install ufw         # Simplest option
```

### Log file not created

Check directory permissions and disk space:

```bash
ls -la data/logs/                       # Check permissions
df -h                                    # Check disk space
sudo ./apotropaios.sh --log-level trace detect  # Maximum diagnostic detail
```

For additional troubleshooting scenarios, see the [Wiki Troubleshooting Guide](docs/wiki/Troubleshooting-Guide.md) and the [Usage Guide](docs/USAGE_GUIDE.md).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Testing

The project includes a comprehensive test suite built on [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System) with 375 tests covering validation, security, lifecycle, CLI, help system, and backup operations.

```bash
# Run the full test suite (lint + all tests)
make test

# Run unit tests only (fast feedback)
make test-quick

# Run security tests only (CWE-mapped)
make test-sec

# Run static security pattern analysis
make security-scan

# Run a specific test file
bats tests/unit/validation.bats

# Run a specific test by name
bats tests/unit/validation.bats --filter "table_family"
```

| Test File | Tests | Coverage |
|-----------|------:|----------|
| `tests/unit/validation.bats` | 88 | All 28 `validate_*` functions, `sanitize_input`, `_contains_shell_meta` |
| `tests/unit/logging.bats` | 28 | `log_init`, `log_shutdown`, `log_set_level`, all severity functions, correlation IDs |
| `tests/unit/os_detect.bats` | 20 | OS detection across 6 distributions, fallback behavior |
| `tests/unit/fw_detect.bats` | 18 | Firewall detection for all 5 backends, binary validation |
| `tests/unit/security.bats` | 23 | UUID generation, checksums, temp files, lock acquisition/release |
| `tests/unit/errors.bats` | 24 | Cleanup stack (LIFO), retry with backoff, signal handling, assertions |
| `tests/unit/rule_engine.bats` | 19 | Rule create, remove, activate, deactivate, expired rule handling |
| `tests/unit/backup.bats` | 14 | Backup create, restore, rotation, manifest verification |
| `tests/integration/lifecycle.bats` | 22 | End-to-end rule lifecycle, CLI flag parsing, version output |
| `tests/integration/import_export.bats` | 10 | Round-trip import/export, integrity verification, malformed file handling |
| `tests/integration/cli.bats` | 29 | All 17 CLI commands, global options, error handling |
| `tests/integration/help_system.bats` | 32 | All 17 per-command help pages, help dispatch routing |
| `tests/security/injection.bats` | 48 | CWE-78 (12), CWE-22 (5), CWE-20 (14), CWE-117 (6), CWE-732 (4), CWE-377 (2), integrity (2), locking (2), info disclosure (1) |

Tests use mock stubs so they run without real firewall operations or root access. See [CONTRIBUTING.md](CONTRIBUTING.md) for details on writing and running tests.

**CI/CD**: Every push and PR runs the test suite automatically via [GitHub Actions](.github/workflows/ci.yml) across a 6-stage pipeline (syntax, lint, security scan, unit tests, integration tests, 5-distro container matrix) with a test summary report. Releases are gated on a full security scan via [release workflow](.github/workflows/release.yml).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Contributing

Contributions are welcome and appreciated. To contribute:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/your-feature-name`)
3. **Commit** your changes with clear, descriptive messages (`git commit -m 'Add: description of change'`)
4. **Push** to your branch (`git push origin feature/your-feature-name`)
5. **Open** a Pull Request with a detailed description of the change, its motivation, and testing performed

### Guidelines

- Run `make test` before submitting — all 375 tests must pass
- Run `make lint` — ShellCheck must report no warnings
- Run `make security-scan` — no new warnings introduced
- Follow the existing code style: comprehensive function documentation headers (Synopsis, Description, Parameters, Returns), inline comments explaining non-obvious logic, and consistent formatting
- All user-supplied inputs must pass through existing validation functions
- New CLI flags must be added to the argument parser, help function, and at least one BATS test
- Update `docs/changelog.md` with your changes under an `[Unreleased]` section
- Read and follow the [Code of Conduct](CODE_OF_CONDUCT.md)
- Report security vulnerabilities privately per [SECURITY.md](SECURITY.md) — do not open public issues for security bugs

For the complete development guide including environment setup, test architecture, known pitfalls, coding standards, and PR process, see [CONTRIBUTING.md](CONTRIBUTING.md) and [DEVELOPMENT_GUIDE.md](docs/DEVELOPMENT_GUIDE.md).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Project overview, features, architecture, and quick reference (this file) |
| [SETUP_GUIDE.md](docs/SETUP_GUIDE.md) | Installation, configuration, first-run, and troubleshooting |
| [USAGE_GUIDE.md](docs/USAGE_GUIDE.md) | Complete CLI and interactive menu reference with operational scenarios |
| [DEVELOPER_GUIDE.md](docs/DEVELOPER_GUIDE.md) | Code component catalog: all 25 modules, function tables, constants |
| [DEVELOPMENT_GUIDE.md](docs/DEVELOPMENT_GUIDE.md) | Contributing guide: coding standards, testing patterns, CI/CD, known pitfalls |
| [Changelog](docs/changelog.md) | Complete version history with detailed change descriptions per release |
| [Wiki](docs/wiki/) | 15-page comprehensive wiki with architecture diagrams and operational scenarios |
| [SECURITY.md](SECURITY.md) | Security policy, vulnerability reporting, CWE coverage, threat model |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution guidelines and development environment setup |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Contributor Covenant v2.1 with responsible use policy |
| [LICENSE](LICENSE) | MIT License with 12 supplementary sections (warranty, liability, firewall disclaimer) |

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| **1.1.5** | 2026-03-27 | Security audit: 10 findings resolved (compound removal, flock locking, whitelist sanitization, log masking expansion, nft -f removal, eval elimination). 375 tests. |
| **1.1.4** | 2026-03-25 | Critical startup fix (PATTERN_SHELL_META portability). Security test suite (48 CWE tests). CI/CD pipeline. Community files. |
| **1.1.3** | 2026-03-24 | Compound actions (`log,drop`). Connection tracking. Rate limiting. Enhanced UFW config. CLI flags for all new options. |
| **1.1.2** | 2026-03-24 | Crash fixes (menu options 4-8). Backend config submenus for ipset, iptables, nftables, firewalld, ufw. |
| **1.1.1** | 2026-03-23 | Progressive help system: 17 per-command help pages with synopsis, options, examples. |
| **1.1.0** | 2026-03-23 | Bug fixes. Rule wizard. 15-page wiki. |
| **1.0.0** | 2026-03-23 | Initial release. 25 modules. 5 backends. Interactive menu. CLI. Rule lifecycle. Backup/recovery. |

See [changelog.md](docs/changelog.md) for complete details on every change.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Acknowledgments

- **[netfilter.org](https://www.netfilter.org/)** — iptables, nftables, and ipset — the kernel-level packet filtering framework this tool manages
- **[firewalld](https://firewalld.org/)** — dynamic firewall management daemon with D-Bus interface
- **[ufw](https://launchpad.net/ufw)** — Ubuntu's Uncomplicated Firewall providing simplified iptables management
- **[BATS](https://github.com/bats-core/bats-core)** — Bash Automated Testing System used for the test suite
- **[ShellCheck](https://www.shellcheck.net/)** — static analysis tool for shell scripts
- **[Contributor Covenant](https://www.contributor-covenant.org/)** — code of conduct framework
- **[Keep a Changelog](https://keepachangelog.com/)** — changelog format standard
- **[Semantic Versioning](https://semver.org/)** — versioning scheme
- **[Shields.io](https://shields.io/)** — badge generation service
- **OWASP** and **NIST** — security standards referenced throughout (OWASP CRG, OWASP Logging Cheat Sheet, NIST SP 800-92, NIST SP 800-218, CWE/SANS Top 25)

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for full terms including 12 supplementary sections covering warranty disclaimer, liability limitation, firewall-specific disclaimer, assumption of risk, export compliance, and contribution licensing.

```
MIT License · Copyright (c) 2026 Apotropaios Project Contributors
```

This software is intended for authorized systems administration, network security management, and firewall configuration. Users are solely responsible for ensuring their use complies with all applicable laws and regulations. See the [Firewall and Network Security Disclaimer](LICENSE) in the LICENSE file.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Support

<p align="center">
  ⭐ If this project helps secure your network, please consider giving it a star! ⭐
</p>

<p align="center">
  <a href="https://github.com/apotropaios-project/apotropaios/issues/new?template=bug_report.yml">Report Bug</a>
  ·
  <a href="https://github.com/apotropaios-project/apotropaios/issues/new?template=feature_request.yml">Request Feature</a>
  ·
  <a href="https://github.com/apotropaios-project/apotropaios/issues/new?template=security_vulnerability.yml">Report Vulnerability</a>
</p>

<p align="center">
  <a href="https://github.com/sponsors/apotropaios-project">
    <img src="https://img.shields.io/badge/Sponsor-❤️-ea4aaa?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor">
  </a>
  <a href="https://ko-fi.com/apotropaios">
    <img src="https://img.shields.io/badge/Ko--fi-Buy%20Me%20a%20Coffee-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Ko-fi">
  </a>
</p>

**Getting Help:**

- **Documentation**: Start with the [Wiki](docs/wiki/) and [USAGE_GUIDE.md](docs/USAGE_GUIDE.md)
- **Built-in Help**: Run `sudo ./apotropaios.sh COMMAND --help` for any of the 17 commands
- **Bug Reports**: Use the [Bug Report template](https://github.com/apotropaios-project/apotropaios/issues/new?template=bug_report.yml)
- **Feature Requests**: Use the [Feature Request template](https://github.com/apotropaios-project/apotropaios/issues/new?template=feature_request.yml)
- **Security Issues**: See [SECURITY.md](SECURITY.md) — use private reporting for critical vulnerabilities
- **Discussions**: [GitHub Discussions](https://github.com/apotropaios-project/apotropaios/discussions) for questions and ideas

**Diagnostic Commands:**

```bash
sudo ./apotropaios.sh detect                        # System scan
sudo ./apotropaios.sh --log-level trace detect      # Maximum diagnostic detail
sudo ./apotropaios.sh --version                     # Check version
bash --version                                       # Check bash version
```

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

<p align="center">

**Apotropaios** — *Turning away evil since v1.0.0*

Made with focus on security, reliability, and simplicity.

</p>
