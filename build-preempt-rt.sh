#!/usr/bin/env bash
#
# build-preempt-rt.sh
#
# Builds and installs the PREEMPT_RT patched kernel for Jetson Orin Nano.
#
# Usage:
#   ./build-preempt-rt.sh <install-path>
#
# Example:
#   ./build-preempt-rt.sh ~/Documents/linux-source
#
# The script expects:
#   <install-path>/Linux_for_Tegra/source/  to exist with kernel sources.

set -euo pipefail

# ─── Colors & helpers ────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_step()    { echo -e "\n${BOLD}${GREEN}▶ STEP: $*${NC}"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }

confirm_step() {
    local msg="$1"
    echo ""
    echo -e "${BOLD}${YELLOW}─────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}${YELLOW}  $msg${NC}"
    echo -e "${BOLD}${YELLOW}─────────────────────────────────────────────────${NC}"
    read -rp "Proceed? [y/N] " answer
    case "$answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *)
            log_warn "Aborted by user."
            exit 0
            ;;
    esac
}

# ─── Argument validation ─────────────────────────────────────────────────────

if [[ $# -ne 1 ]]; then
    log_error "Usage: $0 <install-path>"
    log_info  "Example: $0 ~/Documents/linux-source"
    exit 1
fi

INSTALL_PATH="$(realpath "$1")"
SOURCE_DIR="${INSTALL_PATH}/Linux_for_Tegra/source"

if [[ ! -d "$SOURCE_DIR" ]]; then
    log_error "Source directory not found: ${SOURCE_DIR}"
    log_info  "Make sure the Jetson Linux sources are extracted at the install path."
    exit 1
fi

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       PREEMPT_RT Kernel Build & Install           ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
log_info "Install path : ${INSTALL_PATH}"
log_info "Source dir    : ${SOURCE_DIR}"
echo ""

# ─── Step 1: Backup original kernel image ────────────────────────────────────

log_step "1/6 — Backup original /boot/Image"
if [[ -f /boot/Image.backup ]]; then
    log_warn "/boot/Image.backup already exists, it will be overwritten."
fi
log_info "This creates /boot/Image.backup so you can revert if needed."

confirm_step "Back up /boot/Image -> /boot/Image.backup?"
sudo cp /boot/Image /boot/Image.backup
log_success "Backup created: /boot/Image.backup"

# ─── Step 2: Enable RT configuration ─────────────────────────────────────────

log_step "2/6 — Enable RT kernel configuration"
log_info "Running generic_rt_build.sh to patch the kernel config for PREEMPT_RT."

confirm_step "Enable RT configuration?"
cd "$SOURCE_DIR"
log_info "Working directory: $(pwd)"
./generic_rt_build.sh "enable"
log_success "RT configuration enabled."

# ─── Step 3: Build kernel and in-tree modules ────────────────────────────────

log_step "3/6 — Build kernel and in-tree modules"
log_info "This removes any stale Image artifact and rebuilds the kernel."

confirm_step "Build the kernel?"
cd "$SOURCE_DIR"

IMAGE_PATH="${SOURCE_DIR}/kernel/kernel-jammy-src/arch/arm64/boot/Image"
if [[ -f "$IMAGE_PATH" ]]; then
    log_info "Removing stale Image: ${IMAGE_PATH}"
    rm -rf "$IMAGE_PATH"
fi

log_info "Starting kernel build (make -C kernel) ..."
make -C kernel
log_success "Kernel build complete."

# ─── Step 4: Install kernel and in-tree modules ──────────────────────────────

log_step "4/6 — Install kernel and in-tree modules"
log_info "This installs the built Image and modules to your system."

confirm_step "Install kernel and in-tree modules (sudo)?"
cd "$SOURCE_DIR"
sudo make install -C kernel
log_success "Kernel and in-tree modules installed."

# ─── Step 5: Build out-of-tree modules ───────────────────────────────────────

log_step "5/6 — Build out-of-tree modules"
log_info "Cleans previous build artifacts, then builds out-of-tree modules."

confirm_step "Build out-of-tree modules (sudo)?"
cd "$SOURCE_DIR"

log_info "Cleaning previous build ..."
sudo make clean

export KERNEL_HEADERS="${SOURCE_DIR}/kernel/kernel-jammy-src/"
export IGNORE_CC_MISMATCH=1
export IGNORE_PREEMPT_RT_PRESENCE=1

log_info "Building out-of-tree modules ..."
sudo -E make modules
log_success "Out-of-tree modules built."

# ─── Step 6: Install out-of-tree modules ─────────────────────────────────────

log_step "6/6 — Install out-of-tree modules"
log_info "Installs the out-of-tree modules into your system."

confirm_step "Install out-of-tree modules (sudo)?"
cd "$SOURCE_DIR"

export KERNEL_HEADERS="${SOURCE_DIR}/kernel/kernel-jammy-src/"
export IGNORE_CC_MISMATCH=1
export IGNORE_PREEMPT_RT_PRESENCE=1

sudo -E make modules_install
log_success "Out-of-tree modules installed."

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║           All steps completed!                    ║${NC}"
echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}${RED}Don't forget to add fallback entry in extlinux.conf!!!${NC}"
