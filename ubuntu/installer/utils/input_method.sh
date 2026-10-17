#!/bin/bash
# Shared helpers. Callers own shell options and invoke these outside conditionals
# so that errexit remains effective throughout installation.

ime_error() {
    printf '%s\n' "$*" >&2
    exit 1
}

ime_require_session() {
    if (( EUID == 0 )) || [[ ${XDG_CURRENT_DESKTOP:-} != *GNOME* ]] || [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
        ime_error 'Ubuntu GNOMEの端末から、sudoを付けず通常ユーザーで実行してください。'
    fi
    local ID
    . /etc/os-release
    [[ $ID == ubuntu ]] || ime_error 'Ubuntu向けのスクリプトです。'
}

ime_update_packages() {
    sudo apt-get update --error-on=any
}

ime_install_packages() {
    sudo apt-get install -y --no-remove "$@"
}

ime_select_fcitx5() {
    local backup
    if [[ -e "$HOME/.xinputrc" || -L "$HOME/.xinputrc" ]]; then
        backup=$(mktemp "$HOME/.xinputrc.before-hazkey.XXXXXX")
        cp -L -- "$HOME/.xinputrc" "$backup"
        printf '入力方式の設定を保存しました: %s\n' "$backup"
    fi
    im-config -n fcitx5
}

ime_configure_environment() {
    local environment_dir environment_file template
    environment_dir="$(hazkey_config_home)/environment.d"
    environment_file="$environment_dir/90-fcitx5.conf"
    template="$HAZKEY_INSTALLER_DIR/DB/fcitx5-environment.conf"
    hazkey_install_managed_file "$template" "$environment_file" '既存のFcitx5環境設定'
}

ime_configure_login_environment() (
    set -euo pipefail
    local pam_environment_file template merged
    pam_environment_file="$HOME/.pam_environment"
    template="$HAZKEY_INSTALLER_DIR/DB/fcitx5-pam_environment"
    [[ -f $template ]] || ime_error "設定テンプレートが見つかりません: $template"
    merged=$(mktemp)
    trap 'rm -f -- "$merged"' EXIT
    if [[ -e $pam_environment_file || -L $pam_environment_file ]]; then
        # Keep the user's entries (e.g. locale written by GNOME Settings); replace only
        # the template's lines and variables. Accept both "KEY OVERRIDE=" and "KEY=".
        awk -F '[ \t=]+' 'NR == FNR { line[$0]; if ($1 !~ /^#/ && NF) key[$1]; next }
            !($0 in line) && !($1 in key)' "$template" "$pam_environment_file" > "$merged"
    fi
    cat -- "$template" >> "$merged"
    # Leave an already merged file (or symlink) untouched.
    cmp -s "$merged" "$pam_environment_file" && return
    hazkey_install_managed_file "$merged" "$pam_environment_file" '既存のログイン環境設定'
)
