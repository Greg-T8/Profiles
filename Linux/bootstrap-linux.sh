#!/bin/bash
# -------------------------------------------------------------------------
# Description   : Bootstrap Linux profile configuration from GitHub
# Context       : Remote Linux setup — download and run the installer
# Author        : Greg Tate & coding agent
# Last Modified : 2026-11-21
# Revision History:
#   2026-11-21 - Rename Linux bootstrap and clarify APT-based usage
# -------------------------------------------------------------------------
#
# USAGE:
#   curl -fsSL https://raw.githubusercontent.com/Greg-T8/Profiles/main/Linux/bootstrap-linux.sh | bash
#
# NOTE:
#   This script requires curl. On an APT-based distribution without curl,
#   install it with apt-get before running the bootstrap.
#
# -------------------------------------------------------------------------

# Download and execute the full installer
INSTALLER_URL='https://raw.githubusercontent.com/Greg-T8/Profiles/main/Linux/init-linux.sh'

echo "[INFO] Downloading init-linux.sh installer..."
curl -fsSL "$INSTALLER_URL" | bash
