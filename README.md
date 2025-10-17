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

The build must be performed from within the GSI intranet to access the cluster mirror.

**Base image** (minimal SLURM-enabled container):
```bash
docker buildx build --target base --network host -t virgo:3 .
```

**FairMQ image** (base + FairMQ libraries and tools):
```bash
docker buildx build --target fairmq --network host -t virgo:3-fairmq .
```

You can customize the software versions during build:
```bash
docker buildx build --target fairmq --network host \
  --build-arg FAIRCMAKEMODULES_VERSION=v1.0.0 \
  --build-arg FAIRLOGGER_VERSION=v1.11.1 \
  --build-arg FAIRMQ_VERSION=v1.9.0 \
  -t virgo:3-fairmq .
```

### 2. Accelerating Builds with HTTP Cache (Optional)

If you're building over a slow network connection, you can use a local HTTP cache to speed up repeated builds. A Docker Compose configuration is provided in `build/` for running Squid as a caching proxy.

**Start the cache:**
```bash
docker compose -f build/docker-compose.yml up -d
```

**Build with caching enabled:**
```bash
docker buildx build --target fairmq --network host \
  --build-arg http_proxy=http://localhost:3128 \
  --build-arg https_proxy=http://localhost:3128 \
  -t virgo:3-fairmq .
```

The first build will populate the cache; subsequent builds will be significantly faster as packages are served from the local cache instead of the remote repository.

**Stop the cache:**
```bash
docker compose -f build/docker-compose.yml down
```

The cache data persists in a Docker volume, so you can stop and restart the cache without losing cached packages.

### 3. Convert to Apptainer Format

**From local Docker images:**
```bash
# Base image
apptainer build virgo_3.sif docker-daemon://virgo:3

# FairMQ image
apptainer build virgo_3_fairmq.sif docker-daemon://virgo:3-fairmq
```

**Directly from GitHub Container Registry** (no Docker required):
```bash
# Base image
apptainer build virgo_3.sif docker://ghcr.io/dennisklein/fmq-virgo-demo-2025/virgo:3

# FairMQ image
apptainer build virgo_3_fairmq.sif docker://ghcr.io/dennisklein/fmq-virgo-demo-2025/virgo:3-fairmq
```

This is particularly useful on the Virgo cluster where Docker may not be available. Apptainer will automatically pull and convert the image in one step.

## Usage

### Running on Virgo Cluster

1. **Obtain the container image** - either:
   - Copy a pre-built `.sif` file to the cluster, or
   - Build directly on the cluster from GitHub Container Registry:
     ```bash
     apptainer build virgo_3_fairmq.sif docker://ghcr.io/dennisklein/fmq-virgo-demo-2025/virgo:3-fairmq
     ```

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

### Base Image
- Rocky Linux 8 base system
- SLURM client tools
- slurm-singularity-exec integration
- Lustre filesystem mount point at `/lustre`
- UTF-8 locale configuration
- Minimal system footprint (FROM scratch base)

### FairMQ Image
All base image contents plus complete FAIR software stack:
- **FairCMakeModules**: CMake modules for FAIR software projects
- **FairLogger**: Lightweight and fast C++ logging library
- **FairMQ**: C++ message queuing library and framework
  - FairMQ command-line tools (`fairmq-*`)
  - Development headers and CMake configuration files
  - Support for high-throughput, zero-copy data transport

## Available Build Targets

The Dockerfile provides multiple build targets with clear separation between build and runtime stages:

**Build Stages** (intermediate, create RPM packages):
- **package-faircmakemodules**: Builds FairCMakeModules RPMs
- **package-fairlogger**: Builds FairLogger RPMs
- **package-fairmq**: Builds FairMQ RPMs

**Runtime Stages** (can be used as final images):
- **base**: Minimal Virgo 3 environment with SLURM support only
- **faircmakemodules**: base + FairCMakeModules installed
- **fairlogger**: faircmakemodules + FairLogger installed
- **fairmq**: fairlogger + FairMQ installed (complete FAIR stack)

Each build stage derives from the appropriate runtime stage, ensuring all BuildRequires dependencies are satisfied.

## Technical Details

- **Base OS**: Rocky Linux 8
- **SLURM User**: UID/GID 31002
- **Package Mirror**: http://cluster-mirror.hpc.gsi.de
- **Target Cluster**: Virgo 3

### FAIR Software Versions (configurable via build args)
- **FairCMakeModules**: v1.0.0 (default) - https://github.com/FairRootGroup/FairCMakeModules
- **FairLogger**: v1.11.1 (default) - https://github.com/FairRootGroup/FairLogger
- **FairMQ**: v1.9.0 (default) - https://github.com/FairRootGroup/FairMQ

All packages are built from source with full git metadata preserved for proper version detection.

## License

This project is licensed under the GNU General Public License v3.0 or later (GPL-3.0-or-later).
See the [LICENSES/GPL-3.0-or-later.txt](LICENSES/GPL-3.0-or-later.txt) file for details.
