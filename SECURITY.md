# Security Policy

## Supported Versions

| Version | Support Status | Notes |
|---------|---------------|-------|
| 1.1.x | ✅ Active | Full security support |
| 1.0.x | ⚠️ Critical only | Critical vulnerability patches only |
| < 1.0 | ❌ Unsupported | No security updates |

## Reporting a Vulnerability

### Critical / High Severity

For **critical** or **high** severity vulnerabilities (remote code execution, privilege escalation, authentication bypass, significant data exposure):

1. **DO NOT** create a public GitHub issue
2. Use [GitHub's private vulnerability reporting](https://github.com/Sandler73/Apotropaios-Firewall-Manager/security/advisories/new)
3. Alternatively, email the maintainers with subject: `[SECURITY] Apotropaios vulnerability report`

### Medium / Low Severity

For **medium** or **low** severity issues (input validation gaps, hardening suggestions, defense-in-depth improvements):

1. Use the [Security Vulnerability issue template](https://github.com/Sandler73/Apotropaios-Firewall-Manager/issues/new?template=security_vulnerability.yml)

### What to Include

- Affected version(s)
- Vulnerability category (CWE ID if known)
- Detailed description of the vulnerability
- Steps to reproduce / proof of concept
- Impact assessment (what an attacker could achieve)
- Suggested remediation (if any)

### Response Timeline

| Action | Target |
|--------|--------|
| Acknowledgment | Within 48 hours |
| Initial assessment | Within 72 hours |
| Critical fix release | Within 7 days |
| High fix release | Within 14 days |
| Medium/Low fix release | Next scheduled release |

### Disclosure Policy

We follow coordinated disclosure:

1. Reporter submits vulnerability privately
2. We acknowledge and begin investigation
3. We develop and test a fix
4. We release the fix with a security advisory
5. Reporter is credited (unless anonymity requested)

We request a **90-day disclosure window** before public disclosure. We will work to release fixes well before this deadline.

## Security Architecture

Apotropaios implements defense-in-depth security controls derived from industry standards:

### Standards Alignment

| Standard | Coverage |
|----------|----------|
| OWASP CRG | Input validation, injection prevention |
| NIST SP 800-218 (SSDF) | Secure development lifecycle |
| CWE/SANS Top 25 | Addressed vulnerability classes |
| CWE-20 | Improper input validation |
| CWE-22 | Path traversal |
| CWE-78 | OS command injection |
| CWE-117 | Log injection |
| CWE-200 | Information disclosure |
| CWE-377 | Insecure temporary file |
| CWE-532 | Sensitive data in logs |
| CWE-732 | Insecure file permissions |

### Security Controls

**Input Boundary:**
- 28 whitelist validators for all user-supplied data types
- Shell metacharacter rejection via portable glob-based detection (`_contains_shell_meta`)
- Whitelist-based input sanitization — `sanitize_input()` keeps only known-safe characters
- Path traversal detection and rejection
- Maximum input length enforcement (4096 chars)
- nftables table family validation (inet/ip/ip6/arp/bridge/netdev)

**Command Construction:**
- All firewall commands built using bash arrays — never string interpolation
- No `eval` of user-supplied data; zero `eval` in logging subsystem
- Validated parameters only passed to system commands
- No file-based command execution (nft -f removed — injection vector)
- Parameters re-validated from index before rule removal operations

**File Security:**
- umask 077 enforced at initialization
- Data files: 600 permissions (owner read/write)
- Data directories: 700 permissions (owner only)
- Temporary files via `mktemp` with secure defaults
- Atomic file writes (temp + rename pattern)

**Cryptographic Integrity:**
- SHA-256 checksums on all backup archives
- Import file integrity verification
- Immutable snapshots with `chattr +i` protection

**Logging Security:**
- Automatic masking of sensitive data in 4 formats: key=value, key="quoted", JSON (`"key": "value"`), HTTP Authorization headers (Bearer/Basic/Digest/Token)
- Control character stripping from log messages (CWE-117 prevention)
- Log files written with 600 permissions

**Memory Security:**
- Sensitive variable registration and scrubbing on exit
- Cleanup handlers fire on EXIT, SIGTERM, SIGINT, SIGHUP

**Advisory Locking:**
- Atomic locking via `flock(1)` when available (no TOCTOU race condition)
- Fallback: `noclobber` file creation with PID validation
- Stale lock detection (dead PID removal)
- Configurable timeout (default: 30 seconds)

## Security Testing

The project includes comprehensive security-focused testing:

```bash
make test-sec          # Run CWE-mapped security tests (48 tests)
make test-security     # Run security module unit tests (23 tests)
make test-validation   # Run input validation tests (88 tests)
make security-scan     # Static pattern analysis (6 checks, no external tools)
make lint              # ShellCheck static analysis
```

### CWE Coverage

| CWE | Category | Tests |
|:----|:---------|------:|
| CWE-78 | OS Command Injection | 12 |
| CWE-22 | Path Traversal | 5 |
| CWE-20 | Input Validation Boundaries | 14 |
| CWE-117/532 | Log Injection / Sensitive Data | 6 |
| CWE-732 | Insecure File Permissions | 4 |
| CWE-377 | Insecure Temporary File | 2 |
| CWE-200 | Information Disclosure | 1 |
| — | Cryptographic Integrity | 2 |
| — | Advisory Locking | 2 |

## Hardening Recommendations

When deploying Apotropaios in production:

1. Run with minimum necessary privileges (root only for firewall operations)
2. Set `--log-level warning` to minimize log verbosity
3. Use immutable snapshots for critical baseline configurations
4. Restrict access to the `data/` directory
5. Enable SELinux/AppArmor if available
6. Review rule exports before importing on production systems
7. Use the dry-run mode for imports: `import FILE --dry-run`
