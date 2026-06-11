#!/bin/bash
set -euo pipefail

# Deploy a single pacman package to a running pi-Stomp device by building it
# on-device with makepkg and installing the result. This is the pacman-era
# equivalent of the old pi-stomp/deploy.sh "scp the files" workflow.
#
# Usage:
#   ./deploy-pkg.sh pi-stomp                      # build from git (branch in PKGBUILD)
#   ./deploy-pkg.sh ../pi-stomp                    # build from local source tree
#   ./deploy-pkg.sh pi-stomp --source ../pi-stomp # same, explicit
#   ./deploy-pkg.sh ../mod-ui                      # auto-detects mod-ui
#
# The PKGBUILDs live in pkgbuilds/<name>/ and define the canonical build.
# Passing a directory path as the first argument auto-detects the package name
# from the directory basename (pi-stomp, mod-ui, pistomp-recovery) and implies
# --source from that path.
#
# Local-source deploys rely on the PKGBUILD honoring PISTOMP_DEPLOY: when set,
# the PKGBUILD builds from ./$pkgname (rsynced next to it) instead of fetching
# git. The source directory name is always $pkgname, so this script needs no
# PKGBUILD parsing or rewriting.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGBUILDS_DIR="${SCRIPT_DIR}/pkgbuilds"
DEVICE="${PISTOMP_HOST:-pistomp.local}"
DEVICE_USER="${PISTOMP_USER:-pistomp}"
REMOTE_TMP="/tmp/deploy-pkg"

# Directory names that map to known packages
declare -A REPO_PKG_MAP=(
    [pi-stomp]=pi-stomp
    [mod-ui]=mod-ui
    [pistomp-recovery]=pistomp-recovery
)

usage() {
    echo "Usage: $0 <package | path> [--source <path>] [--host <host>] [--user <user>]"
    echo ""
    echo "If the first argument is a directory (e.g. ../pi-stomp), the package"
    echo "name is derived from the directory basename and --source is implied."
    echo ""
    echo "Packages:"
    ls -1 "${PKGBUILDS_DIR}" | sed 's/^/  /'
    echo ""
    echo "Options:"
    echo "  --source <path>  Use a local source tree instead of git clone"
    echo "  --host <host>    Device hostname (default: \$PISTOMP_HOST or pistomp.local)"
    echo "  --user <user>    Device username (default: \$PISTOMP_USER or pistomp)"
    exit 1
}

PKG=""
LOCAL_SOURCE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            LOCAL_SOURCE="$2"
            shift 2
            ;;
        --host)
            DEVICE="$2"
            shift 2
            ;;
        --user)
            DEVICE_USER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [[ -n "$PKG" ]]; then
                echo "ERROR: unexpected argument: $1" >&2
                usage
            fi
            PKG="$1"
            shift
            ;;
    esac
done

[[ -z "${PKG}" ]] && usage

# If PKG is a directory path, auto-detect package name and imply --source
if [[ -d "${PKG}" ]]; then
    LOCAL_SOURCE="$(cd "${PKG}" && pwd)"
    DIR_NAME="$(basename "${LOCAL_SOURCE}")"
    if [[ -n "${REPO_PKG_MAP[${DIR_NAME}]+x}" ]]; then
        PKG="${REPO_PKG_MAP[${DIR_NAME}]}"
    elif [[ -d "${PKGBUILDS_DIR}/${DIR_NAME}" ]]; then
        PKG="${DIR_NAME}"
    else
        echo "ERROR: directory basename '${DIR_NAME}' does not match a known package" >&2
        echo "Known: ${!REPO_PKG_MAP[*]} $(ls -1 "${PKGBUILDS_DIR}")" >&2
        exit 1
    fi
    echo "==> Auto-detected package: ${PKG} (from ${DIR_NAME}/)"
fi

PKG_DIR="${PKGBUILDS_DIR}/${PKG}"
if [[ ! -d "${PKG_DIR}" ]]; then
    echo "ERROR: no PKGBUILD directory for '${PKG}' in ${PKGBUILDS_DIR}" >&2
    echo "Available packages:" >&2
    ls -1 "${PKGBUILDS_DIR}" | sed 's/^/  /' >&2
    exit 1
fi

if [[ -n "${LOCAL_SOURCE}" ]]; then
    LOCAL_SOURCE="$(cd "${LOCAL_SOURCE}" && pwd)"
    if [[ ! -d "${LOCAL_SOURCE}" ]]; then
        echo "ERROR: source directory does not exist: ${LOCAL_SOURCE}" >&2
        exit 1
    fi
    # The PKGBUILD must understand local-source deploys (build from ./$pkgname
    # when PISTOMP_DEPLOY is set) — otherwise makepkg would silently ignore the
    # rsynced tree and clone from git instead.
    if ! grep -q 'PISTOMP_DEPLOY' "${PKG_DIR}/PKGBUILD"; then
        echo "ERROR: ${PKG}'s PKGBUILD does not support local-source deploy" >&2
        echo "       (it must build from \$pkgname when PISTOMP_DEPLOY is set)." >&2
        echo "       Deploy from git instead: $0 ${PKG}" >&2
        exit 1
    fi
fi

SSH_HOST="${DEVICE_USER}@${DEVICE}"

echo "==> Deploying ${PKG} to ${SSH_HOST}"

# ---------- prepare remote directory ----------

echo "==> Preparing remote build directory..."
ssh "${SSH_HOST}" "rm -rf ${REMOTE_TMP} && mkdir -p ${REMOTE_TMP}"

# ---------- copy PKGBUILD ----------

echo "==> Copying PKGBUILD..."
scp -r "${PKG_DIR}"/* "${SSH_HOST}:${REMOTE_TMP}/"

# ---------- copy local source tree if provided ----------
#
# The source directory name is always $pkgname (the PKGBUILD's source=("$pkgname")
# in deploy mode), so no PKGBUILD parsing or rewriting is needed.

DEPLOY_ENV=""
DEPLOY_VER=""
if [[ -n "${LOCAL_SOURCE}" ]]; then
    echo "==> Copying local source tree (${LOCAL_SOURCE}) as '${PKG}'..."
    rsync -az --delete \
        --exclude='.git' --exclude='.venv' \
        --exclude='__pycache__' --exclude='node_modules' \
        "${LOCAL_SOURCE}/" "${SSH_HOST}:${REMOTE_TMP}/${PKG}/"
    # Throwaway version: 0.dev<UTC timestamp>. The 0.dev prefix always sorts
    # *under* any real release (a numeric version segment outranks the alpha
    # 'dev'), so a later `pacman -Syu` supersedes the dev build. The timestamp
    # keeps successive dev builds monotonic. Computed here (once) rather than in
    # the PKGBUILD so it stays stable across makepkg's repeated PKGBUILD sourcing.
    # PISTOMP_DEPLOY both flags deploy mode (non-empty) and carries the version.
    DEPLOY_VER="0.dev$(date -u +%Y%m%d%H%M%S)"
    DEPLOY_ENV="env PISTOMP_DEPLOY=${DEPLOY_VER} "
fi

# ---------- build on device ----------

echo "==> Building ${PKG} on device (this may take a few minutes)..."

ssh "${SSH_HOST}" bash -s <<REMOTE_SCRIPT
set -e

# Ensure the unprivileged build user exists (08-cleanup.sh removes it from the
# shipped image, so recreate it here). makepkg refuses to run as root.
if ! id builduser &>/dev/null; then
    sudo useradd -m -s /bin/bash builduser
    echo "builduser ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/builduser >/dev/null
fi

cd ${REMOTE_TMP}
sudo chown -R builduser:builduser ${REMOTE_TMP}

# makepkg -s installs any missing makedepends itself and treats already-installed
# packages (including our out-of-repo ones like pistomp-python311) as satisfied,
# so no manual pacman -S step is needed. PISTOMP_DEPLOY (when set) tells the
# PKGBUILD to build from the rsynced ./${PKG} tree instead of cloning git.
echo "==> Running makepkg..."
sudo -u builduser ${DEPLOY_ENV}makepkg -s --noconfirm

PKGFILE=\$(ls *.pkg.tar.* 2>/dev/null | head -1)
if [[ -z "\${PKGFILE}" ]]; then
    echo "ERROR: no package file found after build" >&2
    exit 1
fi
echo "==> Installing \${PKGFILE}..."
sudo pacman -U --noconfirm "\${PKGFILE}"

echo "==> Package installed: \${PKGFILE}"
echo "    Artifacts left in ${REMOTE_TMP}"
REMOTE_SCRIPT

echo ""
echo "==> Done! ${PKG} deployed to ${DEVICE}"
if [[ -n "${LOCAL_SOURCE}" ]]; then
    echo "    (installed as ${DEPLOY_VER}; any real release supersedes it on the"
    echo "     next pacman -Syu. Rebuild from git — '$0 ${PKG}' — for a proper version.)"
fi

# ---------- restart the relevant service ----------

declare -A PKG_SERVICE_MAP=(
    [pi-stomp]=mod-ala-pi-stomp
    [mod-ui]=mod-ui
    [mod-host-pistomp]=mod-host
    [pistomp-recovery]=pistomp-recovery
    [jack2-pistomp]=jack
    [lcd-splash]=pistomp-lcd-splash
)

SERVICE="${PKG_SERVICE_MAP[${PKG}]:-}"
if [[ -n "${SERVICE}" ]]; then
    echo "==> Restarting ${SERVICE}..."
    ssh "${SSH_HOST}" "sudo systemctl restart ${SERVICE}" || true
    sleep 2
    if ssh "${SSH_HOST}" "sudo systemctl is-active --quiet ${SERVICE}"; then
        echo "==> ${SERVICE} is running"
    else
        echo "WARNING: ${SERVICE} failed to start. Check with:" >&2
        echo "  ssh ${SSH_HOST} sudo systemctl status ${SERVICE}" >&2
        ssh "${SSH_HOST}" "sudo systemctl status ${SERVICE}" || true
    fi
fi
