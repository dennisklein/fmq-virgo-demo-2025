# syntax=docker/dockerfile:1.7-labs
# SPDX-FileCopyrightText: 2025 GSI Helmholtzzentrum für Schwerionenforschung GmbH
# SPDX-License-Identifier: GPL-3.0-or-later

# Test Dockerfile for FAIR RPM build library
# Builds all FAIR RPM packages and verifies outputs

# Stage 1: Base setup with dependencies
FROM rockylinux:8 AS base

# Install base requirements (use cache mount for dnf downloads)
RUN --mount=type=cache,target=/var/cache/dnf \
    --mount=type=cache,target=/var/cache/yum <<EOF
set -e
dnf install -y epel-release
dnf install -y mock git gettext createrepo_c findutils
EOF

# Copy spec files and build library
WORKDIR /build
COPY *.spec.in fair-rpm-build-lib.sh ./

# Set version arguments (without 'v' prefix - add 'v' where needed for git tags)
ARG FAIRCMAKEMODULES_VERSION=1.0.0
ARG FAIRLOGGER_VERSION=1.11.1
ARG FAIRMQ_VERSION=1.9.0

# Clone git repositories in parallel (Docker caches each ADD independently)
ADD --keep-git-dir=true https://github.com/FairRootGroup/FairCMakeModules.git#v${FAIRCMAKEMODULES_VERSION} /src/faircmakemodules
ADD --keep-git-dir=true https://github.com/FairRootGroup/FairLogger.git#v${FAIRLOGGER_VERSION} /src/fairlogger
ADD --keep-git-dir=true https://github.com/FairRootGroup/FairMQ.git#v${FAIRMQ_VERSION} /src/fairmq

# Optimize git repositories to reduce size
RUN cd /src/faircmakemodules && git reflog expire --expire=now --all && git gc --aggressive --prune=all && \
    cd /src/fairlogger && git reflog expire --expire=now --all && git gc --aggressive --prune=all && \
    cd /src/fairmq && git reflog expire --expire=now --all && git gc --aggressive --prune=all && \
    git submodule foreach 'git reflog expire --expire=now --all && git gc --aggressive --prune=all || true'

# Set mock arguments for Docker compatibility
ENV FAIR_MOCK_ARGS="--isolation=simple --verbose"
ENV FAIR_FAIRCMAKEMODULES_VERSION=v${FAIRCMAKEMODULES_VERSION}
ENV FAIR_FAIRLOGGER_VERSION=v${FAIRLOGGER_VERSION}
ENV FAIR_FAIRMQ_VERSION=v${FAIRMQ_VERSION}

# Stage 2: Initialize build environment
FROM base AS build-env

RUN --security=insecure \
    --mount=type=cache,target=/var/cache/dnf \
    --mount=type=cache,target=/var/cache/yum <<EOF
set -e
. ./fair-rpm-build-lib.sh
fair_init_config
fair_install_deps
fair_setup_environment
fair_create_mock_config
EOF

# Stage 3: Initialize mock bootstrap chroot
FROM build-env AS bootstrap

RUN --security=insecure \
    --mount=type=cache,target=/var/cache/mock \
    --mount=type=cache,target=/var/cache/dnf \
    --mount=type=cache,target=/var/cache/yum <<EOF
set -e
. ./fair-rpm-build-lib.sh
fair_init_config
fair_init_bootstrap
EOF

# Stage 4a: Build FairCMakeModules SRPM (parallel)
FROM bootstrap AS srpm-faircmakemodules

RUN --security=insecure \
    --mount=type=cache,target=/var/cache/mock <<EOF
set -e
. ./fair-rpm-build-lib.sh
fair_init_config
fair_build_srpm faircmakemodules "${FAIR_FAIRCMAKEMODULES_VERSION}" /src/faircmakemodules
EOF

# Stage 4b: Build FairLogger SRPM (parallel)
FROM bootstrap AS srpm-fairlogger

RUN --security=insecure \
    --mount=type=cache,target=/var/cache/mock <<EOF
set -e
. ./fair-rpm-build-lib.sh
fair_init_config
fair_build_srpm fairlogger "${FAIR_FAIRLOGGER_VERSION}" /src/fairlogger
EOF

# Stage 4c: Build FairMQ SRPM (parallel)
FROM bootstrap AS srpm-fairmq

RUN --security=insecure \
    --mount=type=cache,target=/var/cache/mock <<EOF
set -e
. ./fair-rpm-build-lib.sh
fair_init_config
fair_build_srpm fairmq "${FAIR_FAIRMQ_VERSION}" /src/fairmq
EOF

# Stage 5: Build FairCMakeModules binary RPM
FROM srpm-faircmakemodules AS rpm-faircmakemodules

RUN --security=insecure \
    --mount=type=cache,target=/var/cache/mock <<EOF
set -e
. ./fair-rpm-build-lib.sh
fair_init_config
fair_build_rpm faircmakemodules "${FAIR_FAIRCMAKEMODULES_VERSION}"
EOF

# Stage 6: Build FairLogger binary RPM (depends on FairCMakeModules)
FROM rpm-faircmakemodules AS rpm-fairlogger

# Re-declare ARG to use in this stage
ARG FAIRLOGGER_VERSION
COPY --from=srpm-fairlogger /build/build/fairlogger-${FAIRLOGGER_VERSION}/ /build/build/fairlogger-${FAIRLOGGER_VERSION}/

RUN --security=insecure \
    --mount=type=cache,target=/var/cache/mock <<EOF
set -e
. ./fair-rpm-build-lib.sh
fair_init_config
fair_build_rpm fairlogger "${FAIR_FAIRLOGGER_VERSION}"
EOF

# Stage 7: Build FairMQ binary RPM (depends on FairCMakeModules and FairLogger)
FROM rpm-fairlogger AS rpm-fairmq

# Re-declare ARG to use in this stage
ARG FAIRMQ_VERSION
COPY --from=srpm-fairmq /build/build/fairmq-${FAIRMQ_VERSION}/ /build/build/fairmq-${FAIRMQ_VERSION}/

RUN --security=insecure \
    --mount=type=cache,target=/var/cache/mock <<EOF
set -e
. ./fair-rpm-build-lib.sh
fair_init_config
fair_build_rpm fairmq "${FAIR_FAIRMQ_VERSION}"
EOF

# Stage 8: Verify all RPMs
FROM rpm-fairmq AS verify

RUN <<EOF
set -e
. ./fair-rpm-build-lib.sh
fair_init_config
cd ${FAIR_OUTPUT_DIR}
echo "Checking for expected RPM files..."
ls -1 faircmakemodules-*.noarch.rpm | grep -v '.src.rpm'
ls -1 faircmakemodules-*.src.rpm
ls -1 fairlogger-1*.x86_64.rpm | grep -v '.src.rpm'
ls -1 fairlogger-devel-*.x86_64.rpm
ls -1 fairlogger-*.src.rpm
ls -1 fairmq-1*.x86_64.rpm | grep -v '.src.rpm' | grep -v 'devel'
ls -1 fairmq-devel-*.x86_64.rpm
ls -1 fairmq-*.src.rpm
echo ""
echo "✓ All expected RPM files found!"
echo ""
echo "Build summary:"
ls -lh *.rpm
EOF

# Default command shows the built RPMs
CMD ["sh", "-c", ". ./fair-rpm-build-lib.sh && fair_init_config && ls -lh ${FAIR_OUTPUT_DIR}/*.rpm"]

# Stage 9: Export repository for consumption by other containers
# This image contains a complete yum/dnf repository with all FAIR packages
FROM scratch AS repo

# Copy built RPMs with repository metadata (createrepo_c already ran)
COPY --from=verify /build/rpms/ /rpms/

# Metadata for repository consumers
LABEL org.opencontainers.image.description="DNF/YUM repository with FAIR software packages (FairCMakeModules, FairLogger, FairMQ)"
LABEL org.opencontainers.image.source="https://github.com/FairRootGroup"
