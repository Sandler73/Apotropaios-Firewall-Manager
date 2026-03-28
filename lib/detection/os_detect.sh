#!/usr/bin/env bash
# ==============================================================================
# File:         lib/detection/os_detect.sh
# Project:      Apotropaios - Firewall Manager
# Synopsis:     Secure operating system detection and identification
# Description:  Detects the running operating system by parsing /etc/os-release
#               and other system identification files. Validates against the
#               supported OS list. Determines package manager and OS family.
#               Uses multiple fallback detection methods for robustness.
# Notes:        - Requires lib/core/constants.sh, logging.sh, validation.sh
#               - Detection results stored in global variables (Bash Lesson #9)
#               - All file reads validate content before use
#               - Supports: Ubuntu, Kali, Debian 12, Rocky 9, AlmaLinux 9, Arch
# Version:      1.1.5
# ==============================================================================

# Prevent double-sourcing
[[ -n "${_APOTROPAIOS_OS_DETECT_LOADED:-}" ]] && return 0
readonly _APOTROPAIOS_OS_DETECT_LOADED=1

# ==============================================================================
# Detection Result Variables (Global — Bash Lesson #9)
# ==============================================================================
OS_DETECTED_ID=""          # e.g., "ubuntu", "rocky", "arch"
OS_DETECTED_NAME=""        # e.g., "Ubuntu", "Rocky Linux 9"
OS_DETECTED_VERSION=""     # e.g., "22.04", "9.3"
OS_DETECTED_VERSION_ID=""  # e.g., "22.04", "9"
OS_DETECTED_FAMILY=""      # "debian", "rhel", "arch"
OS_DETECTED_PKG_MANAGER="" # "apt", "dnf", "pacman"
OS_DETECTED_SUPPORTED=0    # 1 if supported, 0 if not

# ==============================================================================
# os_detect()
# Description:  Perform operating system detection using multiple methods.
#               Results stored in OS_DETECTED_* global variables.
# Returns:      0 if OS detected and supported
#               E_OS_UNSUPPORTED if OS detected but not supported
#               E_GENERAL if OS cannot be detected
# ==============================================================================
os_detect() {
    log_info "os_detect" "Beginning operating system detection"

    # Method 1: /etc/os-release (preferred — standard across modern Linux)
    if _os_detect_os_release; then
        log_info "os_detect" "OS detected via /etc/os-release: ${OS_DETECTED_NAME} (${OS_DETECTED_ID})"
    # Method 2: /etc/lsb-release (Ubuntu/Debian fallback)
    elif _os_detect_lsb_release; then
        log_info "os_detect" "OS detected via /etc/lsb-release: ${OS_DETECTED_NAME} (${OS_DETECTED_ID})"
    # Method 3: /etc/redhat-release (RHEL family fallback)
    elif _os_detect_redhat_release; then
        log_info "os_detect" "OS detected via /etc/redhat-release: ${OS_DETECTED_NAME} (${OS_DETECTED_ID})"
    # Method 4: uname fallback (minimal information)
    elif _os_detect_uname; then
        log_info "os_detect" "OS detected via uname: ${OS_DETECTED_NAME} (${OS_DETECTED_ID})"
    else
        log_error "os_detect" "Unable to detect operating system"
        return "${E_GENERAL}"
    fi

    # Determine OS family and package manager
    _os_determine_family

    # Check if detected OS is in supported list
    _os_check_supported

    # Log detection results
    log_info "os_detect" "Detection complete" \
        "id=${OS_DETECTED_ID} version=${OS_DETECTED_VERSION} family=${OS_DETECTED_FAMILY} pkg=${OS_DETECTED_PKG_MANAGER} supported=${OS_DETECTED_SUPPORTED}"

    if [[ "${OS_DETECTED_SUPPORTED}" -eq 0 ]]; then
        log_warning "os_detect" "Operating system '${OS_DETECTED_NAME}' is not in the supported list"
        return "${E_OS_UNSUPPORTED}"
    fi

    return "${E_SUCCESS}"
}

# ==============================================================================
# _os_detect_os_release() [INTERNAL]
# Description:  Parse /etc/os-release for OS identification.
# Returns:      0 if successfully parsed, 1 if file missing/unreadable
# ==============================================================================
_os_detect_os_release() {
    local release_file="/etc/os-release"

    [[ ! -f "${release_file}" ]] && return 1
    [[ ! -r "${release_file}" ]] && return 1

    # Validate file size (reject abnormally large files — security)
    local file_size
    file_size="$(stat -c%s "${release_file}" 2>/dev/null)" || file_size="$(wc -c < "${release_file}" 2>/dev/null)" || return 1
    [[ "${file_size}" -gt 4096 ]] && {
        log_warning "os_detect" "/etc/os-release exceeds expected size (${file_size} bytes)"
        return 1
    }

    # Parse known fields safely (no eval of arbitrary content)
    local id="" name="" version="" version_id="" id_like=""
    local line key value

    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Skip comments and empty lines
        [[ -z "${line}" ]] && continue
        [[ "${line}" == "#"* ]] && continue

        # Extract key=value (handle quoted values)
        key="${line%%=*}"
        value="${line#*=}"
        # Remove surrounding quotes
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"

        case "${key}" in
            ID)         id="$(util_to_lower "${value}")" ;;
            NAME)       name="${value}" ;;
            VERSION)    version="${value}" ;;
            VERSION_ID) version_id="${value}" ;;
            ID_LIKE)    id_like="$(util_to_lower "${value}")" ;;
        esac
    done < "${release_file}"

    [[ -z "${id}" ]] && return 1

    # Normalize known OS IDs
    case "${id}" in
        ubuntu)        OS_DETECTED_ID="ubuntu" ;;
        kali)          OS_DETECTED_ID="kali" ;;
        debian)        OS_DETECTED_ID="debian" ;;
        rocky)         OS_DETECTED_ID="rocky" ;;
        almalinux)     OS_DETECTED_ID="almalinux" ;;
        arch|archlinux) OS_DETECTED_ID="arch" ;;
        *)
            # Check ID_LIKE for derivative distributions
            if [[ "${id_like}" == *"debian"* ]] || [[ "${id_like}" == *"ubuntu"* ]]; then
                OS_DETECTED_ID="${id}"
                OS_DETECTED_FAMILY="debian"
            elif [[ "${id_like}" == *"rhel"* ]] || [[ "${id_like}" == *"centos"* ]] || [[ "${id_like}" == *"fedora"* ]]; then
                OS_DETECTED_ID="${id}"
                OS_DETECTED_FAMILY="rhel"
            else
                OS_DETECTED_ID="${id}"
            fi
            ;;
    esac

    OS_DETECTED_NAME="${name:-${id}}"
    OS_DETECTED_VERSION="${version:-unknown}"
    OS_DETECTED_VERSION_ID="${version_id:-unknown}"

    return 0
}

# ==============================================================================
# _os_detect_lsb_release() [INTERNAL]
# Description:  Parse /etc/lsb-release for OS identification (Ubuntu/Debian).
# Returns:      0 if successfully parsed, 1 if not available
# ==============================================================================
_os_detect_lsb_release() {
    local release_file="/etc/lsb-release"

    [[ ! -f "${release_file}" ]] && return 1
    [[ ! -r "${release_file}" ]] && return 1

    local distrib_id="" distrib_release="" distrib_desc=""
    local line key value

    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -z "${line}" ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        value="${value#\"}"
        value="${value%\"}"

        case "${key}" in
            DISTRIB_ID)          distrib_id="$(util_to_lower "${value}")" ;;
            DISTRIB_RELEASE)     distrib_release="${value}" ;;
            DISTRIB_DESCRIPTION) distrib_desc="${value}" ;;
        esac
    done < "${release_file}"

    [[ -z "${distrib_id}" ]] && return 1

    OS_DETECTED_ID="${distrib_id}"
    OS_DETECTED_NAME="${distrib_desc:-${distrib_id}}"
    OS_DETECTED_VERSION="${distrib_release:-unknown}"
    OS_DETECTED_VERSION_ID="${distrib_release:-unknown}"

    return 0
}

# ==============================================================================
# _os_detect_redhat_release() [INTERNAL]
# Description:  Parse /etc/redhat-release for OS identification (RHEL family).
# Returns:      0 if successfully parsed, 1 if not available
# ==============================================================================
_os_detect_redhat_release() {
    local release_file="/etc/redhat-release"

    [[ ! -f "${release_file}" ]] && return 1
    [[ ! -r "${release_file}" ]] && return 1

    local content
    content="$(head -1 "${release_file}" 2>/dev/null)" || return 1
    [[ -z "${content}" ]] && return 1

    local lower_content
    lower_content="$(util_to_lower "${content}")"

    if [[ "${lower_content}" == *"rocky"* ]]; then
        OS_DETECTED_ID="rocky"
    elif [[ "${lower_content}" == *"alma"* ]]; then
        OS_DETECTED_ID="almalinux"
    elif [[ "${lower_content}" == *"centos"* ]]; then
        OS_DETECTED_ID="centos"
    elif [[ "${lower_content}" == *"red hat"* ]]; then
        OS_DETECTED_ID="rhel"
    else
        OS_DETECTED_ID="rhel_unknown"
    fi

    OS_DETECTED_NAME="${content}"

    # Extract version number
    local version
    version="$(printf '%s' "${content}" | grep -oE '[0-9]+\.[0-9]+' | head -1)" || true
    OS_DETECTED_VERSION="${version:-unknown}"
    OS_DETECTED_VERSION_ID="${version%%.*}"

    return 0
}

# ==============================================================================
# _os_detect_uname() [INTERNAL]
# Description:  Fallback detection using uname command.
# Returns:      0 if basic detection succeeds, 1 if uname unavailable
# ==============================================================================
_os_detect_uname() {
    local kernel
    kernel="$(uname -s 2>/dev/null)" || return 1

    if [[ "${kernel}" != "Linux" ]]; then
        log_warning "os_detect" "Non-Linux kernel detected: ${kernel}"
        OS_DETECTED_ID="unknown"
        OS_DETECTED_NAME="${kernel}"
        OS_DETECTED_VERSION="$(uname -r 2>/dev/null || echo unknown)"
        OS_DETECTED_VERSION_ID="unknown"
        return 0
    fi

    OS_DETECTED_ID="linux_unknown"
    OS_DETECTED_NAME="Linux (unknown distribution)"
    OS_DETECTED_VERSION="$(uname -r 2>/dev/null || echo unknown)"
    OS_DETECTED_VERSION_ID="unknown"

    return 0
}

# ==============================================================================
# _os_determine_family() [INTERNAL]
# Description:  Determine OS family and package manager from detected OS ID.
# ==============================================================================
_os_determine_family() {
    # Skip if family already set by detection
    if [[ -n "${OS_DETECTED_FAMILY}" ]] && [[ -n "${OS_DETECTED_PKG_MANAGER}" ]]; then
        return
    fi

    case "${OS_DETECTED_ID}" in
        ubuntu|kali|debian)
            OS_DETECTED_FAMILY="debian"
            OS_DETECTED_PKG_MANAGER="apt"
            ;;
        rocky|almalinux|centos|rhel|rhel_unknown)
            OS_DETECTED_FAMILY="rhel"
            OS_DETECTED_PKG_MANAGER="dnf"
            ;;
        arch|archlinux)
            OS_DETECTED_FAMILY="arch"
            OS_DETECTED_PKG_MANAGER="pacman"
            ;;
        *)
            # Attempt detection by checking available package managers
            if util_is_command_available apt-get; then
                OS_DETECTED_FAMILY="debian"
                OS_DETECTED_PKG_MANAGER="apt"
            elif util_is_command_available dnf; then
                OS_DETECTED_FAMILY="rhel"
                OS_DETECTED_PKG_MANAGER="dnf"
            elif util_is_command_available pacman; then
                OS_DETECTED_FAMILY="arch"
                OS_DETECTED_PKG_MANAGER="pacman"
            else
                OS_DETECTED_FAMILY="unknown"
                OS_DETECTED_PKG_MANAGER="unknown"
            fi
            ;;
    esac
}

# ==============================================================================
# _os_check_supported() [INTERNAL]
# Description:  Check if the detected OS is in the supported list.
# ==============================================================================
_os_check_supported() {
    OS_DETECTED_SUPPORTED=0

    local supported_os
    for supported_os in "${SUPPORTED_OS_LIST[@]}"; do
        if [[ "${OS_DETECTED_ID}" == "${supported_os}" ]]; then
            OS_DETECTED_SUPPORTED=1
            return
        fi
    done
}

# ==============================================================================
# os_get_info()
# Description:  Print detected OS information.
# ==============================================================================
os_get_info() {
    util_print_kv "OS ID" "${OS_DETECTED_ID}"
    util_print_kv "OS Name" "${OS_DETECTED_NAME}"
    util_print_kv "OS Version" "${OS_DETECTED_VERSION}"
    util_print_kv "OS Family" "${OS_DETECTED_FAMILY}"
    util_print_kv "Package Manager" "${OS_DETECTED_PKG_MANAGER}"
    util_print_kv "Supported" "$( [[ "${OS_DETECTED_SUPPORTED}" -eq 1 ]] && echo 'Yes' || echo 'No' )"
}
