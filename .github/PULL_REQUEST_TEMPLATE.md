## Pull Request

### Description
<!-- Provide a clear, concise description of what this PR does -->


### Type of Change
<!-- Check all that apply -->
- [ ] 🐛 Bug fix (non-breaking change that fixes an issue)
- [ ] ✨ New feature (non-breaking change that adds functionality)
- [ ] 🔧 Enhancement (improvement to existing functionality)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] 📝 Documentation update
- [ ] 🧪 Test addition or improvement
- [ ] 🔒 Security fix or hardening
- [ ] 🏗️ CI/CD pipeline change
- [ ] ♻️ Code refactoring (no functional changes)
- [ ] 🧹 Chore (dependency updates, cleanup)

### Related Issues
<!-- Link related issues: "Fixes #123" or "Relates to #456" -->
Fixes #

### Changes Made
<!-- Describe the specific changes in this PR -->
1.
2.
3.

### Security Considerations
<!-- Required for all code changes. If N/A, explain why. -->
- [ ] All user input is validated through `validate_*` functions before use
- [ ] No raw input is interpolated into commands or file paths
- [ ] File operations use secure permissions (600/700)
- [ ] Sensitive data is never written to logs (masked automatically)
- [ ] Error messages do not leak internal paths or system details
- [ ] Temporary files are cleaned up in all exit paths
- [ ] No new shell metacharacter injection vectors introduced
- [ ] N/A — This change does not touch code paths that handle user input

### Testing
<!-- Describe how you tested these changes -->

#### Test Results
- [ ] `make syntax-check` passes (all `.sh` files)
- [ ] `make lint` passes (ShellCheck zero warnings)
- [ ] `make test-unit` passes (all unit tests)
- [ ] `make test-integration` passes (all integration tests)
- [ ] New tests added for new functionality
- [ ] Existing tests updated for changed behavior

#### Tested Platforms
<!-- Check all platforms you tested on -->
- [ ] Ubuntu 22.04
- [ ] Ubuntu 24.04
- [ ] Kali Linux (rolling)
- [ ] Debian 12
- [ ] Rocky Linux 9
- [ ] AlmaLinux 9
- [ ] Arch Linux

#### Test Commands Run
```bash
# Paste the specific test commands and their output
make test
```

### Documentation
- [ ] `docs/changelog.md` updated with changes
- [ ] `docs/wiki/Changelog.md` updated (if applicable)
- [ ] Help text updated (`--help` or per-command help)
- [ ] README updated (if user-facing changes)
- [ ] `tasks/sync_function.md` updated (if dependencies changed)
- [ ] Wiki pages updated (if applicable)
- [ ] N/A — No documentation changes needed

### Code Quality
- [ ] Code follows existing naming conventions (`fw_`, `rule_`, `validate_`, etc.)
- [ ] Functions have documentation headers (Synopsis, Description, Parameters, Returns)
- [ ] No hardcoded values — uses constants from `constants.sh`
- [ ] Arithmetic expressions use `|| true` under `set -e`
- [ ] All variables are quoted (`"${var}"`)
- [ ] Source guards present on new modules (`[[ -n "${_LOADED}" ]] && return 0`)

### Backward Compatibility
<!-- Describe any backward compatibility implications -->
- [ ] This change is fully backward compatible
- [ ] This change requires migration steps (described below)
- [ ] This change modifies configuration file format

### Screenshots / Terminal Output
<!-- If applicable, add screenshots or terminal output showing the change -->


### Reviewer Notes
<!-- Any specific areas you'd like reviewers to focus on -->


### Pre-Merge Checklist
<!-- Final checks before merging -->
- [ ] PR title follows format: `type(scope): description` (e.g., `fix(validation): handle compound actions`)
- [ ] Branch is up to date with target branch
- [ ] All CI checks pass
- [ ] At least one approval received
- [ ] No merge conflicts
