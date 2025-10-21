#!/bin/bash
# SPDX-FileCopyrightText: 2025 GSI Helmholtzzentrum für Schwerionenforschung GmbH
# SPDX-License-Identifier: GPL-3.0-or-later

# FAIR RPM Build Library
# Provides functions for building FAIR software RPM packages using mock

#==============================================================================
# Logging Framework
#==============================================================================

# Log levels
declare -A FAIR_LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

# Current log level (default: INFO)
: ${FAIR_LOG_LEVEL:=INFO}

# Log output file (default: stderr only)
: ${FAIR_LOG_FILE:=}

# ANSI color codes
declare -A FAIR_LOG_COLORS=(
    [DEBUG]='\033[0;36m'    # Cyan
    [INFO]='\033[0;32m'     # Green
    [WARN]='\033[0;33m'     # Yellow
    [ERROR]='\033[0;31m'    # Red
    [RESET]='\033[0m'       # Reset
)

# Enable/disable colored output (auto-detect if terminal supports color)
: ${FAIR_LOG_COLOR:=auto}

# Internal: Check if colors should be used
_fair_use_colors() {
    if [[ "${FAIR_LOG_COLOR}" == "always" ]]; then
        return 0
    elif [[ "${FAIR_LOG_COLOR}" == "never" ]]; then
        return 1
    else
        # auto: check if output is a terminal
        [[ -t 2 ]]
    fi
}

# Logging function
# Input: $1=level (DEBUG|INFO|WARN|ERROR), $@=message
# Output: Formatted log message to stderr or FAIR_LOG_FILE
fair_log() {
    local level="$1"
    shift

    # Validate log level
    if [[ -z "${FAIR_LOG_LEVELS[$level]}" ]]; then
        level="INFO"
    fi

    # Check if message should be logged based on current log level
    if [[ ${FAIR_LOG_LEVELS[$level]} -lt ${FAIR_LOG_LEVELS[$FAIR_LOG_LEVEL]} ]]; then
        return 0
    fi

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="$*"

    # Build log line
    local log_line="[${timestamp}] [${level}] ${message}"

    # Add colors if enabled and outputting to terminal
    if _fair_use_colors; then
        local color="${FAIR_LOG_COLORS[$level]}"
        local reset="${FAIR_LOG_COLORS[RESET]}"
        log_line="${color}[${timestamp}] [${level}]${reset} ${message}"
    fi

    # Output to file or stderr
    if [[ -n "${FAIR_LOG_FILE}" ]]; then
        # Strip ANSI codes when writing to file
        echo "[${timestamp}] [${level}] ${message}" >> "${FAIR_LOG_FILE}"
    else
        echo -e "${log_line}" >&2
    fi
}

# Convenience logging functions
fair_log_debug() { fair_log DEBUG "$@"; }
fair_log_info() { fair_log INFO "$@"; }
fair_log_warn() { fair_log WARN "$@"; }
fair_log_error() { fair_log ERROR "$@"; }

#==============================================================================
# Package Registry
#==============================================================================

# Package registry - stores Git repository URLs
declare -A FAIR_PACKAGE_URLS=(
    [faircmakemodules]="https://github.com/FairRootGroup/FairCMakeModules"
    [fairlogger]="https://github.com/FairRootGroup/FairLogger"
    [fairmq]="https://github.com/FairRootGroup/FairMQ"
)

# Package registry - stores default versions
declare -A FAIR_PACKAGE_DEFAULT_VERSIONS=(
    [faircmakemodules]="v1.0.0"
    [fairlogger]="v1.11.1"
    [fairmq]="v1.9.0"
)

# Active package versions (initialized from defaults, can be overridden)
declare -A FAIR_PACKAGE_VERSIONS=()

# Register a new package in the registry
# Input: $1=package_name, $2=git_url, $3=default_version
# Output: Adds package to registry
# Returns: 0 on success, 1 on error
fair_register_package() {
    local pkg_name="$1"
    local git_url="$2"
    local default_version="$3"

    if [[ -z "${pkg_name}" ]]; then
        fair_log_error "Package name is required"
        return 1
    fi

    if [[ -z "${git_url}" ]]; then
        fair_log_error "Git URL is required for package '${pkg_name}'"
        return 1
    fi

    if [[ -z "${default_version}" ]]; then
        fair_log_error "Default version is required for package '${pkg_name}'"
        return 1
    fi

    FAIR_PACKAGE_URLS["${pkg_name}"]="${git_url}"
    FAIR_PACKAGE_DEFAULT_VERSIONS["${pkg_name}"]="${default_version}"

    fair_log_debug "Registered package: ${pkg_name} -> ${git_url} (default: ${default_version})"
    return 0
}

# Get list of registered package names
# Output: Prints package names (one per line), sorted
fair_list_packages() {
    printf '%s\n' "${!FAIR_PACKAGE_URLS[@]}" | sort
}

# Check if package is registered
# Input: $1=package_name
# Returns: 0 if registered, 1 otherwise
fair_package_exists() {
    local pkg_name="$1"
    [[ -n "${FAIR_PACKAGE_URLS[${pkg_name}]}" ]]
}

# Get package URL from registry
# Input: $1=package_name
# Output: Prints Git URL
# Returns: 0 on success, 1 if package not found
fair_get_package_url() {
    local pkg_name="$1"

    if ! fair_package_exists "${pkg_name}"; then
        fair_log_error "Package '${pkg_name}' not found in registry"
        return 1
    fi

    echo "${FAIR_PACKAGE_URLS[${pkg_name}]}"
}

# Get package version (from active config)
# Input: $1=package_name
# Output: Prints version string
# Returns: 0 on success, 1 if package not found
fair_get_package_version() {
    local pkg_name="$1"

    if ! fair_package_exists "${pkg_name}"; then
        fair_log_error "Package '${pkg_name}' not found in registry"
        return 1
    fi

    echo "${FAIR_PACKAGE_VERSIONS[${pkg_name}]}"
}

# Validate package name
# Input: $1=package_name
# Returns: 0 if valid, 1 otherwise
_fair_validate_package() {
    local pkg_name="$1"

    if [[ -z "${pkg_name}" ]]; then
        fair_log_error "Package name is required"
        return 1
    fi

    if ! fair_package_exists "${pkg_name}"; then
        fair_log_error "Unknown package '${pkg_name}'. Available packages:"
        fair_list_packages | while read -r pkg; do
            fair_log_error "  - ${pkg}"
        done
        return 1
    fi

    return 0
}

#==============================================================================
# Configuration Management
#==============================================================================

# Initialize configuration variables with defaults
# Input: Environment variables (optional overrides)
# Output: Sets FAIR_* global variables
fair_init_config() {
    fair_log_debug "Initializing configuration..."

    # Initialize package versions from environment or defaults
    for pkg_name in "${!FAIR_PACKAGE_URLS[@]}"; do
        local pkg_upper=$(echo "${pkg_name}" | tr '[:lower:]' '[:upper:]')
        local env_var="FAIR_${pkg_upper}_VERSION"
        local default_version="${FAIR_PACKAGE_DEFAULT_VERSIONS[${pkg_name}]}"

        # Use environment variable if set, otherwise use default from registry
        FAIR_PACKAGE_VERSIONS["${pkg_name}"]="${!env_var:-${default_version}}"

        fair_log_debug "Package ${pkg_name}: version=${FAIR_PACKAGE_VERSIONS[${pkg_name}]}"
    done

    # General configuration
    : ${FAIR_OUTPUT_DIR:=$(pwd)/rpms}
    : ${FAIR_WORK_DIR:=$(pwd)/build}
    : ${FAIR_MOCK_CONFIG:=${FAIR_WORK_DIR}/rocky-8-fair.cfg}
    : ${FAIR_MOCK_ARGS:=}

    fair_log_info "Configuration initialized successfully"
}

# Install build dependencies (MUST RUN AS ROOT)
# Input: None
# Output: Installs required packages via dnf
fair_install_deps() {
    fair_log_debug "Installing build dependencies..."
    dnf install -y mock git gettext createrepo_c findutils tar || return $?
    fair_log_info "Build dependencies installed"
}

# Setup build environment (create directories and repository)
# Input: FAIR_OUTPUT_DIR, FAIR_WORK_DIR
# Output: Creates directories and local RPM repository
fair_setup_environment() {
    local output_dir="${FAIR_OUTPUT_DIR}"
    local work_dir="${FAIR_WORK_DIR}"

    if [[ -z "${output_dir}" ]] || [[ -z "${work_dir}" ]]; then
        fair_log_error "FAIR_OUTPUT_DIR and FAIR_WORK_DIR must be set"
        fair_log_error "Run fair_init_config first"
        return 1
    fi

    fair_log_debug "Setting up build environment..."
    mkdir -p "${output_dir}" "${work_dir}" || return $?

    # Create local repository
    createrepo_c "${output_dir}" || return $?

    fair_log_info "Build environment ready"
}

# Create mock configuration file
# Input: FAIR_MOCK_CONFIG, FAIR_OUTPUT_DIR
# Output: Creates mock config file at FAIR_MOCK_CONFIG
fair_create_mock_config() {
    local mock_config="${FAIR_MOCK_CONFIG}"
    local output_dir="${FAIR_OUTPUT_DIR}"

    if [[ -z "${mock_config}" ]] || [[ -z "${output_dir}" ]]; then
        fair_log_error "FAIR_MOCK_CONFIG and FAIR_OUTPUT_DIR must be set"
        fair_log_error "Run fair_init_config first"
        return 1
    fi

    if [[ ! -d "${output_dir}" ]]; then
        fair_log_error "Output directory does not exist: ${output_dir}"
        fair_log_error "Run fair_setup_environment first"
        return 1
    fi

    fair_log_debug "Creating mock configuration at ${mock_config}..."

    cat > "${mock_config}" <<EOF
include('/etc/mock/templates/rocky-8.tpl')
include('/etc/mock/templates/epel-8.tpl')

config_opts['root'] = 'rocky-8-fair'
config_opts['target_arch'] = 'x86_64'
config_opts['use_nspawn'] = False
config_opts['rpmbuild_networking'] = False
config_opts['use_host_resolv'] = True

# Use dnf backend instead of container bootstrap (faster in Docker)
config_opts['use_bootstrap_image'] = False
config_opts['package_manager'] = 'dnf'

# Use all available CPUs for building
config_opts['macros']['%_smp_mflags'] = '-j%(nproc)'

# Disable plugins that require namespace features
config_opts['plugin_conf']['mount_enable'] = False
config_opts['plugin_conf']['root_cache_enable'] = False

config_opts['yum.conf'] += """
[local-fair]
name=Local FAIR packages
baseurl=file://${output_dir}
enabled=1
gpgcheck=0
"""
EOF

    fair_log_info "Mock configuration created"
}

# Initialize mock bootstrap chroot
# Input: FAIR_MOCK_CONFIG, FAIR_MOCK_ARGS
# Output: Initializes mock bootstrap environment
fair_init_bootstrap() {
    local mock_config="${FAIR_MOCK_CONFIG}"

    if [[ -z "${mock_config}" ]]; then
        fair_log_error "FAIR_MOCK_CONFIG must be set"
        fair_log_error "Run fair_init_config first"
        return 1
    fi

    if [[ ! -f "${mock_config}" ]]; then
        fair_log_error "Mock configuration file does not exist: ${mock_config}"
        fair_log_error "Run fair_create_mock_config first"
        return 1
    fi

    fair_log_debug "Initializing mock bootstrap chroot..."
    mock -r "${mock_config}" ${FAIR_MOCK_ARGS} --init || return $?
    fair_log_info "Bootstrap chroot initialized"
}

# Context manager for strict mode with automatic cleanup
# Internal function - manages shell options and cleanup
# Input: callback function name, followed by its arguments
# Output: Executes callback with strict error handling enabled
_with_strict_mode() {
    local callback="$1"
    shift

    local old_opts=$(set +o)
    set -euo pipefail
    trap "eval '$old_opts'" EXIT ERR INT TERM

    # Execute the callback with remaining arguments
    "$callback" "$@"

    # Cleanup
    trap - EXIT ERR INT TERM
    eval "$old_opts"
}

# Internal: Build source RPM implementation
# Input: $1=name, $2=version, $3=source_dir
#        FAIR_MOCK_CONFIG, FAIR_WORK_DIR
# Output: SRPM in FAIR_WORK_DIR/${name}-${version}/
_do_build_srpm() {
    local pkg_name="$1"
    local pkg_version="$2"
    local source_dir="$3"

    local mock_config="${FAIR_MOCK_CONFIG}"
    local work_dir="${FAIR_WORK_DIR}"
    local version_no_v="${pkg_version#v}"
    local result_dir="${work_dir}/${pkg_name}-${version_no_v}"

    # Create unique temporary directory for build artifacts
    local temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/fair-build-${pkg_name}.XXXXXX")
    trap "rm -rf '${temp_dir}'" EXIT ERR INT TERM

    local tarball="${pkg_name}-${version_no_v}.tar.gz"
    local tarball_path="${temp_dir}/${tarball}"
    local spec_file="${temp_dir}/${pkg_name}.spec"

    fair_log_debug "Building SRPM for ${pkg_name} ${pkg_version}..."

    # Create source tarball from git repository (preserving git metadata for submodules)
    tar czf "${tarball_path}" \
        --transform="s,^\\.,${pkg_name}-${version_no_v}," \
        -C "${source_dir}" \
        .

    # Generate spec from template
    VERSION="${version_no_v}" \
    DATE="$(date '+%a %b %d %Y')" \
    envsubst < "${pkg_name}.spec.in" > "${spec_file}"

    # Build SRPM in mock
    mkdir -p "${result_dir}"
    mock -r "${mock_config}" ${FAIR_MOCK_ARGS} --buildsrpm \
        --spec "${spec_file}" \
        --sources "${tarball_path}" \
        --resultdir="${result_dir}"

    # Cleanup temp directory
    rm -rf "${temp_dir}"
    trap - EXIT ERR INT TERM

    fair_log_info "SRPM built: ${pkg_name} ${pkg_version}"
}

# Build source RPM from git repository
# Input: $1=name, $2=version, $3=source_dir
#        FAIR_MOCK_CONFIG, FAIR_WORK_DIR
# Output: SRPM in FAIR_WORK_DIR/${name}-${version}/
fair_build_srpm() {
    local pkg_name="$1"
    local pkg_version="$2"
    local source_dir="$3"

    # Validate package name using registry
    _fair_validate_package "${pkg_name}" || return 1

    if [[ -z "${pkg_version}" ]]; then
        fair_log_error "Package version is required"
        return 1
    fi

    if [[ -z "${source_dir}" ]]; then
        fair_log_error "Source directory is required"
        return 1
    fi

    if [[ ! -d "${source_dir}" ]]; then
        fair_log_error "Source directory does not exist: ${source_dir}"
        return 1
    fi

    if [[ ! -f "${pkg_name}.spec.in" ]]; then
        fair_log_error "Spec template not found: ${pkg_name}.spec.in"
        return 1
    fi

    # Run build with strict mode context manager
    _with_strict_mode _do_build_srpm "$pkg_name" "$pkg_version" "$source_dir"
}

# Internal: Build binary RPM implementation
# Input: $1=name, $2=version
#        FAIR_MOCK_CONFIG, FAIR_OUTPUT_DIR, FAIR_WORK_DIR
# Output: Binary RPMs in FAIR_OUTPUT_DIR, updated repository metadata
_do_build_rpm() {
    local pkg_name="$1"
    local pkg_version="$2"

    local mock_config="${FAIR_MOCK_CONFIG}"
    local output_dir="${FAIR_OUTPUT_DIR}"
    local work_dir="${FAIR_WORK_DIR}"
    local version_no_v="${pkg_version#v}"
    local result_dir="${work_dir}/${pkg_name}-${version_no_v}"

    # Ensure cleanup happens even on failure
    trap "rm -rf '${result_dir}'" EXIT ERR INT TERM

    fair_log_debug "Building binary RPMs for ${pkg_name} ${pkg_version}..."

    # Build binary RPMs in mock
    mock -r "${mock_config}" ${FAIR_MOCK_ARGS} --rebuild \
        --resultdir="${result_dir}" \
        "${result_dir}/${pkg_name}-${version_no_v}-"*.src.rpm

    # Collect all RPMs (including SRPM)
    find "${result_dir}" -name "*.rpm" -exec cp {} "${output_dir}/" \;

    # Update repository metadata (remove old metadata first to avoid conflicts)
    rm -rf "${output_dir}/.repodata" "${output_dir}/repodata"
    createrepo_c "${output_dir}"

    # Cleanup result directory
    rm -rf "${result_dir}"
    trap - EXIT ERR INT TERM

    fair_log_info "Binary RPMs built: ${pkg_name} ${pkg_version}"
}

# Build binary RPMs from source RPM
# Input: $1=name, $2=version
#        FAIR_MOCK_CONFIG, FAIR_OUTPUT_DIR, FAIR_WORK_DIR
# Output: Binary RPMs in FAIR_OUTPUT_DIR, updated repository metadata
fair_build_rpm() {
    local pkg_name="$1"
    local pkg_version="$2"

    # Validate package name using registry
    _fair_validate_package "${pkg_name}" || return 1

    if [[ -z "${pkg_version}" ]]; then
        fair_log_error "Package version is required"
        return 1
    fi

    local work_dir="${FAIR_WORK_DIR}"
    local version_no_v="${pkg_version#v}"
    local result_dir="${work_dir}/${pkg_name}-${version_no_v}"

    # Check if SRPM exists
    local srpms=( "${result_dir}/${pkg_name}-${version_no_v}-"*.src.rpm )
    if [[ ! -f "${srpms[0]}" ]]; then
        fair_log_error "Source RPM not found in ${result_dir}/"
        fair_log_error "Run fair_build_srpm first"
        return 1
    fi

    # Run build with strict mode context manager
    _with_strict_mode _do_build_rpm "$pkg_name" "$pkg_version"
}

# Print current configuration
# Input: All FAIR_* variables
# Output: Prints configuration to stdout
fair_show_config() {
    echo "FAIR RPM Build Configuration:"
    echo ""
    echo "Packages:"
    for pkg_name in $(fair_list_packages); do
        local version="${FAIR_PACKAGE_VERSIONS[${pkg_name}]:-${FAIR_PACKAGE_DEFAULT_VERSIONS[${pkg_name}]}}"
        local url="${FAIR_PACKAGE_URLS[${pkg_name}]}"
        echo "  ${pkg_name}:"
        echo "    Version: ${version}"
        echo "    URL: ${url}"
    done
    echo ""
    echo "Build Environment:"
    echo "  FAIR_OUTPUT_DIR: ${FAIR_OUTPUT_DIR}"
    echo "  FAIR_WORK_DIR: ${FAIR_WORK_DIR}"
    echo "  FAIR_MOCK_CONFIG: ${FAIR_MOCK_CONFIG}"
    echo ""
    echo "Logging:"
    echo "  FAIR_LOG_LEVEL: ${FAIR_LOG_LEVEL}"
    echo "  FAIR_LOG_COLOR: ${FAIR_LOG_COLOR}"
    echo "  FAIR_LOG_FILE: ${FAIR_LOG_FILE:-<stderr>}"
}
