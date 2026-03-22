# ==============================================================================
# Makefile for Apotropaios - Firewall Manager
# Description: Build, test, lint, install, and package targets.
#              CI should call make targets, not duplicate their logic.
#              (CI/CD Lesson #12: Makefile as CI Entry Point)
# ==============================================================================

SHELL := /bin/bash
.PHONY: all test test-unit test-integration lint clean dist install verify help

# Project metadata
PROJECT     := apotropaios
VERSION     := $(shell grep -m1 'APOTROPAIOS_VERSION=' lib/core/constants.sh 2>/dev/null | cut -d'"' -f2 || echo "0.0.0")
DIST_DIR    := dist
STAGING_DIR := $(DIST_DIR)/staging
INSTALL_DIR := /opt/apotropaios

# BATS test settings
BATS        := bats
TEST_DIR    := tests
TEST_UNIT   := $(TEST_DIR)/unit
TEST_INT    := $(TEST_DIR)/integration
TEST_RESULTS := test-results

# Source files
SHELL_FILES := $(shell find . -name '*.sh' -not -path './dist/*' -not -path './.git/*' 2>/dev/null)
BATS_FILES  := $(shell find $(TEST_DIR) -name '*.bats' 2>/dev/null)

# ==============================================================================
# Default target
# ==============================================================================
all: lint test

# ==============================================================================
# Linting
# ==============================================================================
lint:
	@echo "==> Running ShellCheck on $(words $(SHELL_FILES)) files..."
	@shellcheck_failed=0; \
	for f in $(SHELL_FILES); do \
		if ! shellcheck -x "$$f" 2>/dev/null; then \
			shellcheck_failed=1; \
		fi; \
	done; \
	if [ "$$shellcheck_failed" -eq 1 ]; then \
		echo "ShellCheck found issues"; \
		exit 1; \
	fi
	@echo "==> ShellCheck passed"

# ==============================================================================
# Testing
# ==============================================================================
test: lint test-unit test-integration
	@echo "==> All tests passed"

test-unit:
	@echo "==> Running unit tests..."
	@mkdir -p $(TEST_RESULTS)
	@if command -v $(BATS) >/dev/null 2>&1; then \
		$(BATS) $(TEST_UNIT) --tap > $(TEST_RESULTS)/unit.tap 2>&1 || { \
			echo "Unit tests failed:"; \
			cat $(TEST_RESULTS)/unit.tap; \
			exit 1; \
		}; \
		cat $(TEST_RESULTS)/unit.tap; \
	else \
		echo "BATS not installed — skipping unit tests"; \
		echo "Install: git clone https://github.com/bats-core/bats-core.git && cd bats-core && sudo ./install.sh /usr/local"; \
	fi

test-integration:
	@echo "==> Running integration tests..."
	@mkdir -p $(TEST_RESULTS)
	@if command -v $(BATS) >/dev/null 2>&1; then \
		$(BATS) $(TEST_INT) --tap > $(TEST_RESULTS)/integration.tap 2>&1 || { \
			echo "Integration tests failed:"; \
			cat $(TEST_RESULTS)/integration.tap; \
			exit 1; \
		}; \
		cat $(TEST_RESULTS)/integration.tap; \
	else \
		echo "BATS not installed — skipping integration tests"; \
	fi

# ==============================================================================
# Distribution packaging (CI/CD Lesson #13: Single Source of Truth)
# ==============================================================================
dist: clean
	@echo "==> Building distribution package v$(VERSION)..."
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)
	@cp -r lib conf docs apotropaios.sh Makefile .shellcheckrc README.md LICENSE \
		$(STAGING_DIR)/$(PROJECT)-$(VERSION)/ 2>/dev/null || true
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)/data/logs
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)/data/rules
	@mkdir -p $(STAGING_DIR)/$(PROJECT)-$(VERSION)/data/backups
	@cd $(STAGING_DIR) && tar -czf ../$(PROJECT)-$(VERSION).tar.gz $(PROJECT)-$(VERSION)
	@cd $(DIST_DIR) && sha256sum $(PROJECT)-$(VERSION).tar.gz > SHA256SUMS.txt 2>/dev/null || true
	@rm -rf $(STAGING_DIR)
	@echo "==> Package: $(DIST_DIR)/$(PROJECT)-$(VERSION).tar.gz"

# ==============================================================================
# Installation
# ==============================================================================
install:
	@echo "==> Installing Apotropaios to $(INSTALL_DIR)..."
	@if [ "$$(id -u)" -ne 0 ]; then echo "Error: install requires root"; exit 1; fi
	@mkdir -p $(INSTALL_DIR)
	@cp -r lib conf apotropaios.sh $(INSTALL_DIR)/
	@mkdir -p $(INSTALL_DIR)/data/logs $(INSTALL_DIR)/data/rules $(INSTALL_DIR)/data/backups
	@chmod 700 $(INSTALL_DIR)/data $(INSTALL_DIR)/data/logs $(INSTALL_DIR)/data/rules $(INSTALL_DIR)/data/backups
	@chmod 755 $(INSTALL_DIR)/apotropaios.sh
	@ln -sf $(INSTALL_DIR)/apotropaios.sh /usr/local/bin/apotropaios 2>/dev/null || true
	@echo "==> Installed. Run: sudo apotropaios"

# ==============================================================================
# Post-install verification (CI/CD Lesson #21)
# ==============================================================================
verify:
	@echo "==> Verifying installation..."
	@command -v apotropaios >/dev/null 2>&1 || { echo "Not on PATH"; exit 1; }
	@apotropaios --version || { echo "Version check failed"; exit 1; }
	@echo "==> Verification passed"

# ==============================================================================
# Cleanup
# ==============================================================================
clean:
	@rm -rf $(DIST_DIR) $(TEST_RESULTS)
	@echo "==> Cleaned"

# ==============================================================================
# Help
# ==============================================================================
help:
	@echo "Apotropaios Makefile Targets:"
	@echo "  make all             - Lint and test (default)"
	@echo "  make lint            - Run ShellCheck"
	@echo "  make test            - Run all tests"
	@echo "  make test-unit       - Run unit tests only"
	@echo "  make test-integration - Run integration tests only"
	@echo "  make dist            - Build distribution package"
	@echo "  make install         - Install to $(INSTALL_DIR)"
	@echo "  make verify          - Verify installation"
	@echo "  make clean           - Remove build artifacts"
