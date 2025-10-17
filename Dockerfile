# Build just the base image (need to be inside GSI intranet)
# docker buildx build --target base --network host -t virgo:3 <dir-where-this-dockerfile-is>

# Convert to Apptainer format
# apptainer build <your-name>.sif docker-daemon://<tag-chose-in-above-builds>

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

alias dnf="dnf --installroot=${tgt} --releasever=${tgt_releasever} --config /tmp/dnf.conf -y"
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
