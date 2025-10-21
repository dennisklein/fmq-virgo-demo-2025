<!--
SPDX-FileCopyrightText: 2025 GSI Helmholtzzentrum für Schwerionenforschung GmbH
SPDX-License-Identifier: GPL-3.0-or-later
-->

# RPM Spec Files for FAIR Software

RPM spec templates for building FAIR software packages on RPM-based Linux distributions.

## Available Packages

### faircmakemodules.spec.in

**FairCMakeModules** - CMake modules for FAIR software projects

- **Architecture:** noarch
- **Upstream:** https://github.com/FairRootGroup/FairCMakeModules
- **BuildRequires:** cmake >= 3.15, gcc-c++, git

### fairlogger.spec.in

**FairLogger** - Lightweight and fast C++ logging library

- **Architecture:** Platform-specific
- **Upstream:** https://github.com/FairRootGroup/FairLogger
- **BuildRequires:** cmake >= 3.15, gcc-c++, git, boost-devel, fmt-devel

### fairmq.spec.in

**FairMQ** - C++ message queuing library and framework

- **Architecture:** Platform-specific
- **Upstream:** https://github.com/FairRootGroup/FairMQ
- **Sub-packages:** fairmq, fairmq-devel
- **BuildRequires:** cmake >= 3.15, gcc-c++, git, boost-devel, fairlogger-devel, zeromq-devel, protobuf-devel

## Template Variables

Each `.spec.in` file uses template variables that must be substituted:

- `${VERSION}` - Software version without 'v' prefix (e.g., `1.0.0`)
- `${LICENSE}` - SPDX license identifier (e.g., `LGPL-3.0-or-later`)
- `${DATE}` - Build date in changelog format (e.g., `Wed Jan 15 2025`)
- `${MAINTAINER}` - Package maintainer (e.g., `Your Name <email@example.com>`)

## Building Packages

### Using the Build Library

The `fair-rpm-build-lib.sh` provides reusable functions for building FAIR software packages using mock.

**Features:**
- Configurable package registry for adding custom packages
- Structured logging with multiple log levels and colored output
- Environment-based configuration with sensible defaults
- Automatic dependency ordering and validation

**Complete build example:**

```bash
#!/bin/bash
set -e

# Source the library
source fair-rpm-build-lib.sh

# Optional: Configure logging
export FAIR_LOG_LEVEL=DEBUG        # DEBUG, INFO, WARN, ERROR (default: INFO)
export FAIR_LOG_COLOR=auto         # auto, always, never (default: auto)
export FAIR_LOG_FILE=/tmp/build.log  # Optional: log to file

# Initialize configuration (uses defaults or environment variables)
fair_init_config

# Optional: Register custom packages
fair_register_package "mypackage" "https://github.com/myorg/mypackage" "v2.0.0"

# Optional: Override default package versions
export FAIR_FAIRMQ_VERSION=v1.9.1
export FAIR_OUTPUT_DIR=/tmp/fair-rpms

# Re-initialize with new values
fair_init_config

# Show configuration
fair_show_config

# Install dependencies (requires root)
sudo fair_install_deps

# Setup environment and create mock config
fair_setup_environment
fair_create_mock_config
fair_init_bootstrap

# Clone source repositories with submodules
repo_url=$(fair_get_package_url faircmakemodules)
git clone --recursive --depth 1 --branch "$(fair_get_package_version faircmakemodules)" "${repo_url}" /src/faircmakemodules

repo_url=$(fair_get_package_url fairlogger)
git clone --recursive --depth 1 --branch "$(fair_get_package_version fairlogger)" "${repo_url}" /src/fairlogger

repo_url=$(fair_get_package_url fairmq)
git clone --recursive --depth 1 --branch "$(fair_get_package_version fairmq)" "${repo_url}" /src/fairmq

# Build packages in dependency order
fair_build_srpm faircmakemodules "$(fair_get_package_version faircmakemodules)" /src/faircmakemodules
fair_build_rpm faircmakemodules "$(fair_get_package_version faircmakemodules)"

fair_build_srpm fairlogger "$(fair_get_package_version fairlogger)" /src/fairlogger
fair_build_rpm fairlogger "$(fair_get_package_version fairlogger)"

fair_build_srpm fairmq "$(fair_get_package_version fairmq)" /src/fairmq
fair_build_rpm fairmq "$(fair_get_package_version fairmq)"
```

### Available Functions

#### Configuration Functions

##### `fair_init_config`
Initialize configuration variables with defaults or from environment.

**Environment variables:**

*Package versions (optional):*
- `FAIR_FAIRCMAKEMODULES_VERSION` - FairCMakeModules version (default: `v1.0.0`)
- `FAIR_FAIRLOGGER_VERSION` - FairLogger version (default: `v1.11.1`)
- `FAIR_FAIRMQ_VERSION` - FairMQ version (default: `v1.9.0`)

*Build environment:*
- `FAIR_OUTPUT_DIR` - Output directory for RPMs (default: `./rpms`)
- `FAIR_WORK_DIR` - Working directory for builds (default: `./build`)
- `FAIR_MOCK_CONFIG` - Mock config file path (default: `./build/rocky-8-fair.cfg`)
- `FAIR_MOCK_ARGS` - Additional mock arguments (default: empty)

*Logging:*
- `FAIR_LOG_LEVEL` - Logging level: DEBUG, INFO, WARN, ERROR (default: `INFO`)
- `FAIR_LOG_COLOR` - Color output: auto, always, never (default: `auto`)
- `FAIR_LOG_FILE` - Log file path (default: none, logs to stderr)

**Returns:** Always succeeds (exit code 0)

##### `fair_show_config`
Display current configuration including all registered packages, versions, and settings.

**Example output:**
```
FAIR RPM Build Configuration:

Packages:
  faircmakemodules:
    Version: v1.0.0
    URL: https://github.com/FairRootGroup/FairCMakeModules
  fairlogger:
    Version: v1.11.1
    URL: https://github.com/FairRootGroup/FairLogger
  fairmq:
    Version: v1.9.0
    URL: https://github.com/FairRootGroup/FairMQ

Build Environment:
  FAIR_OUTPUT_DIR: ./rpms
  FAIR_WORK_DIR: ./build
  FAIR_MOCK_CONFIG: ./build/rocky-8-fair.cfg

Logging:
  FAIR_LOG_LEVEL: INFO
  FAIR_LOG_COLOR: auto
  FAIR_LOG_FILE: <stderr>
```

**Returns:** Always succeeds (exit code 0)

#### Package Registry Functions

##### `fair_register_package <name> <git_url> <default_version>`
Register a custom package in the build registry.

**Parameters:**
- `name` - Package name (alphanumeric, lowercase recommended)
- `git_url` - Git repository URL
- `default_version` - Default version tag (e.g., v1.0.0)

**Returns:**
- `0` - Success
- `1` - Invalid parameters

**Example:**
```bash
fair_register_package "mypackage" "https://github.com/myorg/mypackage" "v2.0.0"
```

##### `fair_list_packages`
List all registered package names (sorted alphabetically).

**Returns:** Always succeeds (exit code 0)

**Example:**
```bash
for pkg in $(fair_list_packages); do
    echo "Package: $pkg"
done
```

##### `fair_package_exists <name>`
Check if a package is registered.

**Parameters:**
- `name` - Package name

**Returns:**
- `0` - Package exists
- `1` - Package not found

**Example:**
```bash
if fair_package_exists "fairmq"; then
    echo "Package is registered"
fi
```

##### `fair_get_package_url <name>`
Get the Git repository URL for a registered package.

**Parameters:**
- `name` - Package name

**Returns:**
- `0` - Success, URL printed to stdout
- `1` - Package not found

**Example:**
```bash
repo_url=$(fair_get_package_url fairmq)
echo "Repository: ${repo_url}"
```

##### `fair_get_package_version <name>`
Get the configured version for a registered package.

**Parameters:**
- `name` - Package name

**Returns:**
- `0` - Success, version printed to stdout
- `1` - Package not found

**Example:**
```bash
version=$(fair_get_package_version fairmq)
echo "Version: ${version}"
```

#### Build Environment Functions

##### `fair_install_deps`
Install build dependencies via dnf (requires root privileges).

**Dependencies installed:**
- mock, git, gettext, createrepo_c, findutils, tar

**Returns:**
- `0` - Success
- Non-zero - dnf installation failed

##### `fair_setup_environment`
Create build directories and initialize local RPM repository.

**Validates:**
- `FAIR_OUTPUT_DIR` and `FAIR_WORK_DIR` are set

**Returns:**
- `0` - Success
- `1` - Configuration not initialized

##### `fair_create_mock_config`
Generate mock configuration file with local repository support.

**Validates:**
- `FAIR_MOCK_CONFIG` and `FAIR_OUTPUT_DIR` are set
- Output directory exists

**Returns:**
- `0` - Success
- `1` - Validation failed

##### `fair_init_bootstrap`
Initialize mock bootstrap chroot environment.

**Validates:**
- `FAIR_MOCK_CONFIG` is set
- Mock configuration file exists

**Returns:**
- `0` - Success
- `1` - Validation failed
- Non-zero - mock command failed

#### Build Functions

##### `fair_build_srpm <name> <version> <source_dir>`
Build source RPM from git repository.

**Parameters:**
- `name` - Package name (must be registered in package registry)
- `version` - Package version (e.g., v1.9.0)
- `source_dir` - Path to git repository containing source code

**Validates:**
- All parameters are provided
- Package is registered in package registry
- Source directory exists
- Spec template file exists (${name}.spec.in)

**Returns:**
- `0` - SRPM built successfully
- `1` - Validation failed
- Non-zero - Build failed

**Example:**
```bash
fair_build_srpm fairmq v1.9.0 /src/fairmq
```

##### `fair_build_rpm <name> <version>`
Build binary RPMs from source RPM and publish to local repository.

**Parameters:**
- `name` - Package name (must be registered in package registry)
- `version` - Package version (e.g., v1.9.0)

**Validates:**
- All parameters are provided
- Package is registered in package registry
- Source RPM exists (from fair_build_srpm)

**Returns:**
- `0` - RPMs built successfully
- `1` - Validation failed
- Non-zero - Build failed

**Example:**
```bash
fair_build_rpm fairmq v1.9.0
```

#### Logging Functions

The library includes convenience logging functions that respect the `FAIR_LOG_LEVEL` setting:

- `fair_log <level> <message>` - Log a message at the specified level
- `fair_log_debug <message>` - Log at DEBUG level
- `fair_log_info <message>` - Log at INFO level
- `fair_log_warn <message>` - Log at WARN level
- `fair_log_error <message>` - Log at ERROR level

**Example:**
```bash
fair_log_info "Starting build process..."
fair_log_debug "Source directory: /src/fairmq"
fair_log_error "Build failed!"
```

## Testing

A Dockerfile is provided to test the build library in a clean environment:

```bash
# Build and run the test
docker build -t fair-rpm-test .

# The build process will verify all expected RPMs are created
# Check the output for "✓ All expected RPM files found!"

# Extract built RPMs (optional)
docker run --rm -v $(pwd)/output:/output fair-rpm-test \
    sh -c 'source fair-rpm-build-lib.sh && fair_init_config && cp ${FAIR_OUTPUT_DIR}/*.rpm /output/'
```
