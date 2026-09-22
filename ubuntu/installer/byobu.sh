#!/usr/bin/env bash

# Install the Ubuntu packages.  Byobu's configuration remains per user under
# ~/.byobu and is deliberately not created or changed here.
set -Eeuo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

main() {
    local -a apt=(apt-get)

    command -v apt-get >/dev/null 2>&1 || die 'This installer requires apt-get.'
    if (( EUID != 0 )); then
        command -v sudo >/dev/null 2>&1 || die 'sudo is required to install system packages.'
        sudo -v
        apt=(sudo apt-get)
    fi
    "${apt[@]}" update
    "${apt[@]}" install -y tmux byobu
    command -v tmux >/dev/null 2>&1 || die 'tmux was not installed.'
    command -v byobu-tmux >/dev/null 2>&1 || die 'byobu-tmux was not installed.'
    tmux -V
    printf '%s\n' 'Byobu and tmux are installed system-wide.'
    printf '%s\n' 'Each user can configure Byobu independently in ~/.byobu/.'
}

main "$@"
