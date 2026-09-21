#!/usr/bin/env bash

set -Eeuo pipefail

readonly PYTHON_VERSION="${PYTHON_VERSION:-3.13}"
readonly LOCAL_BIN="$HOME/.local/bin"
readonly BASHRC="$HOME/.bashrc"
readonly UV_BIN="$LOCAL_BIN/uv"
readonly UV_INSTALL_URL=https://astral.sh/uv/install.sh

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

ensure_bashrc_line() {
    local line=$1
    touch "$BASHRC"
    grep -Fqx -- "$line" "$BASHRC" || printf '%s\n' "$line" >> "$BASHRC"
}

find_uv() {
    if command -v uv >/dev/null 2>&1; then
        command -v uv
        return
    fi
    if [[ -x "$UV_BIN" ]]; then
        printf '%s\n' "$UV_BIN"
        return
    fi
    return 1
}

ensure_curl() {
    if ! command -v curl >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl
    fi
}

install_uv() {
    # Keep shell configuration under this installer's explicit, idempotent control.
    ensure_curl
    curl -LsSf "$UV_INSTALL_URL" | env UV_NO_MODIFY_PATH=1 sh
    [[ -x "$UV_BIN" ]] || die "uv was not installed at $UV_BIN."
}

configure_user_path() {
    ensure_bashrc_line 'export PATH="$HOME/.local/bin:$PATH"'
    export PATH="$LOCAL_BIN:$PATH"
}

install_python() {
    local uv_bin=$1
    "$uv_bin" python install "$PYTHON_VERSION"
    "$uv_bin" --version
    "$uv_bin" python find "$PYTHON_VERSION"
}

main() {
    local uv_bin
    if ! uv_bin=$(find_uv); then
        install_uv
        uv_bin=$UV_BIN
    fi

    configure_user_path
    install_python "$uv_bin"
    printf '✨ Python %s environment is ready.\n' "$PYTHON_VERSION"
}

main "$@"
