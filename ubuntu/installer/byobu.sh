#!/usr/bin/env bash

# Install Byobu system-wide, then configure tmux session persistence for the
# invoking user. Pane contents are restored, but AI agent processes are
# deliberately not restarted.
set -Eeuo pipefail

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SAVE_INTERVAL_MINUTES=3
readonly RESURRECT_VERSION='v4.0.0'
readonly RESURRECT_COMMIT='e87d7d592cac97fa38c12395ebec042c154a1844'
readonly RESURRECT_REPOSITORY='https://github.com/tmux-plugins/tmux-resurrect.git'
readonly CONTINUUM_VERSION='v3.1.0'
readonly CONTINUUM_COMMIT='46e0e0023476018ddb4cc0d44783eede27e5a8ec'
readonly CONTINUUM_REPOSITORY='https://github.com/tmux-plugins/tmux-continuum.git'

source "$SCRIPT_DIR/utils/byobu_common.sh"

# tmux comes in as byobu's dependency, so the package manager can autoremove it
# together with byobu.
install_packages() {
    local os=$1

    case $os in
        Linux)
            require_commands apt-get sudo
            sudo -v
            sudo apt-get update
            sudo apt-get install -y byobu
            ;;
        Darwin)
            # Homebrew refuses to run as root.
            require_commands brew
            HOMEBREW_NO_ANALYTICS=1 brew install byobu
            ;;
        *)
            die "Unsupported OS: $os"
            ;;
    esac
}

main() {
    local os data_home plugin_root resurrect_dir restore_helper config_file

    (( EUID != 0 )) || die 'Run this installer as the target user, without sudo.'
    [[ -n ${HOME:-} && -d $HOME ]] || die 'A valid HOME directory is required.'
    require_commands git
    os=$(uname -s)
    install_packages "$os"
    command -v tmux >/dev/null 2>&1 || die 'tmux was not installed.'
    command -v byobu-tmux >/dev/null 2>&1 || die 'byobu-tmux was not installed.'

    umask 077
    data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
    plugin_root="$data_home/tmux-plugins"
    resurrect_dir="$data_home/tmux/resurrect"
    restore_helper="$data_home/byobu-session-restore/restore-after-attach.sh"
    config_file="$HOME/.byobu/.tmux.conf"
    mkdir -p -- "$plugin_root" "$resurrect_dir" "${restore_helper%/*}" "$HOME/.local/bin"
    # macOS chmod treats -- after the mode as a file name.
    chmod 0700 "$plugin_root" "$resurrect_dir" "${restore_helper%/*}"
    install -m 0700 -- "$SCRIPT_DIR/utils/byobu_restore_after_attach.sh" "$restore_helper"
    install -m 0700 -- "$SCRIPT_DIR/utils/byobu_resume.sh" "$HOME/.local/bin/byobu-resume"

    install_plugin tmux-resurrect "$RESURRECT_VERSION" "$RESURRECT_COMMIT" "$RESURRECT_REPOSITORY" "$plugin_root"
    install_plugin tmux-continuum "$CONTINUUM_VERSION" "$CONTINUUM_COMMIT" "$CONTINUUM_REPOSITORY" "$plugin_root"

    write_managed_block "$config_file" byobu-session-restore <<EOF
set -g mouse on
set -g prefix M-a
unbind-key -n C-a
bind-key M-a send-prefix
set -s extended-keys on
set -sq extended-keys-format csi-u
set -s terminal-features[100] 'xterm-ghostty:extkeys'
set -g @resurrect-dir '$resurrect_dir'
set -g @resurrect-processes false
set -g @resurrect-capture-pane-contents on
set -g @continuum-save-interval $SAVE_INTERVAL_MINUTES
set -g @continuum-restore off
set -g @continuum-boot off
if-shell -F '#{!=:#{DEV_SETUP_BYOBU_RESUME_SESSION},}' 'set -g @continuum-save-interval 0'
set-hook -g after-new-session[900] 'run-shell -b "$restore_helper $SAVE_INTERVAL_MINUTES"'
run-shell '$plugin_root/tmux-resurrect/resurrect.tmux'
run-shell '$plugin_root/tmux-continuum/continuum.tmux'
EOF

    if [[ -n ${TMUX:-} ]]; then
        tmux source-file "$config_file"
    fi
    tmux -V
    printf '%s\n' 'Byobu and tmux are installed system-wide.'
    printf '%s\n' 'Session layout and working directories can be restored with byobu-resume.'
    printf 'Pane contents are saved under %s.\n' "$resurrect_dir"
    printf '%s\n' 'WARNING: Saved pane contents are unencrypted and can contain credentials or other sensitive data.'
    printf '%s\n' 'AI agent processes are not restarted.'
    printf '%s\n' 'Run byobu-resume to restore the latest saved session; normal byobu-tmux startup is fresh.'
    if [[ :$PATH: != *":$HOME/.local/bin:"* ]]; then
        printf 'NOTE: %s is not in PATH; run byobu-resume by its full path or add the directory to PATH.\n' "$HOME/.local/bin"
        if [[ $os == Darwin ]]; then
            printf '%s\n' "macOS (zsh): echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zprofile"
        else
            printf '%s\n' "Ubuntu's default ~/.profile adds it at the next login."
        fi
    fi
    if [[ $os == Darwin ]]; then
        printf '%s\n' 'On macOS, let your terminal send Option as Meta so Alt-a works (Ghostty: macos-option-as-alt = left keeps Right Option for characters such as \ on JIS keyboards).'
    fi
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
