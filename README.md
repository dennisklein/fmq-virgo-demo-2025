<!--
SPDX-FileCopyrightText: 2025 GSI Helmholtzzentrum für Schwerionenforschung GmbH
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Virgo 3 HPC Container

Docker/Apptainer container images for running SLURM workloads on the GSI Virgo cluster with the FAIR software stack.

## Contents

- **[packaging/](packaging/)** - RPM spec files and build tooling for FAIR software packages

## Prerequisites

- Access to GSI intranet (required for building)
- Docker with buildx support
- Apptainer/Singularity (for cluster deployment)
- SSH access to virgo.hpc.gsi.de

## Quick Start

### Setup Build Environment

Create a Docker buildx builder with security.insecure entitlement (required for RPM building with mock):

```bash
docker buildx create --name fair-builder --driver docker-container \
  --buildkitd-flags '--allow-insecure-entitlement security.insecure'
```

### Build Images

**Build all images** (uses docker buildx bake):
```bash
docker buildx bake --builder fair-builder --allow security.insecure
```

**Build individual targets:**
```bash
# Just the FAIR RPM repository
docker buildx bake --builder fair-builder --allow security.insecure fair-repo

# Full Virgo cluster image with FAIR software
docker buildx bake --builder fair-builder --allow security.insecure fairmq
```

**Customize software versions** by editing `docker-bake.hcl`:
```hcl
args = {
  FAIRCMAKEMODULES_VERSION = "1.0.0"
  FAIRLOGGER_VERSION = "1.11.1"
  FAIRMQ_VERSION = "1.9.0"
}
```

### Convert to Apptainer

From local Docker images:
```bash
apptainer build virgo-fairmq.sif docker-daemon://virgo-fairmq:latest
```

Or pull directly from GitHub Container Registry:
```bash
apptainer build virgo-fairmq.sif docker://ghcr.io/dennisklein/fmq-virgo-demo-2025/virgo-fairmq:latest
```

## Usage on Virgo Cluster

Launch the container with required bind mounts:

```bash
apptainer exec \
  --bind /etc/slurm,/var/run/munge,/var/spool/slurmd,/var/lib/sss/pipes/nss \
  virgo-fairmq.sif bash -l
```

Use with SLURM:

```bash
# Set environment variable
export SLURM_SINGULARITY_CONTAINER=/full/path/to/virgo-fairmq.sif

# Or pass directly to commands
srun --singularity-container=/full/path/to/virgo-fairmq.sif <command>
sbatch --singularity-container=/full/path/to/virgo-fairmq.sif <script>
```

### Required Bind Mounts

- `/etc/slurm` - SLURM configuration files
- `/var/run/munge` - Munge authentication socket
- `/var/spool/slurmd` - SLURM daemon spool directory
- `/var/lib/sss/pipes/nss` - System Security Services Daemon pipes

## Available Images

### Base Image
- Rocky Linux 8
- SLURM client tools
- slurm-singularity-exec integration
- Lustre filesystem mount point (`/lustre`)
- Minimal footprint

### FairMQ Image
Base image plus:
- **FairCMakeModules** - CMake modules for FAIR projects
- **FairLogger** - C++ logging library
- **FairMQ** - Message queuing framework
  - Command-line tools (`fairmq-*`)
  - Development headers and CMake configs
  - High-throughput, zero-copy transport

## Build System

### Architecture

The build system uses Docker Buildx Bake to orchestrate multi-stage builds:

1. **packaging/** - Builds FAIR software RPMs using mock in isolated stages
2. **fair-repo** - Exports built RPMs as a DNF/YUM repository image
3. **Dockerfile** - Consumes FAIR packages from the repository

### Available Build Targets

See `docker-bake.hcl` for complete configuration.

**Bake Targets:**
- `fair-repo` - FAIR software DNF/YUM repository (FairCMakeModules, FairLogger, FairMQ)
- `fairmq` - Complete Virgo cluster image with FAIR software stack

**Dockerfile Stages:**
- `base` - Minimal Virgo 3 + SLURM
- `fairmq` - base + FAIR software from repository

## Configuration

### Software Versions

Configured in `docker-bake.hcl` under the `fair-repo` target:

| Variable | Default | Description |
|----------|---------|-------------|
| `FAIRCMAKEMODULES_VERSION` | `1.0.0` | FairCMakeModules version (without 'v' prefix) |
| `FAIRLOGGER_VERSION` | `1.11.1` | FairLogger version (without 'v' prefix) |
| `FAIRMQ_VERSION` | `1.9.0` | FairMQ version (without 'v' prefix) |

**Note:** Versions are specified without the 'v' prefix. The build system adds 'v' when cloning git tags.

### Technical Details

- **Base OS:** Rocky Linux 8
- **SLURM User:** UID/GID 31002
- **Package Mirror:** http://cluster-mirror.hpc.gsi.de
- **Target Cluster:** Virgo 3

## License

GNU General Public License v3.0 or later (GPL-3.0-or-later).
See [LICENSES/GPL-3.0-or-later.txt](LICENSES/GPL-3.0-or-later.txt) for details.
