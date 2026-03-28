# Apotropaios — Setup & Installation Guide

A comprehensive guide for installing, configuring, and verifying Apotropaios across all supported platforms.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Quick Install](#quick-install)
3. [Manual Installation](#manual-installation)
4. [Distribution-Specific Notes](#distribution-specific-notes)
5. [Configuration](#configuration)
6. [Post-Installation Setup](#post-installation-setup)
7. [Verifying Installation](#verifying-installation)
8. [Installing Firewall Backends](#installing-firewall-backends)
9. [Data Directory Structure](#data-directory-structure)
10. [Permissions and Security Hardening](#permissions-and-security-hardening)
11. [Container and Virtual Machine Notes](#container-and-virtual-machine-notes)
12. [Development Environment Setup](#development-environment-setup)
13. [Upgrading](#upgrading)
14. [Uninstallation](#uninstallation)
15. [Troubleshooting Installation Issues](#troubleshooting-installation-issues)

---

## System Requirements

### Minimum Requirements

- Linux operating system (see supported distributions below)
- Bash 4.0 or newer (for associative arrays and modern features)
- Root access (for firewall operations)
- Core utilities: `coreutils`, `grep`, `sed`, `awk`, `tar`, `gzip`, `procps`, `util-linux`

### Supported Distributions

| Distribution | Version | Package Manager | Tested In CI |
|:------------|:--------|:----------------|:-------------|
| Ubuntu | 22.04 LTS, 24.04 LTS | apt | Yes |
| Kali Linux | Rolling | apt | Yes |
| Debian | 12 (Bookworm) | apt | Yes |
| Rocky Linux | 9 | dnf | Yes |
| AlmaLinux | 9 | dnf | Yes |
| Arch Linux | Rolling | pacman | Yes |

### Optional Dependencies

| Tool | Purpose | Required For |
|:-----|:--------|:-------------|
| BATS | Bash Automated Testing System | Running tests (`make test`) |
| ShellCheck | Static analysis linter | Linting (`make lint`) |
| Git | Version control | Cloning, updates, development |
| `chattr` | Filesystem attributes | Immutable backup snapshots |

**No external runtime dependencies** — Apotropaios uses only bash built-ins and standard system utilities. No Python, Ruby, Node.js, or third-party packages are required.

### Checking Bash Version

```bash
bash --version
# Output must show 4.0 or newer
# GNU bash, version 5.2.21(1)-release (x86_64-pc-linux-gnu)
```

If your bash is older than 4.0, upgrade it through your package manager before proceeding.

---

## Quick Install

```bash
# Clone the repository
git clone https://github.com/apotropaios-project/apotropaios.git
cd apotropaios

# Install system-wide
sudo make install

# Verify
sudo apotropaios --version
sudo apotropaios detect
```

This installs to `/opt/apotropaios`, creates a symlink at `/usr/local/bin/apotropaios`, and copies configuration to `/etc/apotropaios/`.

---

## Manual Installation

If you prefer not to use `make install`:

```bash
# 1. Extract or clone to your preferred location
git clone https://github.com/apotropaios-project/apotropaios.git /opt/apotropaios

# 2. Set executable permission
chmod +x /opt/apotropaios/apotropaios.sh

# 3. Create data directories with secure permissions
mkdir -p /opt/apotropaios/data/{logs,rules,backups}
chmod 700 /opt/apotropaios/data /opt/apotropaios/data/*

# 4. Create configuration directory
mkdir -p /etc/apotropaios
cp /opt/apotropaios/conf/apotropaios.conf /etc/apotropaios/

# 5. Optional: create a symlink for PATH access
ln -sf /opt/apotropaios/apotropaios.sh /usr/local/bin/apotropaios

# 6. First run
sudo /opt/apotropaios/apotropaios.sh detect
```

### From Release Tarball

```bash
# Download the release
wget https://github.com/apotropaios-project/apotropaios/releases/latest/download/apotropaios-1.1.5.tar.gz

# Verify checksum
wget https://github.com/apotropaios-project/apotropaios/releases/latest/download/SHA256SUMS.txt
sha256sum -c SHA256SUMS.txt

# Extract and install
tar -xzf apotropaios-1.1.5.tar.gz
cd apotropaios-1.1.5
sudo make install
```

---

## Distribution-Specific Notes

### Ubuntu / Debian / Kali Linux

These distributions use `apt`. Core utilities are typically pre-installed.

```bash
# Ensure core prerequisites are present
sudo apt-get update
sudo apt-get install -y bash coreutils procps util-linux

# Kali Linux specific: verify bash version (should be 5.x)
bash --version
```

**Kali Linux note:** Kali's rolling release model means bash and system library versions change frequently. Apotropaios v1.1.5+ includes portable validation that works across all bash versions shipped with Kali.

### Rocky Linux 9 / AlmaLinux 9

RHEL-family distributions use `dnf`. Minimal container images may need the `--allowerasing` flag.

```bash
# Standard installation
sudo dnf install -y bash coreutils procps-ng util-linux

# In containers (minimal images):
sudo dnf install -y --allowerasing bash coreutils procps-ng util-linux
```

**Note:** RHEL-family distributions use `procps-ng` instead of `procps`.

### Arch Linux

```bash
sudo pacman -Sy bash coreutils procps-ng util-linux
```

**Note:** Arch's rolling release means packages are always current. Apotropaios is tested against the latest Arch packages in CI.

---

## Configuration

### Configuration File

Apotropaios reads configuration from `conf/apotropaios.conf` (relative to the installation directory). When installed system-wide, a copy is placed at `/etc/apotropaios/apotropaios.conf`.

The configuration file controls:

| Setting | Default | Description |
|:--------|:--------|:------------|
| `LOG_LEVEL` | `INFO` | Logging verbosity: TRACE, DEBUG, INFO, WARNING, ERROR, CRITICAL |
| `LOG_RETENTION` | `30` | Number of log files to retain before rotation |
| `BACKUP_RETENTION` | `10` | Number of backup archives to keep |
| `DEFAULT_BACKEND` | (auto) | Preferred firewall backend (auto-detected if not set) |
| `RULE_INDEX_FILE` | `data/rules/rule_index.dat` | Path to the persistent rule index |
| `LOCK_TIMEOUT` | `30` | Seconds to wait for advisory lock acquisition |

### Overriding Configuration at Runtime

```bash
# Set log level for a single run
sudo apotropaios --log-level trace detect

# Set log level for a single run (debug for detailed output)
sudo apotropaios --log-level debug add-rule --dst-port 443 --action accept
```

---

## Post-Installation Setup

### First Run

On first run, Apotropaios will automatically:

1. Detect your operating system (distribution, version, package manager)
2. Scan for all installed firewall applications across all 5 supported backends
3. Create the data directory structure with secure permissions (700)
4. Initialize the logging subsystem with timestamped log files (600)
5. Auto-select the first available firewall backend

```bash
# First run — detection and initialization
sudo apotropaios detect
```

### Installing a Firewall Backend

If no firewall is detected, install one:

```bash
# Interactive installation
sudo apotropaios
# Navigate to: Install & Update > select firewall

# CLI installation
sudo apotropaios install ufw
sudo apotropaios install iptables
sudo apotropaios install nftables
sudo apotropaios install firewalld
```

### Selecting a Backend

If multiple firewalls are installed:

```bash
# CLI
sudo apotropaios --backend iptables detect

# Interactive menu
sudo apotropaios
# Navigate to: Firewall Management > Select active firewall backend
```

### Creating an Initial Backup

Before making any changes, create a baseline backup:

```bash
sudo apotropaios backup initial-baseline
```

This creates a timestamped, compressed archive with SHA-256 checksum in `data/backups/`.

---

## Verifying Installation

```bash
# Check version
sudo apotropaios --version

# Run OS and firewall detection
sudo apotropaios detect

# Verify make targets (if installed from source)
make verify

# Run the test suite (requires BATS)
make test
```

### Expected Output

```
Apotropaios - Firewall Manager v1.1.5

[INFO    ] [logging] Logging initialized...
[INFO    ] [os_detect] OS detected via /etc/os-release: Ubuntu (ubuntu)
[INFO    ] [fw_detect] Firewall detection complete: N firewall(s) found
```

---

## Installing Firewall Backends

Apotropaios can manage installation through your system's package manager, or you can install manually:

| Firewall | Ubuntu/Debian/Kali | Rocky/Alma (dnf) | Arch (pacman) |
|:---------|:-------------------|:------------------|:--------------|
| firewalld | `apt install firewalld` | `dnf install firewalld` | `pacman -S firewalld` |
| ipset | `apt install ipset` | `dnf install ipset` | `pacman -S ipset` |
| iptables | `apt install iptables` | `dnf install iptables` | `pacman -S iptables` |
| nftables | `apt install nftables` | `dnf install nftables` | `pacman -S nftables` |
| ufw | `apt install ufw` | `dnf install ufw` | `pacman -S ufw` |

**Recommendation:** For new installations on modern systems, `nftables` is the recommended backend (successor to iptables). For simpler setups, `ufw` provides a user-friendly interface built on iptables/nftables.

---

## Data Directory Structure

Apotropaios stores all runtime data under the `data/` directory:

```
data/
├── logs/                    # Timestamped log files (600 permissions)
│   ├── apotropaios-2026-03-25T15-30-00.log
│   └── .gitkeep
├── rules/                   # Rule index and exported configurations (600)
│   ├── rule_index.dat       # Persistent pipe-delimited rule index
│   └── .gitkeep
└── backups/                 # Compressed backup archives (600)
    ├── apotropaios_backup_2026-03-25T15-30-00.tar.gz
    ├── apotropaios_backup_2026-03-25T15-30-00.tar.gz.sha256
    └── .gitkeep
```

All data directories are created with 700 permissions (owner-only access). All data files are created with 600 permissions (owner read/write only).

---

## Permissions and Security Hardening

### Default Permissions

| Resource | Permissions | Description |
|:---------|:-----------|:------------|
| `data/` directories | 700 | Owner-only access |
| Log files | 600 | Owner read/write |
| Rule index | 600 | Owner read/write |
| Backup archives | 600 | Owner read/write |
| Configuration files | 600 | Owner read/write |
| Temporary files | 600 | Created via `mktemp` |

### Additional Hardening

For production deployments:

```bash
# 1. Run with minimum necessary privileges
# Use root only when firewall operations are needed

# 2. Restrict data directory access
chmod 700 /opt/apotropaios/data
chown root:root /opt/apotropaios/data

# 3. Enable immutable snapshots for critical baselines
sudo apotropaios backup --immutable production-baseline

# 4. Set restrictive log level
sudo apotropaios --log-level warning detect

# 5. Enable SELinux/AppArmor if available
# (Apotropaios works within standard security module contexts)
```

### umask

Apotropaios sets `umask 077` at initialization, ensuring all files and directories created during execution are accessible only by the owner.

---

## Container and Virtual Machine Notes

### Docker

Apotropaios runs in Docker containers but requires appropriate capabilities for firewall operations:

```bash
# Run with NET_ADMIN capability for firewall management
docker run --cap-add=NET_ADMIN -it ubuntu:24.04 bash

# Or run with full privileges (testing only)
docker run --privileged -it ubuntu:24.04 bash
```

**Note:** Container-based firewall management affects the container's network namespace, not the host. For host-level firewall management, run Apotropaios directly on the host.

### WSL (Windows Subsystem for Linux)

Apotropaios detection and rule management work in WSL 2. Note that:

- WSL 2 has its own network namespace with iptables/nftables support
- Firewall rules in WSL do not affect the Windows host firewall
- Some firewall backends may not be available in WSL 1

### Virtual Machines

Apotropaios works identically in VMs (VMware, VirtualBox, KVM, Hyper-V) as on bare metal. No special configuration is required.

---

## Development Environment Setup

For contributors and testers:

```bash
# Clone the repository
git clone https://github.com/apotropaios-project/apotropaios.git
cd apotropaios

# Automated setup (installs BATS, checks ShellCheck)
make dev-setup

# Or manual setup:
# Install BATS
git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats
sudo /tmp/bats/install.sh /usr/local

# Install ShellCheck
sudo apt-get install shellcheck        # Debian/Ubuntu/Kali
sudo dnf install ShellCheck            # RHEL family
sudo pacman -S shellcheck              # Arch

# Verify everything works
make test              # Full suite: lint + unit + integration + security (375 tests)
make test-report       # Detailed per-file breakdown
make check-deps        # Show all tool availability
make metrics           # Project statistics
```

See [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) for coding standards and [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution workflow.

---

## Upgrading

### From Git

```bash
cd /opt/apotropaios    # or your installation directory
git pull origin main
sudo make install
sudo apotropaios --version
```

### From Release Tarball

```bash
# Download new version
wget https://github.com/apotropaios-project/apotropaios/releases/latest/download/apotropaios-X.Y.Z.tar.gz

# Backup current data
cp -r /opt/apotropaios/data /tmp/apotropaios-data-backup

# Extract and install
tar -xzf apotropaios-X.Y.Z.tar.gz
cd apotropaios-X.Y.Z
sudo make install

# Verify
sudo apotropaios --version
```

**Data preservation:** The `make install` target never overwrites the `data/` directory. Logs, rules, and backups are preserved across upgrades. The existing configuration at `/etc/apotropaios/apotropaios.conf` is also preserved — new config is only copied if no config exists.

---

## Uninstallation

### Using Make

```bash
sudo make uninstall
```

This removes the installation from `/opt/apotropaios` and the symlink at `/usr/local/bin/apotropaios`, but **preserves the data directory** (logs, rules, backups) for safety. Remove it manually if desired.

### Manual Removal

```bash
# Remove binary and symlink
sudo rm -f /usr/local/bin/apotropaios

# Remove installation (preserves data)
sudo rm -rf /opt/apotropaios/lib /opt/apotropaios/conf /opt/apotropaios/docs /opt/apotropaios/apotropaios.sh

# Remove configuration
sudo rm -rf /etc/apotropaios

# CAUTION: Remove data (logs, tracked rules, backups)
sudo rm -rf /opt/apotropaios/data
```

**Important:** Uninstallation does not modify or remove any firewall rules that were applied through Apotropaios. Active rules remain in their respective firewall backends. To remove applied rules before uninstalling, use the interactive menu or CLI to deactivate/remove tracked rules.

---

## Troubleshooting Installation Issues

### "Invalid log directory path" on startup

**Cause:** Typically occurs when the installation path contains shell metacharacters (parentheses, ampersands, etc.) or when running an older version on newer bash.

**Fix:** Upgrade to v1.1.5+ which uses portable whitelist-based path validation. Ensure the installation path contains only alphanumeric characters, slashes, hyphens, underscores, dots, and spaces.

### "BATS not installed" when running make test

```bash
make dev-setup    # Automated BATS installation
```

### "Permission denied" during firewall operations

Firewall management requires root. Always run with `sudo`:

```bash
sudo apotropaios detect
sudo apotropaios add-rule --dst-port 443 --action accept
```

### "No firewall backends detected"

Install at least one supported firewall:

```bash
sudo apt-get install ufw         # Ubuntu/Debian/Kali
sudo dnf install firewalld       # Rocky/Alma
sudo pacman -S nftables          # Arch
```

Then re-run detection:

```bash
sudo apotropaios detect
```

### "bash: apotropaios: command not found"

The symlink may not have been created. Either:

```bash
# Re-run install
sudo make install

# Or run directly
sudo /opt/apotropaios/apotropaios.sh
```

### Diagnostic Commands

```bash
# Maximum diagnostic detail
sudo apotropaios --log-level trace detect

# Check bash version
bash --version

# Check installed firewalls
which iptables nft firewall-cmd ufw ipset 2>/dev/null

# Check kernel version
uname -r

# Check SELinux status
getenforce 2>/dev/null || echo "SELinux not available"

# Check available dependencies
make check-deps
```

For additional help, see the [Troubleshooting Guide](wiki/Troubleshooting-Guide.md) in the wiki or [open an issue](https://github.com/apotropaios-project/apotropaios/issues/new?template=bug_report.yml).
