#!/bin/bash
# -------------------------------------------------------------------------
# Program: bootstrap-docker.sh
# Description: Quick one-liner to bootstrap Docker container from GitHub
# Context: Downloads and executes the full init-docker.sh installer
# Author: Greg Tate
# -------------------------------------------------------------------------
#
# USAGE:
#   curl -fsSL https://raw.githubusercontent.com/Greg-T8/Profiles/main/Linux/bootstrap-docker.sh | bash
#
# -------------------------------------------------------------------------

# Download and execute the full installer
INSTALLER_URL='https://raw.githubusercontent.com/Greg-T8/Profiles/main/Linux/init-docker.sh'

echo "[INFO] Downloading init-docker.sh installer..."
curl -fsSL "$INSTALLER_URL" | bash
