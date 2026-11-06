#!/usr/bin/env bash

# Install tmux-agent-sidebar without sudo. Everything it owns lives below the
# invoking user's home directory, so it is safe to use on a shared host.
set -Eeuo pipefail

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SIDEBAR_VERSION='v0.13.0'
readonly SIDEBAR_COMMIT='d89fe2025cd3f7149b0c8af9d48f15eab5fc2a3a'
readonly SIDEBAR_REPOSITORY='https://github.com/hiroppy/tmux-agent-sidebar.git'
readonly SIDEBAR_RELEASE_BASE="https://github.com/hiroppy/tmux-agent-sidebar/releases/download/${SIDEBAR_VERSION}"
readonly SIDEBAR_LINUX_X86_64_SHA256='e06495a327a074c6e38c3d7697f061bdb6d19f04b67d9fc30137d34d9318e344'
readonly SIDEBAR_LINUX_AARCH64_SHA256='3e3937468ca2725b5f7fa632ae4c71c3beb453cbc429745d8878f0855098a09a'
readonly SIDEBAR_DARWIN_X86_64_SHA256='a5e3a34be15967322b0a217caeabadda0759a9b08090773278aaeaf11b53f2af'
readonly SIDEBAR_DARWIN_AARCH64_SHA256='61c7faf1b37ae72614889914ce016378b0e48461d74d6faf360193ed648c23a3'

source "$SCRIPT_DIR/utils/byobu_common.sh"

# macOS ships shasum instead of sha256sum.
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum -- "$1"
    else
        shasum -a 256 -- "$1"
    fi | awk '{ print $1 }'
}

main() {
    local data_home install_dir config_file binary real_binary binary_temp binary_name binary_sha256
    local tmux_version tmux_major tmux_minor

    (( EUID != 0 )) || die 'Run this installer as the target user, without sudo.'
    [[ -n ${HOME:-} && -d $HOME ]] || die 'A valid HOME directory is required.'
    require_commands byobu-tmux curl git tmux
    command -v sha256sum >/dev/null 2>&1 || require_commands shasum

    tmux_version=$(tmux -V)
    [[ $tmux_version =~ ([0-9]+)\.([0-9]+) ]] || die "Cannot determine tmux version: ${tmux_version}"
    tmux_major=${BASH_REMATCH[1]}
    tmux_minor=${BASH_REMATCH[2]}
    (( tmux_major > 3 || (tmux_major == 3 && tmux_minor >= 0) )) || \
        die "tmux-agent-sidebar requires tmux 3.0 or newer (found ${tmux_version})."

    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64|Linux/amd64)
            binary_name='tmux-agent-sidebar-linux-x86_64'
            binary_sha256=$SIDEBAR_LINUX_X86_64_SHA256
            ;;
        Linux/aarch64|Linux/arm64)
            binary_name='tmux-agent-sidebar-linux-aarch64'
            binary_sha256=$SIDEBAR_LINUX_AARCH64_SHA256
            ;;
        Darwin/x86_64)
            binary_name='tmux-agent-sidebar-darwin-x86_64'
            binary_sha256=$SIDEBAR_DARWIN_X86_64_SHA256
            ;;
        Darwin/arm64|Darwin/aarch64)
            binary_name='tmux-agent-sidebar-darwin-aarch64'
            binary_sha256=$SIDEBAR_DARWIN_AARCH64_SHA256
            ;;
        *) die "Unsupported platform: $(uname -s) $(uname -m) (supported: Linux and macOS on x86_64 or arm64)" ;;
    esac

    data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
    install_dir="$data_home/tmux-agent-sidebar"
    config_file="$HOME/.byobu/.tmux.conf"
    binary="$install_dir/bin/tmux-agent-sidebar"
    real_binary="$binary.real"
    binary_temp=''
    trap '[[ -z ${binary_temp:-} ]] || rm -f -- "$binary_temp"' EXIT
    mkdir -p -- "$data_home"

    install_plugin tmux-agent-sidebar "$SIDEBAR_VERSION" "$SIDEBAR_COMMIT" "$SIDEBAR_REPOSITORY" "$data_home"

    # A binary that already matches the pinned checksum is not downloaded again.
    mkdir -p -- "${binary%/*}"
    if [[ ! -x $real_binary || $(sha256_of "$real_binary") != "$binary_sha256" ]]; then
        binary_temp=$(mktemp "${binary%/*}/.tmux-agent-sidebar.XXXXXX") || die 'Could not create a temporary sidebar binary.'
        curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 \
            --output "$binary_temp" "$SIDEBAR_RELEASE_BASE/$binary_name"
        [[ $(sha256_of "$binary_temp") == "$binary_sha256" ]] || \
            die 'tmux-agent-sidebar binary checksum verification failed.'
        chmod 0755 -- "$binary_temp"
        mv -- "$binary_temp" "$real_binary"
        binary_temp=''
    fi

    # Every agent integration reaches the binary through hook.sh as
    # "bin/tmux-agent-sidebar hook ...", and only that subcommand creates
    # /tmp/tmux-agent-activity_<pane>.log with agent commands in it. Run it with
    # a private umask; everything else keeps the caller's umask.
    binary_temp=$(mktemp "${binary%/*}/.tmux-agent-sidebar.XXXXXX") || die 'Could not create the sidebar wrapper.'
    cat > "$binary_temp" <<EOF
#!/bin/sh
[ "\${1:-}" != hook ] || umask 077
exec '$real_binary' "\$@"
EOF
    chmod 0755 -- "$binary_temp"
    mv -- "$binary_temp" "$binary"
    binary_temp=''
    # The trailing slash makes find descend into macOS's /tmp -> /private/tmp symlink.
    find /tmp/ -maxdepth 1 -type f -name 'tmux-agent-activity_*.log' -user "$(id -u)" -exec chmod 0600 {} +

    write_managed_block "$config_file" tmux-agent-sidebar <<EOF
set -g @sidebar_auto_create on
set -g @sidebar_bottom_height 20
set -g @sidebar_notifications off
set -g @agent-sidebar-default-agent codex
set -g @agent_sidebar_dir '$install_dir'
run-shell '$install_dir/tmux-agent-sidebar.tmux'
EOF

    if [[ -n ${TMUX:-} ]]; then
        tmux source-file "$config_file"
    fi
    printf '%s\n' "tmux-agent-sidebar ${SIDEBAR_VERSION} is installed at ${install_dir}."
    printf '%s\n' 'Agent activity logs under /tmp are created readable only by you.'
    printf '%s\n' 'Start Byobu with byobu-tmux, then use Alt-a e (or F12 e) to toggle the sidebar.'
    printf '%s\n' 'Configure agent integrations separately with installer/tmux_agent_sidebar_hooks.sh.'
}

main "$@"
