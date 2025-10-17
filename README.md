<!--
SPDX-FileCopyrightText: 2025 GSI Helmholtzzentrum für Schwerionenforschung GmbH
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Virgo 3 HPC Container

A Docker/Apptainer container image for running SLURM workloads on the GSI Virgo cluster.

## Prerequisites

- Access to GSI intranet (required for building)
- Docker with buildx support
- Apptainer/Singularity (for cluster deployment)
- SSH access to virgo.hpc.gsi.de

## Building

### 1. Build Docker Image

The build must be performed from within the GSI intranet to access the cluster mirror:

```bash
docker buildx build --target base --network host -t virgo:3 .
```

### 2. Convert to Apptainer Format

```bash
apptainer build virgo_3.sif docker-daemon://virgo:3
```

## Usage

### Running on Virgo Cluster

1. Copy the `.sif` file to the Virgo cluster
2. SSH into the cluster:

```bash
ssh virgo.hpc.gsi.de
```

3. Launch the container with required bind mounts:

```bash
apptainer exec \
  --bind /etc/slurm,/var/run/munge,/var/spool/slurmd,/var/lib/sss/pipes/nss \
  virgo_3.sif bash -l
```

4. Inside the container, set the SLURM container variable:

```bash
export SLURM_SINGULARITY_CONTAINER=/full/path/to/virgo_3.sif
```

Or pass it directly to SLURM commands:

```bash
srun --singularity-container=/full/path/to/virgo_3.sif <command>
sbatch --singularity-container=/full/path/to/virgo_3.sif <script>
```

### Bind Mounts Explained

The following host paths must be mounted for proper cluster integration:

- `/etc/slurm` - SLURM configuration files
- `/var/run/munge` - Munge authentication socket
- `/var/spool/slurmd` - SLURM daemon spool directory
- `/var/lib/sss/pipes/nss` - System Security Services Daemon pipes for user/group resolution

## What's Included

- Rocky Linux 8 base system
- SLURM client tools
- slurm-singularity-exec integration
- Lustre filesystem mount point at `/lustre`
- UTF-8 locale configuration
- Minimal system footprint (FROM scratch base)

## Technical Details

- **Base OS**: Rocky Linux 8
- **SLURM User**: UID/GID 31002
- **Package Mirror**: http://cluster-mirror.hpc.gsi.de
- **Target Cluster**: Virgo 3

## License

This project is licensed under the GNU General Public License v3.0 or later (GPL-3.0-or-later).
See the [LICENSES/GPL-3.0-or-later.txt](LICENSES/GPL-3.0-or-later.txt) file for details.
