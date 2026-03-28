# ==============================================================================
# Makefile for Apotropaios - Firewall Manager
#
# Synopsis:     make [TARGET]
# Description:  Build, test, lint, security scan, install, and package targets.
#               CI pipelines should call make targets, not duplicate their logic.
#               (CI/CD Lesson #12: Makefile as Single Entry Point)
#
# Notes:        - VERSION is auto-extracted from lib/core/constants.sh
#               - All test targets depend on _check-bats for BATS availability
#               - TAP output written to test-results/ for CI artifact upload
#               - Security targets require no external tools beyond ShellCheck
#
# Version:     1.1.5
# ==============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: all test test-unit test-integration test-sec test-all test-quick \
        lint syntax-check security-scan \
        test-report test-count test-list \
        test-validation test-logging test-os-detect test-fw-detect \
        test-security test-errors test-rule-engine test-backup \
        test-lifecycle test-import-export test-cli test-help-system \
        test-sec-injection \
        clean dist dist-full install uninstall verify \
        check-deps dev-setup info metrics \
        help

# ==============================================================================
# Project Metadata (auto-extracted from source)
# ==============================================================================
PROJECT      := apotropaios
VERSION      := $(shell grep -m1 'APOTROPAIOS_VERSION=' lib/core/constants.sh 2>/dev/null | cut -d'"' -f2 || echo "0.0.0")
DIST_DIR     := dist
STAGING_DIR  := $(DIST_DIR)/staging
INSTALL_DIR  := /opt/apotropaios
BIN_LINK     := /usr/local/bin/apotropaios
CONF_DIR     := /etc/apotropaios

# ==============================================================================
# Tool Configuration
# ==============================================================================
BATS         := bats
SHELLCHECK   := shellcheck
TAR          := tar
SHA256       := sha256sum

# ==============================================================================
# File Discovery
# ==============================================================================
TEST_DIR     := tests
TEST_UNIT    := $(TEST_DIR)/unit
TEST_INT     := $(TEST_DIR)/integration
TEST_SEC     := $(TEST_DIR)/security
TEST_RESULTS := test-results

SHELL_FILES  := $(shell find . -name '*.sh' -not -path './dist/*' -not -path './.git/*' -not -path './data/*' 2>/dev/null)
BATS_FILES   := $(shell find $(TEST_DIR) -name '*.bats' 2>/dev/null)

SHELL_COUNT  := $(words $(SHELL_FILES))
BATS_COUNT   := $(words $(BATS_FILES))

# ==============================================================================
# Community / Documentation Files
# ==============================================================================
COMMUNITY_FILES := README.md LICENSE CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                              DEFAULT TARGET                               ║
# ╚════════════════════════════════════════════════════════════════════════════╝

all: lint test

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           QUALITY ASSURANCE                               ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ==============================================================================
# Syntax Check — fastest gate, no external tools needed
# ==============================================================================
syntax-check:
	@echo "==> Syntax checking $(SHELL_COUNT) shell files..."
	@fail=0; \
	for f in $(SHELL_FILES); do \
		if ! bash -n "$$f" 2>/dev/null; then \
			echo "  FAIL: $$f"; \
			bash -n "$$f"; \
			fail=1; \
		fi; \
	done; \
	if [ "$$fail" -eq 1 ]; then exit 1; fi
	@echo "==> Syntax check passed ($(SHELL_COUNT) files)"

# ==============================================================================
# Lint — ShellCheck static analysis
# ==============================================================================
lint: syntax-check
	@echo "==> Running ShellCheck on $(SHELL_COUNT) files..."
	@if ! command -v $(SHELLCHECK) >/dev/null 2>&1; then \
		echo "WARNING: shellcheck not installed — skipping lint"; \
		echo "Install: sudo apt-get install shellcheck"; \
		exit 0; \
	fi; \
	fail=0; \
	for f in $(SHELL_FILES); do \
		if ! $(SHELLCHECK) -x "$$f" 2>/dev/null; then \
			fail=1; \
		fi; \
	done; \
	if [ "$$fail" -eq 1 ]; then \
		echo "ShellCheck found issues"; \
		exit 1; \
	fi
	@echo "==> ShellCheck passed"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                              TEST SUITE                                   ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ==============================================================================
# Full Test Suite (CI entry point)
# ==============================================================================
test: lint test-unit test-integration test-sec
	@echo ""
	@echo "  ================================================"
	@echo "  ✓ ALL TESTS PASSED — v$(VERSION)"
	@echo "  ================================================"
	@echo ""

# Quick test — unit only, no lint (for rapid development feedback)
test-quick: test-unit
	@echo "==> Quick tests passed"

# Full suite explicitly named
test-all: lint test-unit test-integration test-sec
	@echo "==> Full test suite passed"

# ==============================================================================
# Unit Tests
# ==============================================================================
test-unit: _check-bats
	@echo "==> Running all unit tests..."
	@mkdir -p $(TEST_RESULTS)
	@$(BATS) $(TEST_UNIT) --tap > $(TEST_RESULTS)/unit.tap 2>&1 || { \
		echo "Unit tests FAILED:"; \
		cat $(TEST_RESULTS)/unit.tap; \
		exit 1; \
	}
	@echo "==> Unit tests passed ($$(grep -c '^ok ' $(TEST_RESULTS)/unit.tap) tests)"

test-validation: _check-bats
	@$(BATS) $(TEST_UNIT)/validation.bats

test-logging: _check-bats
	@$(BATS) $(TEST_UNIT)/logging.bats

test-os-detect: _check-bats
	@$(BATS) $(TEST_UNIT)/os_detect.bats

test-fw-detect: _check-bats
	@$(BATS) $(TEST_UNIT)/fw_detect.bats

test-security: _check-bats
	@$(BATS) $(TEST_UNIT)/security.bats

test-errors: _check-bats
	@$(BATS) $(TEST_UNIT)/errors.bats

test-rule-engine: _check-bats
	@$(BATS) $(TEST_UNIT)/rule_engine.bats

test-backup: _check-bats
	@$(BATS) $(TEST_UNIT)/backup.bats

# ==============================================================================
# Integration Tests
# ==============================================================================
test-integration: _check-bats
	@echo "==> Running all integration tests..."
	@mkdir -p $(TEST_RESULTS)
	@$(BATS) $(TEST_INT) --tap > $(TEST_RESULTS)/integration.tap 2>&1 || { \
		echo "Integration tests FAILED:"; \
		cat $(TEST_RESULTS)/integration.tap; \
		exit 1; \
	}
	@echo "==> Integration tests passed ($$(grep -c '^ok ' $(TEST_RESULTS)/integration.tap) tests)"

test-lifecycle: _check-bats
	@$(BATS) $(TEST_INT)/lifecycle.bats

test-import-export: _check-bats
	@$(BATS) $(TEST_INT)/import_export.bats

test-cli: _check-bats
	@$(BATS) $(TEST_INT)/cli.bats

test-help-system: _check-bats
	@$(BATS) $(TEST_INT)/help_system.bats

# ==============================================================================
# Security Tests
# ==============================================================================
test-sec: _check-bats
	@echo "==> Running all security tests..."
	@mkdir -p $(TEST_RESULTS)
	@$(BATS) $(TEST_SEC) --tap > $(TEST_RESULTS)/security.tap 2>&1 || { \
		echo "Security tests FAILED:"; \
		cat $(TEST_RESULTS)/security.tap; \
		exit 1; \
	}
	@echo "==> Security tests passed ($$(grep -c '^ok ' $(TEST_RESULTS)/security.tap) tests)"

test-sec-injection: _check-bats
	@$(BATS) $(TEST_SEC)/injection.bats

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           SECURITY ANALYSIS                               ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ==============================================================================
# Security Scan — static pattern analysis (no external tools beyond grep)
# ==============================================================================
security-scan:
	@echo "==> Security pattern scan — v$(VERSION)"
	@echo ""
	@pass=0; warn=0; \
	echo "  [1/6] Checking for eval with variable expansion..."; \
	matches=$$(grep -rn 'eval.*\$$' lib/ apotropaios.sh --include='*.sh' 2>/dev/null | grep -v 'eval "exec' | grep -v '^\s*#'); \
	if [ -n "$$matches" ]; then \
		echo "$$matches" | head -5; \
		echo "  ⚠  WARNING: eval with variable expansion detected (review required)"; \
		warn=$$(( warn + 1 )); \
	else \
		echo "  ✓  PASS"; pass=$$(( pass + 1 )); \
	fi; \
	echo "  [2/6] Checking for hardcoded /tmp paths..."; \
	matches=$$(grep -rn '/tmp/' lib/ apotropaios.sh --include='*.sh' 2>/dev/null | grep -v '#\|mktemp\|test\|TMPDIR\|printf\|help\|echo'); \
	if [ -n "$$matches" ]; then \
		echo "$$matches" | head -5; \
		echo "  ⚠  WARNING: Hardcoded /tmp paths (use mktemp)"; \
		warn=$$(( warn + 1 )); \
	else \
		echo "  ✓  PASS"; pass=$$(( pass + 1 )); \
	fi; \
	echo "  [3/6] Checking for permissive file modes..."; \
	matches=$$(grep -rn 'chmod.*[67][0-9][0-9]' lib/ apotropaios.sh --include='*.sh' 2>/dev/null | grep -v '#\|700\|600\|chmod 755.*apotropaios'); \
	if [ -n "$$matches" ]; then \
		echo "$$matches" | head -5; \
		echo "  ⚠  WARNING: Permissions more permissive than 700/600"; \
		warn=$$(( warn + 1 )); \
	else \
		echo "  ✓  PASS"; pass=$$(( pass + 1 )); \
	fi; \
	echo "  [4/6] Checking for unquoted variable expansions in firewall commands..."; \
	matches=$$(grep -rn 'iptables \$$\|nft \$$\|firewall-cmd \$$\|ufw \$$\|ipset \$$' lib/firewall/ --include='*.sh' 2>/dev/null | grep -v '#\|log_info\|log_debug\|log_error\|log_warning'); \
	if [ -n "$$matches" ]; then \
		echo "$$matches" | head -5; \
		echo "  ⚠  WARNING: Unquoted variable in firewall command"; \
		warn=$$(( warn + 1 )); \
	else \
		echo "  ✓  PASS"; pass=$$(( pass + 1 )); \
	fi; \
	echo "  [5/6] Checking for curl/wget without certificate validation..."; \
	matches=$$(grep -rn 'curl.*-k\|curl.*--insecure\|wget.*--no-check-certificate' lib/ apotropaios.sh --include='*.sh' 2>/dev/null | grep -v '#'); \
	if [ -n "$$matches" ]; then \
		echo "$$matches" | head -5; \
		echo "  ⚠  WARNING: Insecure download detected"; \
		warn=$$(( warn + 1 )); \
	else \
		echo "  ✓  PASS"; pass=$$(( pass + 1 )); \
	fi; \
	echo "  [6/6] Checking for debug/test credentials left in code..."; \
	matches=$$(grep -rni 'password\s*=\s*["\x27][^*]' lib/ apotropaios.sh --include='*.sh' 2>/dev/null | grep -v '#\|MASKED\|sanitize\|_log_sanitize\|PATTERN\|mask\|sed.*password'); \
	if [ -n "$$matches" ]; then \
		echo "$$matches" | head -5; \
		echo "  ⚠  WARNING: Possible hardcoded credentials"; \
		warn=$$(( warn + 1 )); \
	else \
		echo "  ✓  PASS"; pass=$$(( pass + 1 )); \
	fi; \
	echo ""; \
	echo "  Results: $${pass} passed, $${warn} warnings"; \
	echo "==> Security scan complete"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           TEST REPORTING                                  ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ==============================================================================
# Test Report — detailed per-file summary with counts
# ==============================================================================
test-report: _check-bats
	@echo ""
	@echo "  ====================================================="
	@echo "  APOTROPAIOS TEST REPORT — v$(VERSION)"
	@echo "  $$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
	@echo "  ====================================================="
	@echo ""
	@mkdir -p $(TEST_RESULTS)
	@total_pass=0; total_fail=0; total_skip=0; \
	for f in $$(find $(TEST_DIR) -name '*.bats' | sort); do \
		name=$$(basename "$$f" .bats); \
		dir=$$(basename $$(dirname "$$f")); \
		output=$$($(BATS) "$$f" --tap 2>&1); \
		pass=$$(echo "$$output" | grep -c '^ok ' || true); \
		fail=$$(echo "$$output" | grep -c '^not ok ' || true); \
		skip=$$(echo "$$output" | grep -c '# skip' || true); \
		total=$$(( pass + fail )); \
		total_pass=$$(( total_pass + pass )); \
		total_fail=$$(( total_fail + fail )); \
		total_skip=$$(( total_skip + skip )); \
		if [ "$$fail" -gt 0 ]; then \
			status="FAIL"; \
		else \
			status="PASS"; \
		fi; \
		printf "  %-12s %-20s %3d/%3d  [%s]\n" "$$dir" "$$name" "$$pass" "$$total" "$$status"; \
	done; \
	echo ""; \
	echo "  -----------------------------------------------------"; \
	printf "  TOTAL: %d passed, %d failed, %d skipped\n" "$$total_pass" "$$total_fail" "$$total_skip"; \
	echo "  -----------------------------------------------------"; \
	if [ "$$total_fail" -gt 0 ]; then \
		echo "  RESULT: ✗ FAIL"; \
		exit 1; \
	else \
		echo "  RESULT: ✓ PASS"; \
	fi

# ==============================================================================
# Test Count — quick count without executing (uses bats --count)
# ==============================================================================
test-count: _check-bats
	@total=0; \
	for f in $$(find $(TEST_DIR) -name '*.bats' | sort); do \
		name=$$(basename "$$f" .bats); \
		dir=$$(basename $$(dirname "$$f")); \
		c=$$($(BATS) --count "$$f" 2>/dev/null || echo 0); \
		total=$$(( total + c )); \
		printf "  %-12s %-20s %3d tests\n" "$$dir" "$$name" "$$c"; \
	done; \
	echo "  ---"; \
	echo "  Total: $$total tests across $(BATS_COUNT) files"

# ==============================================================================
# Test List — list all test names without running them
# ==============================================================================
test-list: _check-bats
	@for f in $$(find $(TEST_DIR) -name '*.bats' | sort); do \
		dir=$$(basename $$(dirname "$$f")); \
		name=$$(basename "$$f" .bats); \
		echo ""; \
		echo "  [$$dir/$$name]"; \
		grep '^@test ' "$$f" | sed 's/@test "/ ├── /;s/" {$$//' | head -50; \
	done

# ==============================================================================
# BATS Availability Check
# ==============================================================================
_check-bats:
	@if ! command -v $(BATS) >/dev/null 2>&1; then \
		echo "ERROR: BATS not installed."; \
		echo "  Install: git clone https://github.com/bats-core/bats-core.git && cd bats-core && sudo ./install.sh /usr/local"; \
		echo "  Or run: make dev-setup"; \
		exit 1; \
	fi

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                              PACKAGING                                    ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ==============================================================================
# Distribution Package — runtime files only
# ==============================================================================
dist: clean
	@echo "==> Building distribution package v$(VERSION)..."
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)
	@cp -r lib conf apotropaios.sh Makefile .shellcheckrc .gitignore \
		$(COMMUNITY_FILES) \
		$(STAGING_DIR)/$(PROJECT)-$(VERSION)/ 2>/dev/null || true
	@cp -r docs $(STAGING_DIR)/$(PROJECT)-$(VERSION)/ 2>/dev/null || true
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)/data/logs
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)/data/rules
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)/data/backups
	@touch $(STAGING_DIR)/$(PROJECT)-$(VERSION)/data/logs/.gitkeep
	@touch $(STAGING_DIR)/$(PROJECT)-$(VERSION)/data/rules/.gitkeep
	@touch $(STAGING_DIR)/$(PROJECT)-$(VERSION)/data/backups/.gitkeep
	@cd $(STAGING_DIR) && $(TAR) -czf ../$(PROJECT)-$(VERSION).tar.gz $(PROJECT)-$(VERSION)
	@cd $(DIST_DIR) && $(SHA256) $(PROJECT)-$(VERSION).tar.gz > SHA256SUMS.txt 2>/dev/null || true
	@rm -rf $(STAGING_DIR)
	@echo "==> Package: $(DIST_DIR)/$(PROJECT)-$(VERSION).tar.gz"
	@echo "==> Checksum: $(DIST_DIR)/SHA256SUMS.txt"

# ==============================================================================
# Full Distribution — includes tests, CI, templates, tasks
# ==============================================================================
dist-full: clean
	@echo "==> Building full distribution package v$(VERSION)..."
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)-full
	@cp -r lib conf docs tests .github tasks \
		apotropaios.sh Makefile .shellcheckrc .gitignore \
		$(COMMUNITY_FILES) \
		$(STAGING_DIR)/$(PROJECT)-$(VERSION)-full/ 2>/dev/null || true
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)-full/data/logs
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)-full/data/rules
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)-full/data/backups
	@touch $(STAGING_DIR)/$(PROJECT)-$(VERSION)-full/data/logs/.gitkeep
	@touch $(STAGING_DIR)/$(PROJECT)-$(VERSION)-full/data/rules/.gitkeep
	@touch $(STAGING_DIR)/$(PROJECT)-$(VERSION)-full/data/backups/.gitkeep
	@cd $(STAGING_DIR) && $(TAR) -czf ../$(PROJECT)-$(VERSION)-full.tar.gz $(PROJECT)-$(VERSION)-full
	@cd $(DIST_DIR) && $(SHA256) $(PROJECT)-$(VERSION)-full.tar.gz >> SHA256SUMS.txt 2>/dev/null || true
	@rm -rf $(STAGING_DIR)
	@echo "==> Package: $(DIST_DIR)/$(PROJECT)-$(VERSION)-full.tar.gz"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                         INSTALLATION / REMOVAL                            ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ==============================================================================
# Install — system-wide installation to INSTALL_DIR
# ==============================================================================
install:
	@echo "==> Installing Apotropaios v$(VERSION) to $(INSTALL_DIR)..."
	@if [ "$$(id -u)" -ne 0 ]; then echo "Error: install requires root (use sudo)"; exit 1; fi
	@mkdir -p $(INSTALL_DIR)
	@cp -r lib conf apotropaios.sh $(INSTALL_DIR)/
	@cp -r docs $(INSTALL_DIR)/ 2>/dev/null || true
	@mkdir -p $(INSTALL_DIR)/data/logs $(INSTALL_DIR)/data/rules $(INSTALL_DIR)/data/backups
	@chmod 700 $(INSTALL_DIR)/data $(INSTALL_DIR)/data/logs $(INSTALL_DIR)/data/rules $(INSTALL_DIR)/data/backups
	@chmod 755 $(INSTALL_DIR)/apotropaios.sh
	@ln -sf $(INSTALL_DIR)/apotropaios.sh $(BIN_LINK) 2>/dev/null || true
	@mkdir -p $(CONF_DIR) 2>/dev/null || true
	@if [ ! -f $(CONF_DIR)/apotropaios.conf ]; then \
		cp conf/apotropaios.conf $(CONF_DIR)/ 2>/dev/null || true; \
		echo "  Config installed: $(CONF_DIR)/apotropaios.conf"; \
	else \
		echo "  Config exists — not overwritten: $(CONF_DIR)/apotropaios.conf"; \
	fi
	@echo "==> Installed to $(INSTALL_DIR)"
	@echo "==> Symlink: $(BIN_LINK) → $(INSTALL_DIR)/apotropaios.sh"
	@echo "==> Run: sudo apotropaios"

# ==============================================================================
# Uninstall — remove system-wide installation
# ==============================================================================
uninstall:
	@echo "==> Uninstalling Apotropaios from $(INSTALL_DIR)..."
	@if [ "$$(id -u)" -ne 0 ]; then echo "Error: uninstall requires root (use sudo)"; exit 1; fi
	@rm -f $(BIN_LINK) 2>/dev/null || true
	@if [ -d "$(INSTALL_DIR)" ]; then \
		echo "  Removing $(INSTALL_DIR)..."; \
		echo "  NOTE: data/ directory preserved for safety."; \
		rm -rf $(INSTALL_DIR)/lib $(INSTALL_DIR)/conf $(INSTALL_DIR)/docs $(INSTALL_DIR)/apotropaios.sh 2>/dev/null || true; \
		if [ -d "$(INSTALL_DIR)/data" ]; then \
			echo "  Data directory left at $(INSTALL_DIR)/data — remove manually if desired"; \
		fi; \
	else \
		echo "  $(INSTALL_DIR) not found — nothing to remove"; \
	fi
	@echo "==> Uninstall complete"
	@echo "  Config preserved at $(CONF_DIR)/apotropaios.conf — remove manually if desired"

# ==============================================================================
# Post-install Verification
# ==============================================================================
verify:
	@echo "==> Verifying installation..."
	@command -v apotropaios >/dev/null 2>&1 || { echo "  ✗ apotropaios not on PATH"; exit 1; }
	@installed_version=$$(apotropaios --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'); \
	echo "  ✓ Binary found on PATH"; \
	echo "  ✓ Version: $$installed_version"; \
	if [ "$$installed_version" != "$(VERSION)" ]; then \
		echo "  ⚠ Version mismatch: installed=$$installed_version expected=$(VERSION)"; \
	fi
	@echo "==> Verification passed"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                        DEVELOPMENT UTILITIES                              ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ==============================================================================
# Development Setup — install all development dependencies
# ==============================================================================
dev-setup:
	@echo "==> Setting up development environment..."
	@echo "  [1/2] Installing BATS test framework..."
	@if command -v $(BATS) >/dev/null 2>&1; then \
		echo "    BATS already installed: $$($(BATS) --version)"; \
	else \
		if [ -d /tmp/bats-core ]; then rm -rf /tmp/bats-core; fi; \
		git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats-core && \
		cd /tmp/bats-core && sudo ./install.sh /usr/local && \
		rm -rf /tmp/bats-core && \
		echo "    BATS installed: $$($(BATS) --version)"; \
	fi
	@echo "  [2/2] Checking ShellCheck..."
	@if command -v $(SHELLCHECK) >/dev/null 2>&1; then \
		echo "    ShellCheck already installed: $$($(SHELLCHECK) --version | head -2 | tail -1)"; \
	else \
		echo "    ShellCheck not found — install manually:"; \
		echo "      Debian/Ubuntu/Kali: sudo apt-get install shellcheck"; \
		echo "      RHEL/Rocky/Alma:    sudo dnf install ShellCheck"; \
		echo "      Arch:               sudo pacman -S shellcheck"; \
	fi
	@echo "==> Development setup complete"
	@echo "==> Run 'make test' to verify"

# ==============================================================================
# Dependency Check — verify all required tools are available
# ==============================================================================
check-deps:
	@echo "==> Checking dependencies..."
	@all_ok=1; \
	echo "  Required:"; \
	for cmd in bash grep sed awk find sort tar stat date mkdir chmod; do \
		if command -v $$cmd >/dev/null 2>&1; then \
			printf "    ✓ %-12s %s\n" "$$cmd" "$$(command -v $$cmd)"; \
		else \
			printf "    ✗ %-12s MISSING\n" "$$cmd"; \
			all_ok=0; \
		fi; \
	done; \
	echo "  Development:"; \
	for cmd in $(BATS) $(SHELLCHECK) git; do \
		if command -v $$cmd >/dev/null 2>&1; then \
			printf "    ✓ %-12s %s\n" "$$cmd" "$$(command -v $$cmd)"; \
		else \
			printf "    ○ %-12s not installed (optional for development)\n" "$$cmd"; \
		fi; \
	done; \
	echo "  Runtime:"; \
	for cmd in iptables nft firewall-cmd ufw ipset; do \
		if command -v $$cmd >/dev/null 2>&1; then \
			ver=$$($$cmd --version 2>/dev/null | head -1 || echo "unknown"); \
			printf "    ✓ %-12s %s\n" "$$cmd" "$$ver"; \
		else \
			printf "    ○ %-12s not installed\n" "$$cmd"; \
		fi; \
	done; \
	if [ "$$all_ok" -eq 0 ]; then \
		echo ""; echo "  ✗ Missing required dependencies"; exit 1; \
	fi
	@echo "==> All required dependencies available"

# ==============================================================================
# Project Info — version, file counts, quick summary
# ==============================================================================
info:
	@echo ""
	@echo "  Apotropaios — Firewall Manager"
	@echo "  ════════════════════════════════"
	@echo "  Version:       v$(VERSION)"
	@echo "  Shell modules: $(SHELL_COUNT)"
	@echo "  Test files:    $(BATS_COUNT)"
	@echo "  Install dir:   $(INSTALL_DIR)"
	@echo "  Config dir:    $(CONF_DIR)"
	@echo ""

# ==============================================================================
# Metrics — detailed project statistics
# ==============================================================================
metrics:
	@echo ""
	@echo "  Apotropaios v$(VERSION) — Project Metrics"
	@echo "  ══════════════════════════════════════════"
	@echo ""
	@echo "  Source Code:"
	@printf "    Shell modules:    %d\n" $(SHELL_COUNT)
	@printf "    Code lines:       %d\n" $$(cat $(SHELL_FILES) 2>/dev/null | wc -l)
	@printf "    Code lines (net): %d\n" $$(cat $(SHELL_FILES) 2>/dev/null | grep -v '^\s*#' | grep -v '^\s*$$' | wc -l)
	@echo ""
	@echo "  Testing:"
	@printf "    Test files:       %d\n" $(BATS_COUNT)
	@printf "    Test lines:       %d\n" $$(cat $(BATS_FILES) 2>/dev/null | wc -l)
	@if command -v $(BATS) >/dev/null 2>&1; then \
		total=0; \
		for f in $(BATS_FILES); do \
			c=$$($(BATS) --count "$$f" 2>/dev/null || echo 0); \
			total=$$(( total + c )); \
		done; \
		printf "    Test count:       %d\n" "$$total"; \
	fi
	@echo ""
	@echo "  Documentation:"
	@printf "    Wiki pages:       %d\n" $$(find docs/wiki -name '*.md' 2>/dev/null | wc -l)
	@printf "    Doc files:        %d\n" $$(find docs -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
	@printf "    Community files:  %d\n" $$(ls $(COMMUNITY_FILES) 2>/dev/null | wc -l)
	@echo ""
	@echo "  Infrastructure:"
	@printf "    CI workflows:     %d\n" $$(find .github/workflows -name '*.yml' 2>/dev/null | wc -l)
	@printf "    Issue templates:  %d\n" $$(find .github/ISSUE_TEMPLATE -name '*.yml' -not -name 'config.yml' 2>/dev/null | wc -l)
	@printf "    Makefile targets: %d\n" $$(grep -c '^[a-z].*:' Makefile 2>/dev/null)
	@echo ""

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                              CLEANUP                                      ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ==============================================================================
# Clean — remove build artifacts and runtime data
# ==============================================================================
clean:
	@rm -rf $(DIST_DIR) $(TEST_RESULTS)
	@rm -f data/logs/*.log data/rules/*.dat data/rules/*.tmp.*
	@rm -f data/backups/*.tar.gz data/backups/*.sha256
	@echo "==> Cleaned"

# ==============================================================================
# Deep Clean — clean + remove all generated state (use with caution)
# ==============================================================================
clean-all: clean
	@rm -rf data/logs/* data/rules/* data/backups/*
	@touch data/logs/.gitkeep data/rules/.gitkeep data/backups/.gitkeep 2>/dev/null || true
	@echo "==> Deep cleaned (all data removed)"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                                 HELP                                      ║
# ╚════════════════════════════════════════════════════════════════════════════╝

help:
	@echo ""
	@echo "  Apotropaios v$(VERSION) — Makefile Targets"
	@echo "  ═══════════════════════════════════════════"
	@echo ""
	@echo "  Quality:"
	@echo "    make lint                Run syntax check + ShellCheck"
	@echo "    make syntax-check        Bash syntax check only (fastest)"
	@echo ""
	@echo "  Testing:"
	@echo "    make test                Full suite: lint + unit + integration + security"
	@echo "    make test-quick          Unit tests only (fast development feedback)"
	@echo "    make test-unit           All unit tests"
	@echo "    make test-integration    All integration tests"
	@echo "    make test-sec            All security tests"
	@echo "    make test-report         Detailed per-file report with pass/fail counts"
	@echo "    make test-count          Quick test count (no execution)"
	@echo "    make test-list           List all test names"
	@echo ""
	@echo "  Individual Test Suites:"
	@echo "    make test-validation     Input validation (88 tests)"
	@echo "    make test-logging        Logging and utilities (28 tests)"
	@echo "    make test-os-detect      OS detection (20 tests)"
	@echo "    make test-fw-detect      Firewall detection (18 tests)"
	@echo "    make test-security       Security module (23 tests)"
	@echo "    make test-errors         Error handling (24 tests)"
	@echo "    make test-rule-engine    Rule engine (19 tests)"
	@echo "    make test-backup         Backup module (14 tests)"
	@echo "    make test-lifecycle      Integration lifecycle (22 tests)"
	@echo "    make test-import-export  Import/export round-trip (10 tests)"
	@echo "    make test-cli            CLI arguments and commands (29 tests)"
	@echo "    make test-help-system    Progressive help system (32 tests)"
	@echo "    make test-sec-injection  CWE injection prevention (48 tests)"
	@echo ""
	@echo "  Security:"
	@echo "    make security-scan       Static pattern analysis (6 checks)"
	@echo ""
	@echo "  Packaging:"
	@echo "    make dist                Build runtime distribution tarball"
	@echo "    make dist-full           Build full distribution (includes tests, CI, tasks)"
	@echo ""
	@echo "  Installation:"
	@echo "    make install             Install to $(INSTALL_DIR) (requires root)"
	@echo "    make uninstall           Remove installation (preserves data)"
	@echo "    make verify              Verify installation"
	@echo ""
	@echo "  Development:"
	@echo "    make dev-setup           Install BATS + check ShellCheck"
	@echo "    make check-deps          Check all required and optional dependencies"
	@echo "    make info                Quick project summary"
	@echo "    make metrics             Detailed project statistics"
	@echo ""
	@echo "  Cleanup:"
	@echo "    make clean               Remove build artifacts and test results"
	@echo "    make clean-all           Deep clean: remove all generated state"
	@echo ""
