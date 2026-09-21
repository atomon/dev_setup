#!/usr/bin/env bash

# Install Ghostty from Ubuntu's repository when available, otherwise use the
# community .deb package documented by the Ghostty project for Ubuntu 24.04.
set -Eeuo pipefail

readonly GHOSTTY_UBUNTU_REPOSITORY='mkasberg/ghostty-ubuntu'
readonly GITHUB_API_URL="https://api.github.com/repos/${GHOSTTY_UBUNTU_REPOSITORY}/releases/latest"

WORK_DIR=''
DEFAULT_TERMINAL_TEMP=''

trap '[[ -z $WORK_DIR ]] || rm -rf -- "$WORK_DIR"; [[ -z $DEFAULT_TERMINAL_TEMP ]] || rm -f -- "$DEFAULT_TERMINAL_TEMP"' EXIT

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

latest_deb_url() {
    local architecture=$1 suffix release_json
    suffix="${architecture}_24.04"
    release_json=$(curl --fail --silent --show-error --location --retry 3 \
        --proto '=https' --proto-redir '=https' "$GITHUB_API_URL") || return

    # GitHub's release API contains an asset URL for each architecture. Read
    # only browser_download_url fields, never a lookalike URL in release notes.
    printf '%s\n' "$release_json" | sed -nE \
        "s#^[[:space:]]*\\\"browser_download_url\\\"[[:space:]]*:[[:space:]]*\\\"(https://github.com/${GHOSTTY_UBUNTU_REPOSITORY}/releases/download/[^\"[:space:]]+/ghostty_[^\"/_[:space:]]+_${suffix}\\.deb)\\\"[,]?[[:space:]]*\$#\\1#p" \
        | head -n 1
}

main() {
    local architecture deb_url deb_path config_dir terminal_list

    [[ -r /etc/os-release ]] || die 'Cannot identify the operating system.'
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ ${ID:-} == ubuntu ]] || die 'This installer supports Ubuntu only.'
    dpkg --compare-versions "${VERSION_ID:-0}" ge 24.04 || \
        die 'Ghostty requires Ubuntu 24.04 or newer.'
    architecture=$(dpkg --print-architecture)
    case $architecture in
        amd64|arm64) ;;
        *) die "Unsupported architecture: ${architecture} (supported: amd64, arm64)" ;;
    esac
    (( EUID != 0 )) || die 'Run this script as the desktop user, not through sudo.'
    sudo -v

    # Ghostty is in Ubuntu's own archive from 26.04 onward. Ubuntu 24.04 has
    # no official package; use the community package linked by Ghostty docs.
    if dpkg --compare-versions "$VERSION_ID" ge 26.04; then
        sudo apt-get update
        sudo apt-get install -y ghostty
    else
        printf '%s\n' 'Ubuntu 24.04 uses the community-built ghostty-ubuntu .deb package.' >&2
        printf '%s\n' 'See https://ghostty.org/docs/install/binary#debian-and-ubuntu for its trust model.' >&2
        deb_url=$(latest_deb_url "$architecture") || die 'Could not retrieve the latest Ghostty package URL.'
        [[ -n $deb_url ]] || die "No Ghostty package is available for Ubuntu 24.04 (${architecture})."

        WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ghostty.XXXXXX") || die 'Could not create a temporary directory.'
        deb_path="$WORK_DIR/${deb_url##*/}"
        printf 'Downloading %s\n' "${deb_url##*/}"
        curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' \
            --output "$deb_path" "$deb_url"
        sudo apt-get install -y "$deb_path"
    fi

    [[ $(dpkg-query -W -f='${db:Status-Status}' ghostty 2>/dev/null || true) == installed ]] || \
        die 'Ghostty package is not installed.'
    command -v ghostty >/dev/null 2>&1 || die 'Ghostty executable is not on PATH.'
    printf 'Ghostty is ready: %s\n' "$(ghostty --version)"

    if dpkg --compare-versions "$VERSION_ID" lt 25.04; then
        sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator \
            "$(command -v ghostty)" 60
        sudo update-alternatives --set x-terminal-emulator "$(command -v ghostty)"
    else
        config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
        terminal_list="$config_dir/ubuntu-xdg-terminals.list"
        mkdir -p -- "$config_dir"
        DEFAULT_TERMINAL_TEMP=$(mktemp "$config_dir/.ubuntu-xdg-terminals.XXXXXX") || \
            die 'Could not create the default-terminal settings file.'
        {
            printf '%s\n' 'com.mitchellh.ghostty.desktop'
            [[ ! -f $terminal_list ]] || grep -Fxv 'com.mitchellh.ghostty.desktop' "$terminal_list" || true
        } > "$DEFAULT_TERMINAL_TEMP"
        mv -- "$DEFAULT_TERMINAL_TEMP" "$terminal_list"
        DEFAULT_TERMINAL_TEMP=''
    fi
    printf '%s\n' 'Ghostty is now the default terminal.'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
