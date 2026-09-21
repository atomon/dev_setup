#!/usr/bin/env bash

# Install the current patch release in the Node.js 24 LTS line with nvm.
set -Eeuo pipefail

readonly INSTALLER_NVM_RELEASE='0.40.7'
readonly INSTALLER_NODE_MAJOR='24'
readonly INSTALLER_NVM_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v${INSTALLER_NVM_RELEASE}/install.sh"

NVM_INSTALLER=''

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    local status=$?
    [[ -z $NVM_INSTALLER ]] || rm -f -- "$NVM_INSTALLER"
    return "$status"
}

trap cleanup EXIT

require_unprivileged_user() {
    (( EUID != 0 )) || die 'Run this script as the target user, without sudo.'
    [[ -n ${HOME:-} && -d $HOME ]] || die 'A valid HOME directory is required.'
}

configure_nvm_directory() {
    if [[ -z ${NVM_DIR:-} ]]; then
        if [[ -n ${XDG_CONFIG_HOME:-} ]]; then
            NVM_DIR="$XDG_CONFIG_HOME/nvm"
        else
            NVM_DIR="$HOME/.nvm"
        fi
    fi
    export NVM_DIR
}

install_prerequisites() {
    command -v apt-get >/dev/null 2>&1 || die 'This installer requires apt-get.'
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
}

install_nvm() {
    NVM_INSTALLER=$(mktemp) || die 'Could not create a temporary file for the nvm installer.'

    curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 \
        --output "$NVM_INSTALLER" "$INSTALLER_NVM_URL"
    bash "$NVM_INSTALLER"
}

load_nvm() {
    [[ -s "$NVM_DIR/nvm.sh" ]] || die "nvm was not installed at $NVM_DIR."
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
    command -v nvm >/dev/null 2>&1 || die 'nvm could not be loaded.'
}

install_node() {
    # This installs or updates to the newest available patch release in v24.
    nvm install "$INSTALLER_NODE_MAJOR"
    nvm alias default "$INSTALLER_NODE_MAJOR"
    nvm use default
}

verify_installation() {
    local node_version npm_version
    node_version=$(node --version)
    npm_version=$(npm --version)
    [[ $node_version == v${INSTALLER_NODE_MAJOR}.* ]] || \
        die "Expected Node.js v${INSTALLER_NODE_MAJOR}.x, got $node_version."
    printf 'Node.js %s and npm %s are ready (nvm %s; default: Node.js %s).\n' \
        "$node_version" "$npm_version" "$INSTALLER_NVM_RELEASE" "$INSTALLER_NODE_MAJOR"
}

main() {
    require_unprivileged_user
    configure_nvm_directory
    install_prerequisites
    install_nvm
    load_nvm
    install_node
    verify_installation
}

main "$@"
