#!/usr/bin/env bash

# Install tmux-agent-sidebar without sudo. Everything it owns lives below the
# invoking user's home directory, so it is safe to use on a shared host.
set -Eeuo pipefail

readonly SIDEBAR_VERSION='v0.13.0'
readonly SIDEBAR_COMMIT='d89fe2025cd3f7149b0c8af9d48f15eab5fc2a3a'
readonly SIDEBAR_REPOSITORY='https://github.com/hiroppy/tmux-agent-sidebar.git'
readonly SIDEBAR_RELEASE_BASE="https://github.com/hiroppy/tmux-agent-sidebar/releases/download/${SIDEBAR_VERSION}"
readonly SIDEBAR_X86_64_SHA256='e06495a327a074c6e38c3d7697f061bdb6d19f04b67d9fc30137d34d9318e344'
readonly SIDEBAR_AARCH64_SHA256='3e3937468ca2725b5f7fa632ae4c71c3beb453cbc429745d8878f0855098a09a'

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

main() {
    local data_home install_dir config_dir config_file temporary_dir binary_temp binary_name binary_sha256
    local tmux_version tmux_major tmux_minor config_temp backup config_input

    (( EUID != 0 )) || die 'Run this installer as the target user, without sudo.'
    [[ -n ${HOME:-} && -d $HOME ]] || die 'A valid HOME directory is required.'
    for command in byobu-tmux curl git sha256sum tmux; do
        command -v "$command" >/dev/null 2>&1 || die "Missing required command: ${command}"
    done

    tmux_version=$(tmux -V)
    [[ $tmux_version =~ ([0-9]+)\.([0-9]+) ]] || die "Cannot determine tmux version: ${tmux_version}"
    tmux_major=${BASH_REMATCH[1]}
    tmux_minor=${BASH_REMATCH[2]}
    (( tmux_major > 3 || (tmux_major == 3 && tmux_minor >= 0) )) || \
        die "tmux-agent-sidebar requires tmux 3.0 or newer (found ${tmux_version})."

    case $(uname -m) in
        x86_64|amd64)
            binary_name='tmux-agent-sidebar-linux-x86_64'
            binary_sha256=$SIDEBAR_X86_64_SHA256
            ;;
        aarch64|arm64)
            binary_name='tmux-agent-sidebar-linux-aarch64'
            binary_sha256=$SIDEBAR_AARCH64_SHA256
            ;;
        *) die "Unsupported architecture: $(uname -m) (supported: x86_64, aarch64)" ;;
    esac

    data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
    install_dir="$data_home/tmux-agent-sidebar"
    config_dir="$HOME/.byobu"
    config_file="$config_dir/.tmux.conf"
    temporary_dir=''
    binary_temp=''
    trap '[[ -z ${temporary_dir:-} ]] || rm -rf -- "$temporary_dir"; [[ -z ${binary_temp:-} ]] || rm -f -- "$binary_temp"' EXIT
    mkdir -p -- "$data_home" "$config_dir"

    if [[ -e $install_dir ]] && [[ $(git -C "$install_dir" rev-parse HEAD 2>/dev/null || true) != "$SIDEBAR_COMMIT" ]]; then
        die "${install_dir} already exists and is not ${SIDEBAR_VERSION}; preserve it or move it before installing."
    fi
    if [[ ! -d $install_dir/.git ]]; then
        temporary_dir=$(mktemp -d "$data_home/.tmux-agent-sidebar.XXXXXX") || die 'Could not create a temporary directory.'
        git clone --depth 1 --branch "$SIDEBAR_VERSION" "$SIDEBAR_REPOSITORY" "$temporary_dir"
        [[ $(git -C "$temporary_dir" rev-parse HEAD) == "$SIDEBAR_COMMIT" ]] || die 'The checked-out source does not match the expected release commit.'
        mv -- "$temporary_dir" "$install_dir"
        temporary_dir=''
    fi

    mkdir -p -- "$install_dir/bin"
    binary_temp=$(mktemp "$install_dir/bin/.tmux-agent-sidebar.XXXXXX") || die 'Could not create a temporary sidebar binary.'
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 \
        --output "$binary_temp" "$SIDEBAR_RELEASE_BASE/$binary_name"
    printf '%s  %s\n' "$binary_sha256" "$binary_temp" | sha256sum --check --status || \
        die 'tmux-agent-sidebar binary checksum verification failed.'
    chmod 0755 -- "$binary_temp"
    mv -- "$binary_temp" "$install_dir/bin/tmux-agent-sidebar"
    binary_temp=''

    config_input=/dev/null
    [[ ! -f $config_file ]] || config_input=$config_file
    config_temp=$(mktemp "$config_dir/.tmux-agent-sidebar.XXXXXX") || die 'Could not create a temporary configuration file.'
    if ! awk -v script="$install_dir/tmux-agent-sidebar.tmux" '
        /^# >>> dev_setup tmux-agent-sidebar >>>$/ { managed = 1; next }
        /^# <<< dev_setup tmux-agent-sidebar <<<$/ { managed = 0; next }
        !managed { print }
        END {
            print "# >>> dev_setup tmux-agent-sidebar >>>"
            print "set -g @sidebar_auto_create on"
            print "set -g @sidebar_bottom_height 20"
            print "set -g @sidebar_notifications off"
            print "set -g @agent-sidebar-default-agent codex"
            print "run-shell \047" script "\047"
            print "# <<< dev_setup tmux-agent-sidebar <<<"
        }
    ' "$config_input" > "$config_temp"; then
        rm -f -- "$config_temp"
        die 'Could not create the Byobu configuration.'
    fi
    if [[ ! -f $config_file ]] || ! cmp -s "$config_temp" "$config_file"; then
        if [[ -f $config_file ]]; then
            backup="$config_file.before-tmux-agent-sidebar.$(date +%Y%m%d%H%M%S)"
            cp -p -- "$config_file" "$backup"
            printf 'Backed up %s\n' "$backup"
        fi
        mv -- "$config_temp" "$config_file"
    else
        rm -f -- "$config_temp"
    fi

    if [[ -n ${TMUX:-} ]]; then
        tmux source-file "$config_file"
    fi
    printf '%s\n' "tmux-agent-sidebar ${SIDEBAR_VERSION} is installed at ${install_dir}."
    printf '%s\n' 'Start Byobu with byobu-tmux, then use Ctrl-a e to toggle the sidebar.'
    printf '%s\n' 'Configure agent integrations separately with installer/tmux_agent_sidebar_hooks.sh.'
}

main "$@"
