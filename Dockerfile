# SPDX-FileCopyrightText: 2025 GSI Helmholtzzentrum für Schwerionenforschung GmbH
# SPDX-License-Identifier: GPL-3.0-or-later

# Virgo Cluster Container Image - see README.md for build instructions

FROM rockylinux:8 AS installer

# Variables to deduplicate the content of this file
ENV tgt_cluster=virgo
ENV tgt_version=3
ENV tgt=/tgt
ENV reposdir=/etc/yum.repos.d
ENV tgt_releasever=8
ENV mirror=http://cluster-mirror.hpc.gsi.de

RUN --mount=type=cache,target=/var/cache/dnf \
    --mount=type=cache,target=/var/cache/yum <<EORUN
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

# FAIR package repository (provided via fairrepo build context from packaging/)
FROM fairrepo AS fair-repo

FROM base AS fairmq

# Copy FAIR package repository
COPY --from=fair-repo /rpms /fair-repo

# Install FAIR packages from local repository
RUN --mount=type=cache,target=/var/cache/dnf \
    --mount=type=cache,target=/var/cache/yum <<EOF
set -e

# Configure local FAIR repository
cat > /etc/yum.repos.d/fair-local.repo <<EOC
[fair-local]
name=Local FAIR packages
baseurl=file:///fair-repo
enabled=1
gpgcheck=0
priority=1
EOC

# Install all FAIR packages (including devel packages for building)
dnf install -y \
    faircmakemodules \
    fairlogger \
    fairlogger-devel \
    fairmq \
    fairmq-devel

# Cleanup
dnf clean all
rm -rf /fair-repo /etc/yum.repos.d/fair-local.repo
EOF
