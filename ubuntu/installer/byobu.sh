#!/usr/bin/env bash

# Install Byobu system-wide, then configure tmux session persistence for the
# invoking user. Pane contents and shell history are restored, but AI agent
# processes are deliberately not restarted.
set -Eeuo pipefail

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly RESURRECT_VERSION='v4.0.0'
readonly RESURRECT_COMMIT='e87d7d592cac97fa38c12395ebec042c154a1844'
readonly RESURRECT_REPOSITORY='https://github.com/tmux-plugins/tmux-resurrect.git'
readonly CONTINUUM_VERSION='v3.1.0'
readonly CONTINUUM_COMMIT='46e0e0023476018ddb4cc0d44783eede27e5a8ec'
readonly CONTINUUM_REPOSITORY='https://github.com/tmux-plugins/tmux-continuum.git'

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

install_plugin() {
    local name=$1 version=$2 commit=$3 repository=$4 plugin_root=$5 destination stage

    destination="$plugin_root/$name"
    if [[ -e $destination ]]; then
        [[ -d $destination/.git ]] || die "$destination exists but is not a Git checkout."
        [[ $(git -C "$destination" rev-parse HEAD 2>/dev/null || true) == "$commit" ]] || \
            die "$destination is not the expected $version; preserve it or move it before installing."
        return
    fi

    stage=$(mktemp -d "$plugin_root/.${name}.XXXXXX") || die "Could not create a temporary $name directory."
    if ! git clone --depth 1 --branch "$version" "$repository" "$stage"; then
        rm -rf -- "$stage"
        die "Could not clone $name."
    fi
    if [[ $(git -C "$stage" rev-parse HEAD) != "$commit" ]]; then
        rm -rf -- "$stage"
        die "$name source does not match the expected $version commit."
    fi
    mv -- "$stage" "$destination"
}

main() {
    local data_home plugin_root resurrect_dir restore_helper
    local config_dir config_file config_input config_temp backup

    (( EUID != 0 )) || die 'Run this installer as the target user, without sudo.'
    [[ -n ${HOME:-} && -d $HOME ]] || die 'A valid HOME directory is required.'
    for command in apt-get git sudo; do
        command -v "$command" >/dev/null 2>&1 || die "Missing required command: $command"
    done

    sudo -v
    sudo apt-get update
    sudo apt-get install -y tmux byobu
    command -v tmux >/dev/null 2>&1 || die 'tmux was not installed.'
    command -v byobu-tmux >/dev/null 2>&1 || die 'byobu-tmux was not installed.'

    umask 077
    data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
    plugin_root="$data_home/tmux-plugins"
    resurrect_dir="$data_home/tmux/resurrect"
    restore_helper="$data_home/byobu-session-restore/restore-after-attach.sh"
    config_dir="$HOME/.byobu"
    config_file="$config_dir/.tmux.conf"
    mkdir -p -- "$plugin_root" "$resurrect_dir" "${restore_helper%/*}" "$HOME/.local/bin"
    chmod 0700 -- "$plugin_root" "$resurrect_dir" "${restore_helper%/*}"
    install -m 0700 -- "$SCRIPT_DIR/utils/byobu_restore_after_attach.sh" "$restore_helper"
    install -m 0700 -- "$SCRIPT_DIR/utils/byobu_resume.sh" "$HOME/.local/bin/byobu-resume"

    install_plugin tmux-resurrect "$RESURRECT_VERSION" "$RESURRECT_COMMIT" "$RESURRECT_REPOSITORY" "$plugin_root"
    install_plugin tmux-continuum "$CONTINUUM_VERSION" "$CONTINUUM_COMMIT" "$CONTINUUM_REPOSITORY" "$plugin_root"

    mkdir -p -- "$config_dir"
    config_input=/dev/null
    [[ ! -f $config_file ]] || config_input=$config_file
    config_temp=$(mktemp "$config_dir/.byobu-session-restore.XXXXXX") || die 'Could not create a temporary Byobu configuration.'
    if ! awk -v resurrect_dir="$resurrect_dir" \
        -v resurrect="$plugin_root/tmux-resurrect/resurrect.tmux" \
        -v continuum="$plugin_root/tmux-continuum/continuum.tmux" \
        -v restore_helper="$restore_helper" '
        /^# >>> dev_setup byobu-session-restore >>>$/ { managed = 1; next }
        /^# <<< dev_setup byobu-session-restore <<<$/ { managed = 0; next }
        !managed { print }
        END {
            print "# >>> dev_setup byobu-session-restore >>>"
            print "set -g mouse on"
            print "set -g @resurrect-dir \047" resurrect_dir "\047"
            print "set -g @resurrect-processes false"
            print "set -g @resurrect-capture-pane-contents on"
            print "set -g @resurrect-save-shell-history on"
            print "set -g @continuum-save-interval 3"
            print "set -g @continuum-restore off"
            print "set -g @continuum-boot off"
            print "if-shell -F \047#{!=:#{DEV_SETUP_BYOBU_RESUME_SESSION},}\047 \047set -g @continuum-save-interval 0\047"
            print "set-hook -g after-new-session[900] \047run-shell -b \042" restore_helper "\042\047"
            print "run-shell \047" resurrect "\047"
            print "run-shell \047" continuum "\047"
            print "# <<< dev_setup byobu-session-restore <<<"
        }
    ' "$config_input" > "$config_temp"; then
        rm -f -- "$config_temp"
        die 'Could not create the Byobu configuration.'
    fi
    if [[ ! -f $config_file ]] || ! cmp -s "$config_temp" "$config_file"; then
        if [[ -f $config_file ]]; then
            backup="$config_file.before-byobu-session-restore.$(date +%Y%m%d%H%M%S)"
            cp -p -- "$config_file" "$backup"
            printf 'Backed up %s\n' "$backup"
        fi
        mv -- "$config_temp" "$config_file"
    else
        rm -f -- "$config_temp"
    fi

    if [[ -n ${TMUX:-} ]]; then
        tmux source-file "$HOME/.byobu/.tmux.conf"
    fi
    tmux -V
    printf '%s\n' 'Byobu and tmux are installed system-wide.'
    printf '%s\n' 'Session layout and working directories can be restored with byobu-resume.'
    printf 'Pane contents and shell history are saved under %s.\n' "$resurrect_dir"
    printf '%s\n' 'WARNING: Saved pane contents and shell history are unencrypted and can contain credentials or other sensitive data.'
    printf '%s\n' 'AI agent processes are not restarted.'
    printf '%s\n' 'Run byobu-resume to restore the latest saved session; normal byobu-tmux startup is fresh.'
}

main "$@"
