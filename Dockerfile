# SPDX-FileCopyrightText: 2025 GSI Helmholtzzentrum für Schwerionenforschung GmbH
# SPDX-License-Identifier: GPL-3.0-or-later

# Version build arguments (global, available to all stages)
ARG FAIRCMAKEMODULES_VERSION=v1.0.0
ARG FAIRLOGGER_VERSION=v1.11.1
ARG FAIRMQ_VERSION=v1.9.0

# Common build arguments for RPM packages
ARG RPM_MAINTAINER="GSI <sde@gsi.de>"
ARG RPM_LICENSE="LGPL-3.0"
ARG RPM_DATE="Fri Oct 17 2025"

# Build images (need to be inside GSI intranet)
# Base image:
#   docker buildx build --target base --network host -t virgo:3 .
# FairMQ image (with devel packages):
#   docker buildx build --target fairmq --network host -t virgo:3-fairmq .

# Convert to Apptainer format
# apptainer build virgo_3.sif docker-daemon://virgo:3
# apptainer build virgo_3_fairmq.sif docker-daemon://virgo:3-fairmq

# Usage
# ssh virgo.hpc.gsi.de
# virgo> apptainer exec --bind /etc/slurm,/var/run/munge,/var/spool/slurmd,/var/lib/sss/pipes/nss virgo_3.sif bash -l
# virgo/Apptainer> export SLURM_SINGULARITY_CONTAINER=<FULL-PATH-TO>virgo_3.sif # or --singularity-container arg to srun/sbatch
# virgo/Apptainer> srun ... / sbatch ...

FROM rockylinux:8 AS installer

# Variables to deduplicate the content of this file
ENV tgt_cluster=virgo
ENV tgt_version=3
ENV tgt=/tgt
ENV reposdir=/etc/yum.repos.d
ENV tgt_releasever=8
ENV mirror=http://cluster-mirror.hpc.gsi.de

RUN <<EORUN
mkdir -p ${tgt}${reposdir}
# One can lookup this from a Virgo submitter node in /etc/yum.repos.d/gsi-*.repo
cat <<EOC | tee ${tgt}${reposdir}/gsi-rocky.repo
[gsi-rocky-base]
name = gsi-rocky-base
baseurl = ${mirror}/rocky/${tgt_releasever}/BaseOS/x86_64/os
enabled = 1
gpgcheck = 0

[gsi-rocky-appstream]
name = gsi-rocky-appstream
baseurl = ${mirror}/rocky/${tgt_releasever}/AppStream/x86_64/os
enabled = 1
gpgcheck = 0

[gsi-rocky-powertools]
name = gsi-rocky-powertools
baseurl = ${mirror}/rocky/${tgt_releasever}/PowerTools/x86_64/os
enabled = 1
gpgcheck = 0
EOC
cat <<EOC | tee ${tgt}${reposdir}/gsi-epel.repo
[gsi-epel]
name = gsi-epel
baseurl = ${mirror}/epel/${tgt_releasever}/Everything/x86_64
enabled = 1
gpgcheck = 0
EOC
cat <<EOC | tee ${tgt}${reposdir}/gsi-packages.repo
[gsi-packages]
name = gsi-packages
baseurl = ${mirror}/packages/el${tgt_releasever}
enabled = 1
gpgcheck = 0
EOC
cat <<EOC | tee /tmp/dnf.conf
[main]
reposdir=${tgt}${reposdir}
EOC

alias dnf="dnf --installroot=${tgt} --releasever=${tgt_releasever} --config /tmp/dnf.conf --setopt=install_weak_deps=False -y"
dnf repolist --all
dnf install bash coreutils dnf langpacks-en
rm -rf ${tgt}${reposdir}/Rocky*.repo
# slurm-release installs /etc/yum.repos.d/slurm.repo and /etc/pki/rpm-gpg/RPM-GPG-KEY-slurm
dnf install ${mirror}/packages/${tgt_cluster}-${tgt_version}/el${tgt_releasever}/slurm-release.rpm
cp ${tgt}/etc/pki/rpm-gpg/RPM-GPG-KEY-slurm /etc/pki/rpm-gpg/
dnf update
dnf install slurm slurm-singularity-exec
dnf autoremove
dnf clean all

chroot ${tgt} groupadd --system --gid 31002 slurm
chroot ${tgt} useradd --system --uid 31002 --gid 31002 slurm

mkdir -p ${tgt}/lustre

cat <<EOC | tee ${tgt}/etc/release
${tgt_cluster} ${tgt_version} - container
$(date +%Y%m%dT%H%M)
EOC
EORUN

FROM scratch AS base
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
COPY --from=installer /tgt /

CMD ["bash"]

FROM base AS package-base
RUN dnf install -y rpm-build rpmdevtools dnf-plugins-core gettext && dnf clean all && rpmdev-setuptree

FROM package-base AS package-faircmakemodules

ARG FAIRCMAKEMODULES_VERSION
ARG RPM_MAINTAINER
ARG RPM_LICENSE
ARG RPM_DATE

# Clone FairCMakeModules source with full git metadata
ADD https://github.com/FairRootGroup/FairCMakeModules.git#${FAIRCMAKEMODULES_VERSION} /tmp/faircmakemodules-src

# Create source tarball for RPM build
RUN cd /tmp/faircmakemodules-src \
    && tar czf ~/rpmbuild/SOURCES/faircmakemodules-${FAIRCMAKEMODULES_VERSION}.tar.gz \
    --transform "s,^,faircmakemodules-${FAIRCMAKEMODULES_VERSION}/," .

# Copy spec template and substitute variables
COPY specs/faircmakemodules.spec.in /tmp/
RUN export VERSION=${FAIRCMAKEMODULES_VERSION#v} \
           LICENSE=${RPM_LICENSE} \
           MAINTAINER=${RPM_MAINTAINER} \
           DATE=${RPM_DATE} && \
    envsubst < /tmp/faircmakemodules.spec.in > ~/rpmbuild/SPECS/faircmakemodules.spec

# Install dependencies, build RPMs, and collect
RUN dnf builddep -y ~/rpmbuild/SPECS/faircmakemodules.spec && \
    rpmbuild -ba ~/rpmbuild/SPECS/faircmakemodules.spec && \
    mkdir -p /rpms && \
    cp ~/rpmbuild/RPMS/*/*.rpm /rpms/

# Runtime image with FairCMakeModules installed
FROM base AS faircmakemodules

COPY --from=package-faircmakemodules /rpms/*.rpm /tmp/rpms/
RUN dnf install -y /tmp/rpms/*.rpm && dnf clean all && rm -rf /tmp/rpms

FROM package-base AS package-fairlogger

ARG FAIRLOGGER_VERSION
ARG RPM_MAINTAINER
ARG RPM_LICENSE
ARG RPM_DATE

# Install faircmakemodules (required by BuildRequires)
COPY --from=package-faircmakemodules /rpms/*.rpm /tmp/rpms/
RUN dnf install -y /tmp/rpms/*.rpm && rm -rf /tmp/rpms

# Clone FairLogger source with full git metadata
ADD https://github.com/FairRootGroup/FairLogger.git#${FAIRLOGGER_VERSION} /tmp/fairlogger-src

# Create source tarball for RPM build
RUN cd /tmp/fairlogger-src \
    && tar czf ~/rpmbuild/SOURCES/fairlogger-${FAIRLOGGER_VERSION}.tar.gz \
    --transform "s,^,fairlogger-${FAIRLOGGER_VERSION}/," .

# Copy spec template and substitute variables
COPY specs/fairlogger.spec.in /tmp/
RUN export VERSION=${FAIRLOGGER_VERSION#v} \
           LICENSE=${RPM_LICENSE} \
           MAINTAINER=${RPM_MAINTAINER} \
           DATE=${RPM_DATE} && \
    envsubst < /tmp/fairlogger.spec.in > ~/rpmbuild/SPECS/fairlogger.spec

# Install dependencies, build RPMs, and collect
RUN dnf builddep -y ~/rpmbuild/SPECS/fairlogger.spec && \
    rpmbuild -ba ~/rpmbuild/SPECS/fairlogger.spec && \
    mkdir -p /rpms && \
    cp ~/rpmbuild/RPMS/*/*.rpm /rpms/

# Runtime image with FairCMakeModules and FairLogger installed
FROM faircmakemodules AS fairlogger

COPY --from=package-fairlogger /rpms/*.rpm /tmp/rpms/
RUN dnf install -y /tmp/rpms/*.rpm && dnf clean all && rm -rf /tmp/rpms

FROM package-base AS package-fairmq

ARG FAIRMQ_VERSION
ARG RPM_MAINTAINER
ARG RPM_LICENSE
ARG RPM_DATE

# Install faircmakemodules and fairlogger-devel (required by BuildRequires)
COPY --from=package-faircmakemodules /rpms/*.rpm /tmp/rpms-cmake/
COPY --from=package-fairlogger /rpms/*.rpm /tmp/rpms-logger/
RUN dnf install -y /tmp/rpms-cmake/*.rpm /tmp/rpms-logger/*.rpm && rm -rf /tmp/rpms-*

# Install git for submodule operations
RUN dnf install -y git && dnf clean all

# Clone FairMQ source with full git metadata (needed for version detection)
ADD --keep-git-dir=true https://github.com/FairRootGroup/FairMQ.git#${FAIRMQ_VERSION} /tmp/fairmq-src

# Initialize submodules and create source tarball for RPM build
RUN cd /tmp/fairmq-src \
    && git submodule update --init --recursive \
    && tar czf ~/rpmbuild/SOURCES/fairmq-${FAIRMQ_VERSION}.tar.gz \
    --transform "s,^,fairmq-${FAIRMQ_VERSION}/," .

# Copy spec template and substitute variables
COPY specs/fairmq.spec.in /tmp/
RUN export VERSION=${FAIRMQ_VERSION#v} \
           LICENSE=${RPM_LICENSE} \
           MAINTAINER=${RPM_MAINTAINER} \
           DATE=${RPM_DATE} && \
    envsubst < /tmp/fairmq.spec.in > ~/rpmbuild/SPECS/fairmq.spec

# Install dependencies, build RPMs, and collect
RUN dnf builddep -y ~/rpmbuild/SPECS/fairmq.spec && \
    rpmbuild -ba ~/rpmbuild/SPECS/fairmq.spec && \
    mkdir -p /rpms && \
    cp ~/rpmbuild/RPMS/*/*.rpm /rpms/

# Final runtime image with complete FAIR software stack (includes devel packages)
FROM fairlogger AS fairmq

COPY --from=package-fairmq /rpms/*.rpm /tmp/rpms/
RUN dnf install -y /tmp/rpms/*.rpm && dnf clean all && rm -rf /tmp/rpms
