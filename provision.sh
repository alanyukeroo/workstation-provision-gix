#!/usr/bin/env bash
#
# provision-robot-workstation.sh
#
# Post-install provisioning script for machines already running
# Ubuntu 26.04 LTS (Resolute Raccoon). Sets up:
#   0. The ntuser login account (password: robot1234), if it doesn't exist
#   1. NVIDIA GPU driver
#   2. CUDA toolkit
#   3. Visual Studio Code
#
# Run locally on each fresh machine, logged in as whatever admin account
# the image ships with, using sudo:
#   sudo ./provision-robot-workstation.sh
#
# Idempotent — safe to re-run; each step checks whether it's already done.
# NOTE: this script creates a local account with a hardcoded password
# (ntuser / robot1234). That's fine for an internal lab image, but don't
# reuse this script or password on anything internet-facing.

set -euo pipefail

LOG_FILE="/var/log/provision-robot-workstation.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Provisioning started: $(date) ==="

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo. Try: sudo $0"
    exit 1
fi

TARGET_USER="ntuser"
TARGET_PASS="robot1234"

if ! grep -q '^VERSION_ID="26' /etc/os-release; then
    echo "WARNING: this doesn't look like Ubuntu 26.x. Found:"
    grep '^VERSION=' /etc/os-release
    read -rp "Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

NEEDS_REBOOT=0

# ---------------------------------------------------------------------------
# 0.5 Ensure the ntuser login account exists
# ---------------------------------------------------------------------------
if id "$TARGET_USER" &>/dev/null; then
    echo "User $TARGET_USER already exists, leaving account as-is."
else
    echo "--- Creating login user $TARGET_USER ---"
    useradd -m -s /bin/bash "$TARGET_USER"
    echo "${TARGET_USER}:${TARGET_PASS}" | chpasswd
    usermod -aG sudo "$TARGET_USER"
    echo "$TARGET_USER created and added to the sudo group."
fi

# ---------------------------------------------------------------------------
# 1. Base update + tooling
# ---------------------------------------------------------------------------
echo "--- Updating package lists ---"
apt update
apt -y upgrade

echo "--- Installing base tooling ---"
apt install -y build-essential curl wget gnupg ca-certificates software-properties-common

# ---------------------------------------------------------------------------
# 2. NVIDIA GPU driver
# ---------------------------------------------------------------------------
echo "--- Checking for existing NVIDIA driver ---"
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    echo "NVIDIA driver already active:"
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
else
    echo "--- Installing recommended NVIDIA driver ---"
    apt install -y ubuntu-drivers-common
    ubuntu-drivers install
    NEEDS_REBOOT=1
fi

# ---------------------------------------------------------------------------
# 3. CUDA toolkit
# ---------------------------------------------------------------------------
echo "--- Installing CUDA toolkit ---"
if ! command -v nvcc &>/dev/null; then
    apt install -y nvidia-cuda-toolkit
else
    echo "CUDA toolkit already installed: $(nvcc --version | tail -1)"
fi

# Make sure ntuser can access the GPU devices without re-logging in as root
usermod -aG video,render "$TARGET_USER" || true

# ---------------------------------------------------------------------------
# 4. Visual Studio Code
# ---------------------------------------------------------------------------
echo "--- Installing VS Code ---"
if ! command -v code &>/dev/null; then
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
    install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
    echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        > /etc/apt/sources.list.d/vscode.list
    rm -f /tmp/packages.microsoft.gpg
    apt update
    apt install -y code
else
    echo "VS Code already installed: $(code --version | head -1)"
fi

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Provisioning complete: $(date) ==="
echo "User:        $TARGET_USER"
echo "OS:          $(grep PRETTY_NAME /etc/os-release | cut -d= -f2)"
if command -v nvidia-smi &>/dev/null; then
    echo "GPU driver:  $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 'installed, reboot required to load')"
fi
if command -v code &>/dev/null; then
    echo "VS Code:     $(code --version | head -1)"
fi

if [[ "$NEEDS_REBOOT" -eq 1 ]]; then
    echo ""
    echo "!!! A REBOOT IS REQUIRED to load the new NVIDIA kernel module. !!!"
    echo "Run: sudo reboot"
fi
