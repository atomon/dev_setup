#!/usr/bin/env bash

# Personal Ubuntu Desktop bootstrap: Ubuntu 24.04+ on amd64.
set -Eeuo pipefail

readonly APT_KEYRINGS_DIR=/etc/apt/keyrings
readonly VSCODE_KEYRING="$APT_KEYRINGS_DIR/microsoft.gpg"
readonly VIVALDI_KEYRING="$APT_KEYRINGS_DIR/vivaldi.gpg"
readonly VSCODE_SOURCE=/etc/apt/sources.list.d/vscode.sources
readonly VIVALDI_SOURCE=/etc/apt/sources.list.d/vivaldi.list
readonly LEGACY_VSCODE_SOURCE=/etc/apt/sources.list.d/microsoft_vscode.list
readonly -a BASE_PACKAGES=(ca-certificates curl git gnupg gnome-sushi snapd vim)

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

is_deb_installed() {
    [[ $(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null || true) == installed ]]
}

is_snap_installed() {
    snap list "$1" >/dev/null 2>&1
}

require_supported_platform() {
    [[ -r /etc/os-release ]] || die 'Cannot identify the operating system.'
    # shellcheck disable=SC1091
    . /etc/os-release

    [[ ${ID:-} == ubuntu ]] || die 'This installer supports Ubuntu only.'
    dpkg --compare-versions "${VERSION_ID:-0}" ge 24.04 || \
        die 'Vivaldi requires Ubuntu 24.04 or newer.'
    [[ $(dpkg --print-architecture) == amd64 ]] || \
        die 'This installer requires amd64 because Vivaldi is installed by default.'
    (( EUID != 0 )) || die 'Run this script as the desktop user, not through sudo.'
}

install_apt_key() {
    local url=$1 destination=$2 armored_key binary_key
    armored_key=$(mktemp)
    binary_key=$(mktemp)

    if ! curl --fail --silent --show-error --location "$url" -o "$armored_key" ||
        ! gpg --batch --yes --dearmor --output "$binary_key" "$armored_key" ||
        ! sudo install -D -m 0644 "$binary_key" "$destination"; then
        rm -f "$armored_key" "$binary_key"
        return 1
    fi
    rm -f "$armored_key" "$binary_key"
}

write_apt_source() {
    sudo tee "$1" >/dev/null
}

install_snap_app() {
    local app=$1 conflicting_deb=${2:-}

    if is_snap_installed "$app"; then
        return
    fi
    if [[ -n $conflicting_deb ]] && is_deb_installed "$conflicting_deb"; then
        die "$app is already installed as the $conflicting_deb deb package; remove it before installing the Snap version."
    fi
    sudo snap install "$app"
}

install_base_packages() {
    sudo apt-get update
    sudo apt-get install -y "${BASE_PACKAGES[@]}"
}

configure_git_defaults() {
    git config --global --replace-all fetch.prune true
    git config --global --replace-all pull.rebase true
}

install_snap_apps() {
    # Slack's official Snap command does not require --classic. Do not install
    # a second package format when a deb installation already exists.
    install_snap_app slack slack-desktop
    install_snap_app discord discord
}

configure_vscode_repository() {
    # A Snap-installed VS Code and the Microsoft APT package should not coexist.
    is_snap_installed code && die 'VS Code is already installed as a Snap; remove it before using the Microsoft APT package.'

    install_apt_key 'https://packages.microsoft.com/keys/microsoft.asc' "$VSCODE_KEYRING"
    write_apt_source "$VSCODE_SOURCE" <<'EOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /etc/apt/keyrings/microsoft.gpg
EOF
    # This was the source-list filename managed by previous script versions.
    sudo rm -f "$LEGACY_VSCODE_SOURCE"
}

configure_vivaldi_repository() {
    install_apt_key 'https://repo.vivaldi.com/archive/linux_signing_key.pub' "$VIVALDI_KEYRING"
    write_apt_source "$VIVALDI_SOURCE" <<'EOF'
deb [arch=amd64 signed-by=/etc/apt/keyrings/vivaldi.gpg] https://repo.vivaldi.com/archive/deb/ stable main
EOF
}

install_apt_apps() {
    sudo install -d -m 0755 "$APT_KEYRINGS_DIR"
    configure_vscode_repository
    configure_vivaldi_repository
    sudo apt-get update
    sudo apt-get install -y code vivaldi-stable
}

verify_installation() {
    is_snap_installed slack || die 'Slack Snap is not installed.'
    is_snap_installed discord || die 'Discord Snap is not installed.'
    is_deb_installed code || die 'VS Code is not installed.'
    is_deb_installed vivaldi-stable || die 'Vivaldi is not installed.'
}

main() {
    require_supported_platform
    sudo -v
    install_base_packages
    configure_git_defaults
    install_snap_apps
    install_apt_apps
    verify_installation
    printf '✨ Installed all apps.\n'
}

main "$@"
