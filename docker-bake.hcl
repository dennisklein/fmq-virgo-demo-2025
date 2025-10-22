# SPDX-FileCopyrightText: 2025 GSI Helmholtzzentrum für Schwerionenforschung GmbH
# SPDX-License-Identifier: GPL-3.0-or-later

# Docker Buildx Bake configuration for Virgo cluster images
# Usage: docker buildx bake [target]

# Default group builds everything
group "default" {
  targets = ["fairmq"]
}

# FAIR package repository - builds RPMs using mock
target "fair-repo" {
  context = "./packaging"
  dockerfile = "Dockerfile"
  target = "repo"
  tags = ["fair-repo:latest"]

  # Enable security.insecure for mock to work in containers
  entitlements = ["security.insecure"]

  output = ["type=docker"]

  # Pass version arguments to packaging build
  args = {
    FAIRCMAKEMODULES_VERSION = "1.0.0"
    FAIRLOGGER_VERSION = "1.11.1"
    FAIRMQ_VERSION = "1.9.0"
  }
}

# Virgo cluster image with FAIR software stack
target "fairmq" {
  context = "."
  dockerfile = "Dockerfile"
  target = "fairmq"
  tags = ["virgo-fairmq:latest"]

  # Ensure fair-repo is built first and made available as named context
  contexts = {
    fairrepo = "target:fair-repo"
  }

  output = ["type=docker"]
}
