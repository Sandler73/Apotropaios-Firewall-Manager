# Apotropaios — Usage Guide

Complete reference for all CLI commands, interactive menu operations, rule creation, and advanced features.

## Table of Contents

1. [Running Apotropaios](#running-apotropaios)
2. [Interactive Menu Mode](#interactive-menu-mode)
3. [CLI Mode](#cli-mode)
4. [Per-Command Help](#per-command-help)
5. [Managing Firewall Backends](#managing-firewall-backends)
6. [Creating Firewall Rules](#creating-firewall-rules)
7. [Compound Actions](#compound-actions)
8. [Connection Tracking](#connection-tracking)
9. [Rate Limiting](#rate-limiting)
10. [Rule Lifecycle](#rule-lifecycle)
11. [Temporary Rules with TTL](#temporary-rules-with-ttl)
12. [Backend Configuration](#backend-configuration)
13. [Importing and Exporting Rules](#importing-and-exporting-rules)
14. [Backup and Recovery](#backup-and-recovery)
15. [Quick Actions](#quick-actions)
16. [Logging and Troubleshooting](#logging-and-troubleshooting)
17. [Configuration File Reference](#configuration-file-reference)

---

## Running Apotropaios

Apotropaios requires root privileges for firewall operations.

**Interactive mode (default):**
```bash
sudo ./apotropaios.sh
```

**CLI mode with specific command:**
```bash
sudo ./apotropaios.sh [OPTIONS] COMMAND [ARGS]
```

**Global options (must precede the command):**

| Option | Description |
|:-------|:------------|
| `--help`, `-h` | Show global help (or per-command help if after a command) |
| `--version`, `-v` | Show version and exit |
| `--backend BACKEND` | Override auto-detected backend (iptables, nftables, firewalld, ufw, ipset) |
| `--log-level LEVEL` | Set log verbosity: trace, debug, info, warning, error, critical |
| `--quiet`, `-q` | Suppress non-error output |

**Examples:**
```bash
sudo ./apotropaios.sh --log-level trace detect      # Maximum verbosity
sudo ./apotropaios.sh --log-level error status       # Errors only
sudo ./apotropaios.sh --backend nftables add-rule --dst-port 80 --action accept
```

---

## Interactive Menu Mode

Launch with `sudo ./apotropaios.sh` or `sudo ./apotropaios.sh menu`.

The main menu presents numbered options. Enter the number and press Enter.

**Main Menu Options:**

1. **Firewall Management** — Select and configure firewall backends. Start, stop, reload, reset firewalls. View current rules and status. Backend-specific configuration submenus.
2. **Rule Management** — Create rules through a 5-step guided wizard. List, remove, activate, deactivate tracked rules. Import/export rule configurations. Rule expiry watcher.
3. **Quick Actions** — One-click block-all or allow-all traffic with automatic restore point creation.
4. **Backup & Recovery** — Create timestamped backups, list available backups, restore from backup, manage immutable snapshots.
5. **System Information** — View detected OS, installed firewalls, framework status, active log file.
6. **Install & Update** — Install missing firewalls or update existing ones via the system package manager.
7. **Help & Documentation** — In-app help reference.
8. **Exit** — Clean shutdown with resource cleanup.

### Rule Creation Wizard

The interactive wizard guides you through 5 steps:

**Step 1: Backend Selection** — Choose which firewall backend to use for this rule.

**Step 2: Rule Parameters** — Direction, protocol, source/destination IP and port, action (including compound actions like `log,drop`), interface, connection state, log options (if action includes log), and rate limiting.

**Step 3: Backend-Specific Options** — Zone (firewalld), table/chain (iptables/nftables), set name (ipset), or additional ufw options.

**Step 4: Duration** — Permanent or temporary with TTL in seconds.

**Step 5: Summary and Confirmation** — Review all parameters before applying.

---

## CLI Mode

Every operation available in the menu is also accessible via CLI commands.

### Detection and Status

```bash
sudo ./apotropaios.sh detect              # OS and firewall detection
sudo ./apotropaios.sh status              # Active backend status
sudo ./apotropaios.sh system-rules        # List all native firewall rules
```

### Rule Operations

```bash
sudo ./apotropaios.sh list-rules                          # List Apotropaios-tracked rules
sudo ./apotropaios.sh add-rule [OPTIONS]                   # Create a new rule
sudo ./apotropaios.sh remove-rule <UUID>                   # Remove by UUID
sudo ./apotropaios.sh activate-rule <UUID>                 # Re-apply a deactivated rule
sudo ./apotropaios.sh deactivate-rule <UUID>               # Remove from firewall, keep in index
```

### Import/Export

```bash
sudo ./apotropaios.sh import /path/to/rules.conf          # Import rules from file
sudo ./apotropaios.sh export /path/to/output.conf          # Export tracked rules
```

### Backup and Recovery

```bash
sudo ./apotropaios.sh backup <label>                       # Create labeled backup
sudo ./apotropaios.sh restore /path/to/backup.tar.gz       # Restore from archive
```

### Quick Actions

```bash
sudo ./apotropaios.sh block-all                            # Drop all traffic
sudo ./apotropaios.sh allow-all                            # Remove all restrictions
```

### Firewall Management

```bash
sudo ./apotropaios.sh start                                # Start active backend
sudo ./apotropaios.sh stop                                 # Stop active backend
sudo ./apotropaios.sh reload                               # Reload configuration
sudo ./apotropaios.sh reset                                # Reset to defaults
```

---

## Per-Command Help

Every command has detailed help with synopsis, options, examples, tips, and related commands:

```bash
sudo ./apotropaios.sh --help                # Global help
sudo ./apotropaios.sh add-rule --help       # Full add-rule option reference
sudo ./apotropaios.sh backup --help         # Backup contents and retention
sudo ./apotropaios.sh import --help         # Config file format reference
sudo ./apotropaios.sh detect --help         # Detection methods
```

Per-command help bypasses framework initialization for instant response — no root required, no firewall detection delay.

All 17 commands have dedicated help pages: `detect`, `status`, `add-rule`, `remove-rule`, `activate-rule`, `deactivate-rule`, `list-rules`, `system-rules`, `import`, `export`, `backup`, `restore`, `block-all`, `allow-all`, `start`, `stop`, `reload`, `reset`, `install`.

---

## Managing Firewall Backends

Apotropaios auto-detects installed firewalls and selects the first available as the active backend. Override with `--backend`:

```bash
sudo ./apotropaios.sh --backend nftables add-rule --dst-port 80 --action accept
sudo ./apotropaios.sh --backend ufw status
```

In interactive mode, use **Firewall Management > Select active firewall backend** to switch.

Rules are tagged with the backend used to create them. When removing or deactivating rules, Apotropaios automatically routes to the correct backend regardless of the currently active one.

### Backend Priority

When multiple backends are installed, auto-detection selects in this order: firewalld > nftables > iptables > ufw > ipset.

---

## Creating Firewall Rules

### add-rule Options

| Option | Description | Default |
|:-------|:------------|:--------|
| `--direction DIR` | Traffic direction: inbound, outbound, forward | inbound |
| `--protocol PROTO` | Protocol: tcp, udp, icmp, icmpv6, sctp, all | tcp |
| `--src-ip IP` | Source IP address or CIDR notation | any |
| `--dst-ip IP` | Destination IP address or CIDR notation | any |
| `--src-port PORT` | Source port or range (e.g., 1024-65535) | any |
| `--dst-port PORT` | Destination port or range (e.g., 443, 8080-8090) | any |
| `--action ACTION` | Single or compound: accept, drop, reject, log, log,drop | accept |
| `--interface IFACE` | Network interface (e.g., eth0, ens33) | any |
| `--conn-state STATES` | Connection tracking: new,established,related,invalid | — |
| `--log-prefix TEXT` | Log message prefix (max 29 chars, when action includes log) | auto |
| `--log-level LEVEL` | Syslog level: emerg/alert/crit/err/warning/notice/info/debug | — |
| `--limit RATE` | Rate limit: N/second, N/minute, N/hour, N/day | — |
| `--limit-burst N` | Burst packets before rate limit applies | 5 |
| `--duration TYPE` | permanent or temporary | permanent |
| `--ttl SECONDS` | TTL for temporary rules (60-2592000) | — |
| `--description TEXT` | Human-readable description | — |
| `--zone ZONE` | Firewalld zone name | public |
| `--chain CHAIN` | iptables/nftables chain (auto-set from direction) | auto |
| `--table TABLE` | iptables table (filter/nat/mangle/raw) or nftables table | filter |

### Basic Examples

```bash
# Allow HTTPS inbound
sudo ./apotropaios.sh add-rule --protocol tcp --dst-port 443 --action accept

# Block a specific IP
sudo ./apotropaios.sh add-rule --src-ip 10.0.0.50 --action drop --description "Block attacker"

# Allow DNS (temporary, 1 hour)
sudo ./apotropaios.sh add-rule --protocol udp --dst-port 53 --action accept \
    --duration temporary --ttl 3600

# Allow a port range
sudo ./apotropaios.sh add-rule --protocol tcp --dst-port 8080-8090 --action accept

# Outbound rule on specific interface
sudo ./apotropaios.sh add-rule --direction outbound --protocol tcp --dst-port 25 \
    --action reject --interface eth0 --description "Block SMTP outbound"
```

---

## Compound Actions

Rules can combine non-terminal actions (like `log`) with a terminal action (like `drop`, `accept`, `reject`). Use comma-separated syntax:

```bash
# Log and drop — the most common compound action
sudo ./apotropaios.sh add-rule --src-ip 10.0.0.0/8 --action log,drop \
    --log-prefix "BLOCKED: " --log-level warning

# Log and accept
sudo ./apotropaios.sh add-rule --protocol tcp --dst-port 22 --action log,accept \
    --log-prefix "SSH: "

# Log and reject
sudo ./apotropaios.sh add-rule --protocol tcp --dst-port 23 --action log,reject
```

### How Backends Handle Compound Actions

Each backend translates compound actions into its native equivalent:

| Backend | Compound Action Translation |
|:--------|:----------------------------|
| **iptables** | Creates two separate rules: LOG rule first, then terminal rule. This is the correct iptables pattern since LOG is non-terminating. |
| **nftables** | Combines in a single expression: `log prefix "..." drop`. nft handles this natively. |
| **firewalld** | Rich rule with log clause: `rule ... log prefix="..." level="..." drop`. |
| **ufw** | Extracts the terminal action for the ufw verb; enables logging separately via `ufw logging on`. |

### Validation Rules

- At most **one terminal action** per compound: `log,drop` is valid; `drop,accept` is invalid.
- Terminal actions: accept, drop, reject, masquerade, snat, dnat, return.
- Non-terminal actions: log.
- Log options (`--log-prefix`, `--log-level`) only apply when the action includes `log`.

---

## Connection Tracking

Connection tracking allows rules to match traffic based on the connection's state in the kernel's conntrack table:

```bash
# Allow established and related connections (stateful firewall baseline)
sudo ./apotropaios.sh add-rule --conn-state established,related --action accept

# Only match new connections on port 443
sudo ./apotropaios.sh add-rule --protocol tcp --dst-port 443 \
    --conn-state new --action accept

# Drop invalid packets
sudo ./apotropaios.sh add-rule --conn-state invalid --action drop
```

### Available States

| State | Description |
|:------|:------------|
| `new` | First packet of a new connection |
| `established` | Packet belongs to an existing, tracked connection |
| `related` | Packet starting a new connection related to an existing one (e.g., FTP data) |
| `invalid` | Packet that does not match any known connection |
| `untracked` | Packet explicitly excluded from connection tracking |

Multiple states can be comma-separated: `--conn-state new,established,related`.

### Backend Translation

| Backend | Implementation |
|:--------|:---------------|
| iptables | `-m conntrack --ctstate NEW,ESTABLISHED,RELATED` |
| nftables | `ct state new,established,related` |
| firewalld | Rich rule with connection state matching |
| ufw | Uses underlying iptables conntrack |

---

## Rate Limiting

Rate limiting controls how many packets matching a rule are processed per time unit. Useful for mitigating brute force, DDoS, and scan attacks:

```bash
# Limit SSH connections to 5 per minute
sudo ./apotropaios.sh add-rule --protocol tcp --dst-port 22 --action accept \
    --limit 5/minute --limit-burst 10

# Log excessive ICMP (ping flood mitigation)
sudo ./apotropaios.sh add-rule --protocol icmp --action log,accept \
    --limit 1/second --limit-burst 5 --log-prefix "ICMP-FLOOD: "

# Rate limit HTTP connections
sudo ./apotropaios.sh add-rule --protocol tcp --dst-port 80 --action accept \
    --limit 100/minute
```

### Rate Format

`N/unit` where unit is: `second`, `minute`, `hour`, or `day`.

`--limit-burst N` specifies how many packets are allowed before the rate limit takes effect (default: 5).

### Backend Translation

| Backend | Implementation |
|:--------|:---------------|
| iptables | `-m limit --limit 5/minute --limit-burst 10` |
| nftables | `limit rate 5/minute burst 10 packets` |
| firewalld | Rich rule: `limit value="5/m"` |

---

## Rule Lifecycle

Every rule created through Apotropaios follows this lifecycle:

1. **Created** — Parameters validated, UUID assigned, tracking comment generated
2. **Applied** — Rule dispatched to the firewall backend (with compound action translation)
3. **Indexed** — Rule recorded in the persistent pipe-delimited index with all fields
4. **Active** — Rule is enforced by the firewall

From the active state, a rule can be:

- **Deactivated** — Removed from the firewall but retained in the index. Can be re-activated later.
- **Removed** — Deleted from both the firewall and the index permanently.
- **Expired** — Temporary rules automatically transition to inactive when their TTL expires.

### Rule Index Fields

Each indexed rule stores: UUID, backend, direction, action, protocol, source/destination IP, source/destination port, interface, chain, table, zone, set name, connection state, log prefix, log level, rate limit, rate burst, duration type, TTL, description, state, creation timestamp.

Use `list-rules` to see all tracked rules with their current state.

---

## Temporary Rules with TTL

Temporary rules are automatically deactivated after their TTL (time-to-live) expires.

```bash
# Block an IP for 30 minutes (1800 seconds)
sudo ./apotropaios.sh add-rule --src-ip 192.168.1.100 --action drop \
    --duration temporary --ttl 1800 --description "Temporary block"

# Allow testing port for 2 hours
sudo ./apotropaios.sh add-rule --protocol tcp --dst-port 8080 --action accept \
    --duration temporary --ttl 7200 --description "Testing window"
```

TTL range: 60 seconds (1 minute) to 2,592,000 seconds (30 days).

### Expiry Watcher

The interactive menu includes a **Rule Expiry Watcher** (Rule Management > View rule expiry) that displays:

- Color-coded time remaining (green > 50%, yellow > 20%, red < 20%)
- Option to extend TTL on expiring rules
- Automatic cleanup of expired rules on framework startup

---

## Backend Configuration

Each firewall backend has a dedicated configuration submenu accessible via **Firewall Management > Backend configuration** in the interactive menu.

### iptables (7 options)

Check/view/save/restore iptables configuration, show table summary, view chain policies.

### nftables (5 options)

Check/view/save nftables configuration, list tables, list chains.

### firewalld (6 options)

Show default zone, list all zones, list active zones, list services, list rich rules, compare runtime vs permanent configuration.

### ufw (9 options)

1. Check UFW defaults — view input/output/forward default policies
2. View UFW defaults file — raw `/etc/default/ufw` contents
3. Show application profiles — list all detected apps with port details
4. Enable application profile — select from detected apps and create allow rules
5. Disable application profile — select and remove rules for an app
6. Show logging level — current ufw logging level
7. Set logging level — choose off/low/medium/high/full with descriptions
8. List config files — browse `/etc/ufw/` and `/etc/ufw/applications.d/`
9. Set default policies — configure incoming/outgoing/routed defaults

### ipset (7 options)

Check/view/save/load ipset configuration, list active sets, create new set, flush all sets.

---

## Importing and Exporting Rules

### Export

```bash
# Export to specific path
sudo ./apotropaios.sh export /tmp/my-rules.conf

# Interactive menu: uses timestamped default path
# data/rules/apotropaios-rules-TIMESTAMP.conf
```

Export creates a key-value format file and a SHA-256 checksum sidecar (`.sha256`).

### Import

```bash
# Import from file
sudo ./apotropaios.sh import /tmp/my-rules.conf
```

During import, each line is validated before application. The interactive menu offers a dry-run preview and a file scanner to browse available rule files.

### Configuration File Format

```
# Lines starting with # are comments
# Blank lines are ignored
direction=inbound action=accept protocol=tcp dst_port=443 duration_type=permanent description="Allow HTTPS"
direction=inbound action=log,drop src_ip=10.0.0.0/8 duration_type=permanent description="Log and block RFC1918"
direction=inbound action=accept conn_state=established,related duration_type=permanent description="Stateful baseline"
direction=outbound action=accept protocol=udp dst_port=53 duration_type=temporary ttl=7200 description="Allow DNS 2h"
```

### Supported Import Fields

`direction`, `action`, `protocol`, `src_ip`, `dst_ip`, `src_port`, `dst_port`, `duration_type`, `ttl`, `description`, `conn_state`, `log_prefix`, `log_level`, `limit`, `limit_burst`, `zone`, `table`, `chain`, `interface`

---

## Backup and Recovery

### Creating Backups

```bash
# CLI with descriptive label
sudo ./apotropaios.sh backup pre-deployment

# The backup includes:
# - All detected firewall configurations (iptables rules, nft ruleset, etc.)
# - Rule index and state files
# - Compressed with gzip, verified with SHA-256
```

### Restoring from Backup

```bash
sudo ./apotropaios.sh restore data/backups/apotropaios_backup_pre-deployment_2026-03-25T15-30-00.tar.gz
```

A pre-restore safety backup is automatically created before applying the restoration.

### Immutable Snapshots

Via the interactive menu (Backup & Recovery), immutable snapshots use `chattr +i` to prevent modification after creation:

- Cannot be deleted, modified, or overwritten without removing the immutable attribute
- SHA-256 checksum verified on creation
- Useful for production baselines and compliance auditing

### Backup Contents

| Component | What's Backed Up |
|:----------|:-----------------|
| iptables | `iptables-save` output |
| nftables | `nft list ruleset` output |
| firewalld | Runtime and permanent zone/service/rich rule configuration |
| ufw | `/etc/ufw/` configuration files |
| ipset | `ipset save` output |
| Rule index | Apotropaios rule tracking database |
| State data | TTL tracking, activation state |

---

## Quick Actions

### Block All Traffic

```bash
sudo ./apotropaios.sh block-all
```

Sets all default policies to DROP while preserving loopback connectivity. An automatic restore point is created before the block is applied.

### Allow All Traffic

```bash
sudo ./apotropaios.sh allow-all
```

Removes all firewall restrictions by setting default policies to ACCEPT and flushing rules. Use with caution — this leaves the system unprotected.

Both quick actions are available from the interactive menu under **Quick Actions**.

---

## Logging and Troubleshooting

### Log Location

Logs are written to `data/logs/` with ISO 8601 timestamps:

```
data/logs/apotropaios-2026-03-25T15-30-00.log
```

### Log Format

```
[2026-03-25T15:30:00.123Z] [INFO    ] [rule_engine] [cid:a1b2c3d4] Rule created: abc-def-123
```

Each entry includes: timestamp, severity level, component name, correlation ID, and message.

### Log Levels

From most to least verbose: `TRACE`, `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`

```bash
# Maximum diagnostic detail
sudo ./apotropaios.sh --log-level trace detect

# Production — warnings and above only
sudo ./apotropaios.sh --log-level warning add-rule --dst-port 443 --action accept
```

### Log Rotation

Rotation occurs automatically when log file count exceeds the retention limit (default: 30 files). Oldest files are removed first.

### Security

- Sensitive data (passwords, tokens, API keys) is automatically masked in log output
- Control characters are stripped to prevent log injection (CWE-117)
- Log files are created with 600 permissions (owner read/write only)

### Diagnostic Commands

```bash
# System scan with maximum detail
sudo ./apotropaios.sh --log-level trace detect

# Check last log file
ls -la data/logs/ | tail -3

# View recent log entries
tail -50 data/logs/apotropaios-*.log | less

# Check bash version (for compatibility debugging)
bash --version

# Check installed firewalls
which iptables nft firewall-cmd ufw ipset

# Check kernel version
uname -r
```

---

## Configuration File Reference

The configuration file is at `conf/apotropaios.conf` (or `/etc/apotropaios/apotropaios.conf` for system-wide installs):

```ini
# ==============================================================================
# Logging
# ==============================================================================
LOG_LEVEL=INFO                    # TRACE, DEBUG, INFO, WARNING, ERROR, CRITICAL
LOG_DIR=data/logs                 # Relative to installation directory
LOG_MAX_SIZE_MB=100               # Max log file size before rotation
LOG_MAX_FILES=30                  # Number of log files to retain

# ==============================================================================
# Default Backend (auto-detected if empty)
# ==============================================================================
DEFAULT_BACKEND=                  # iptables, nftables, firewalld, ufw, ipset

# ==============================================================================
# Backup
# ==============================================================================
BACKUP_DIR=data/backups           # Relative to installation directory
BACKUP_MAX_RETAINED=20            # Max backup archives to keep

# ==============================================================================
# Rules
# ==============================================================================
RULES_DIR=data/rules              # Relative to installation directory
RULE_DEFAULT_DURATION=permanent   # permanent or temporary

# ==============================================================================
# Security
# ==============================================================================
LOCK_TIMEOUT=30                   # Seconds to wait for advisory lock
```

Override at runtime with `--log-level LEVEL` or `--backend BACKEND` flags.
