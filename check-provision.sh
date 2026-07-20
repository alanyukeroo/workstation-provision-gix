#!/usr/bin/env bash
#
# check-provision.sh
#
# Verifies that provision.sh's setup actually landed on this machine:
#   - Ubuntu 26.x
#   - ntuser account exists (in sudo, video, render groups)
#   - NVIDIA driver active
#   - CUDA toolkit installed
#   - VS Code installed
#
# Standalone — no sudo needed:
#   ./check-provision.sh
#
# Exits 0 if everything passes, 1 if anything is missing (handy for
# scripting a fleet-wide check across multiple machines).

set -uo pipefail

PASS="[OK]"
FAIL="[MISSING]"
FAILED=0

check() {
    local label="$1"
    local ok="$2"
    if [[ "$ok" -eq 0 ]]; then
        echo "$PASS  $label"
    else
        echo "$FAIL  $label"
        FAILED=1
    fi
}

echo "=== Provisioning check: $(date) ==="
echo "Host: $(hostname)"
echo ""

# ---------------------------------------------------------------------------
# OS version
# ---------------------------------------------------------------------------
if grep -q '^VERSION_ID="26' /etc/os-release 2>/dev/null; then
    check "Ubuntu 26.x ($(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"'))" 0
else
    check "Ubuntu 26.x (found: $(grep '^VERSION=' /etc/os-release 2>/dev/null | cut -d= -f2))" 1
fi

# ---------------------------------------------------------------------------
# ntuser account
# ---------------------------------------------------------------------------
TARGET_USER="ntuser"

if id "$TARGET_USER" &>/dev/null; then
    check "User '$TARGET_USER' exists" 0

    GROUPS_LIST=$(id -nG "$TARGET_USER")

    if grep -qw sudo <<< "$GROUPS_LIST"; then
        check "  -> in sudo group" 0
    else
        check "  -> in sudo group" 1
    fi

    if grep -qw video <<< "$GROUPS_LIST"; then
        check "  -> in video group" 0
    else
        check "  -> in video group" 1
    fi

    if grep -qw render <<< "$GROUPS_LIST"; then
        check "  -> in render group" 0
    else
        check "  -> in render group" 1
    fi
else
    check "User '$TARGET_USER' exists" 1
fi

# ---------------------------------------------------------------------------
# NVIDIA driver
# ---------------------------------------------------------------------------
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    check "NVIDIA driver active ($GPU_NAME, driver $DRIVER_VER)" 0
else
    check "NVIDIA driver active" 1
fi

# ---------------------------------------------------------------------------
# CUDA toolkit
# ---------------------------------------------------------------------------
if command -v nvcc &>/dev/null; then
    CUDA_VER=$(nvcc --version | grep -oP 'release \K[0-9.]+' || echo "unknown")
    check "CUDA toolkit installed (v$CUDA_VER)" 0
else
    check "CUDA toolkit installed" 1
fi

# ---------------------------------------------------------------------------
# VS Code
# ---------------------------------------------------------------------------
if command -v code &>/dev/null; then
    CODE_VER=$(code --version | head -1)
    check "VS Code installed (v$CODE_VER)" 0
else
    check "VS Code installed" 1
fi

echo ""
if [[ "$FAILED" -eq 0 ]]; then
    echo "=== All checks passed ==="
else
    echo "=== Some checks failed - see above ==="
fi

exit "$FAILED"
