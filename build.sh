#!/usr/bin/env bash
# build.sh - Automated Godot export script for Astryx
# Produces: builds/windows/Astryx.exe, builds/linux/Astryx.x86_64, builds/linux/Astryx.AppImage

set -euo pipefail

# --- Config ---
GODOT_VERSION="4.6.3.stable"
GODOT_CMD="flatpak run org.godotengine.Godot"
TEMPLATE_DIR="${HOME}/.var/app/org.godotengine.Godot/data/godot/export_templates/${GODOT_VERSION}"
TEMPLATE_URL="https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/builds"

# --- Colours ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()   { echo -e "${GREEN}[BUILD]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# --- 1. Download and install export templates if missing ---
install_templates() {
    if [[ -d "${TEMPLATE_DIR}" && -n "$(ls -A "${TEMPLATE_DIR}" 2>/dev/null)" ]]; then
        log "Export templates already installed at ${TEMPLATE_DIR}"
        return
    fi

    log "Export templates not found. Downloading Godot ${GODOT_VERSION} templates..."
    mkdir -p "${TEMPLATE_DIR}"

    local tpz_file="/tmp/godot_export_templates_${GODOT_VERSION}.tpz"

    if [[ ! -f "${tpz_file}" ]]; then
        curl -L --progress-bar -C - \
            -o "${tpz_file}" \
            "${TEMPLATE_URL}" || error "Template download failed. Check your internet connection."
    else
        log "Resuming existing partial download..."
        curl -L --progress-bar -C - \
            -o "${tpz_file}" \
            "${TEMPLATE_URL}"
    fi

    log "Extracting templates..."
    # .tpz is a renamed .zip; unzip into a temp dir then move contents
    local tmp_extract="/tmp/godot_templates_extract_$$"
    mkdir -p "${tmp_extract}"
    unzip -o "${tpz_file}" -d "${tmp_extract}" > /dev/null

    # Templates are nested inside templates/ subdir in the zip
    if [[ -d "${tmp_extract}/templates" ]]; then
        cp -r "${tmp_extract}/templates/." "${TEMPLATE_DIR}/"
    else
        cp -r "${tmp_extract}/." "${TEMPLATE_DIR}/"
    fi

    rm -rf "${tmp_extract}"
    log "Templates installed to ${TEMPLATE_DIR}"
}

# --- 2. Export Windows .exe ---
export_windows() {
    log "Exporting Windows build..."
    mkdir -p "${BUILD_DIR}/windows"
    ${GODOT_CMD} \
        --headless \
        --path "${PROJECT_DIR}" \
        --export-release "Windows Desktop" \
        "${BUILD_DIR}/windows/Astryx.exe" \
        2>&1 | grep -v "^$" || true

    if [[ -f "${BUILD_DIR}/windows/Astryx.exe" ]]; then
        local size
        size=$(du -sh "${BUILD_DIR}/windows/Astryx.exe" | cut -f1)
        log "Windows build done: ${BUILD_DIR}/windows/Astryx.exe (${size})"
    else
        error "Windows export failed — Astryx.exe not found."
    fi
}

# --- 3. Export Linux binary ---
export_linux() {
    log "Exporting Linux build..."
    mkdir -p "${BUILD_DIR}/linux"
    ${GODOT_CMD} \
        --headless \
        --path "${PROJECT_DIR}" \
        --export-release "Linux/X11" \
        "${BUILD_DIR}/linux/Astryx.x86_64" \
        2>&1 | grep -v "^$" || true

    if [[ -f "${BUILD_DIR}/linux/Astryx.x86_64" ]]; then
        chmod +x "${BUILD_DIR}/linux/Astryx.x86_64"
        local size
        size=$(du -sh "${BUILD_DIR}/linux/Astryx.x86_64" | cut -f1)
        log "Linux binary done: ${BUILD_DIR}/linux/Astryx.x86_64 (${size})"
    else
        error "Linux export failed — Astryx.x86_64 not found."
    fi
}

# --- 4. Package Linux as AppImage ---
build_appimage() {
    log "Building Linux AppImage..."

    local appimage_tool="${BUILD_DIR}/appimagetool-x86_64.AppImage"
    local appdir="${BUILD_DIR}/linux/Astryx.AppDir"

    # Download appimagetool if not present
    if [[ ! -f "${appimage_tool}" ]]; then
        log "Downloading appimagetool..."
        curl -L --progress-bar \
            -o "${appimage_tool}" \
            "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
        chmod +x "${appimage_tool}"
    fi

    # Build AppDir structure
    rm -rf "${appdir}"
    mkdir -p "${appdir}/usr/bin"
    mkdir -p "${appdir}/usr/share/applications"
    mkdir -p "${appdir}/usr/share/icons/hicolor/256x256/apps"

    # Copy binary
    cp "${BUILD_DIR}/linux/Astryx.x86_64" "${appdir}/usr/bin/astryx"

    # Desktop entry
    cat > "${appdir}/usr/share/applications/astryx.desktop" <<EOF
[Desktop Entry]
Name=Astryx
Comment=Space exploration game
Exec=astryx
Icon=astryx
Type=Application
Categories=Game;
EOF
    cp "${appdir}/usr/share/applications/astryx.desktop" "${appdir}/astryx.desktop"

    # Icon — use a placeholder if no icon exists in project
    local icon_src
    icon_src=$(find "${PROJECT_DIR}" -maxdepth 2 -name "*.png" | head -1)
    if [[ -n "${icon_src}" ]]; then
        cp "${icon_src}" "${appdir}/usr/share/icons/hicolor/256x256/apps/astryx.png"
        cp "${icon_src}" "${appdir}/astryx.png"
    fi

    # AppRun entry point
    cat > "${appdir}/AppRun" <<'EOF'
#!/bin/bash
exec "$(dirname "$(readlink -f "${0}")")/usr/bin/astryx" "$@"
EOF
    chmod +x "${appdir}/AppRun"

    # Build the AppImage
    ARCH=x86_64 "${appimage_tool}" "${appdir}" "${BUILD_DIR}/linux/Astryx.AppImage" 2>&1 || \
        warn "AppImage packaging failed — the raw .x86_64 binary is still usable."

    if [[ -f "${BUILD_DIR}/linux/Astryx.AppImage" ]]; then
        chmod +x "${BUILD_DIR}/linux/Astryx.AppImage"
        local size
        size=$(du -sh "${BUILD_DIR}/linux/Astryx.AppImage" | cut -f1)
        log "AppImage done: ${BUILD_DIR}/linux/Astryx.AppImage (${size})"
    fi
}

# --- 5. Build Linux shell installer ---
build_linux_installer() {
    log "Building Linux shell installer..."

    local installer="${BUILD_DIR}/linux/install-astryx.sh"

    cat > "${installer}" <<'INSTALLER_EOF'
#!/usr/bin/env bash
# Astryx Linux Installer
set -euo pipefail

INSTALL_DIR="/opt/astryx"
BIN_LINK="/usr/local/bin/astryx"
DESKTOP_FILE="/usr/share/applications/astryx.desktop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="${SCRIPT_DIR}/Astryx.x86_64"

# Check if binary exists
if [[ ! -f "${BINARY}" ]]; then
    echo "Error: Astryx.x86_64 not found in the same directory as this installer."
    exit 1
fi

# Require root for system-wide install
if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with sudo for a system-wide install:"
    echo "  sudo bash install-astryx.sh"
    echo ""
    echo "Or install locally (no sudo)? [y/N]: "
    read -r ans
    if [[ "${ans}" =~ ^[Yy]$ ]]; then
        INSTALL_DIR="${HOME}/.local/opt/astryx"
        BIN_LINK="${HOME}/.local/bin/astryx"
        DESKTOP_FILE="${HOME}/.local/share/applications/astryx.desktop"
    else
        exit 1
    fi
fi

echo "Installing Astryx to ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"
cp "${BINARY}" "${INSTALL_DIR}/astryx"
chmod +x "${INSTALL_DIR}/astryx"

# Launcher symlink
mkdir -p "$(dirname "${BIN_LINK}")"
ln -sf "${INSTALL_DIR}/astryx" "${BIN_LINK}"

# Desktop entry
mkdir -p "$(dirname "${DESKTOP_FILE}")"
cat > "${DESKTOP_FILE}" <<DESK
[Desktop Entry]
Name=Astryx
Comment=Space exploration game
Exec=${INSTALL_DIR}/astryx
Icon=applications-games
Type=Application
Categories=Game;
Terminal=false
DESK

echo ""
echo "Astryx installed successfully."
echo "  Binary : ${INSTALL_DIR}/astryx"
echo "  Launcher: ${BIN_LINK}"
echo "  Desktop entry: ${DESKTOP_FILE}"
echo ""
echo "Run with: astryx"
INSTALLER_EOF

    chmod +x "${installer}"
    log "Linux installer created: ${installer}"
}

# --- Main ---
main() {
    log "=== Astryx Build Script ==="
    log "Project: ${PROJECT_DIR}"
    log "Godot:   ${GODOT_VERSION}"

    install_templates
    export_windows
    export_linux
    build_appimage
    build_linux_installer

    echo ""
    log "=== Build Complete ==="
    echo ""
    echo "  Windows:         builds/windows/Astryx.exe"
    echo "  Linux binary:    builds/linux/Astryx.x86_64"
    echo "  Linux AppImage:  builds/linux/Astryx.AppImage"
    echo "  Linux installer: builds/linux/install-astryx.sh"
    echo ""
}

main "$@"
