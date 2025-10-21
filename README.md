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

### Build Images

**Base image** (minimal SLURM-enabled container):
```bash
docker buildx build --target base --network host -t virgo:3 .
```

**FairMQ image** (base + FairMQ libraries and tools):
```bash
docker buildx build --target fairmq --network host -t virgo:3-fairmq .
```

Customize software versions:
```bash
docker buildx build --target fairmq --network host \
  --build-arg FAIRCMAKEMODULES_VERSION=v1.0.0 \
  --build-arg FAIRLOGGER_VERSION=v1.11.1 \
  --build-arg FAIRMQ_VERSION=v1.9.0 \
  -t virgo:3-fairmq .
```

### Convert to Apptainer

From local Docker images:
```bash
apptainer build virgo_3_fairmq.sif docker-daemon://virgo:3-fairmq
```

Or pull directly from GitHub Container Registry:
```bash
apptainer build virgo_3_fairmq.sif docker://ghcr.io/dennisklein/fmq-virgo-demo-2025/virgo:3-fairmq
```

## Usage on Virgo Cluster

Launch the container with required bind mounts:

```bash
apptainer exec \
  --bind /etc/slurm,/var/run/munge,/var/spool/slurmd,/var/lib/sss/pipes/nss \
  virgo_3_fairmq.sif bash -l
```

Use with SLURM:

```bash
# Set environment variable
export SLURM_SINGULARITY_CONTAINER=/full/path/to/virgo_3_fairmq.sif

# Or pass directly to commands
srun --singularity-container=/full/path/to/virgo_3_fairmq.sif <command>
sbatch --singularity-container=/full/path/to/virgo_3_fairmq.sif <script>
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

## Build Optimization

### HTTP Caching (Optional)

Speed up repeated builds with a local HTTP cache:

```bash
# Start cache
docker compose -f build/docker-compose.yml up -d

# Build with cache
docker buildx build --target fairmq --network host \
  --build-arg http_proxy=http://localhost:3128 \
  --build-arg https_proxy=http://localhost:3128 \
  -t virgo:3-fairmq .

# Stop cache
docker compose -f build/docker-compose.yml down
```

### Available Build Targets

**Runtime Stages:**
- `base` - Minimal Virgo 3 + SLURM
- `faircmakemodules` - base + FairCMakeModules
- `fairlogger` - faircmakemodules + FairLogger
- `fairmq` - fairlogger + FairMQ (complete stack)

**Build Stages:**
- `package-faircmakemodules` - Builds FairCMakeModules RPMs
- `package-fairlogger` - Builds FairLogger RPMs
- `package-fairmq` - Builds FairMQ RPMs

## Configuration

### Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `FAIRCMAKEMODULES_VERSION` | `v1.0.0` | FairCMakeModules git tag |
| `FAIRLOGGER_VERSION` | `v1.11.1` | FairLogger git tag |
| `FAIRMQ_VERSION` | `v1.9.0` | FairMQ git tag |

### Technical Details

- **Base OS:** Rocky Linux 8
- **SLURM User:** UID/GID 31002
- **Package Mirror:** http://cluster-mirror.hpc.gsi.de
- **Target Cluster:** Virgo 3

## License

GNU General Public License v3.0 or later (GPL-3.0-or-later).
See [LICENSES/GPL-3.0-or-later.txt](LICENSES/GPL-3.0-or-later.txt) for details.
