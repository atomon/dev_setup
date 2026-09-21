#!/bin/bash
# Helpers for installer-owned files in the user's configuration directory.

hazkey_config_home() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

hazkey_install_managed_file() {
    local template=$1 target=$2 backup_message=$3 backup

    [[ -f $template ]] || ime_error "設定テンプレートが見つかりません: $template"
    if [[ -e $target || -L $target ]] && ! cmp -s "$template" "$target"; then
        backup=$(mktemp "$target.before-hazkey.XXXXXX")
        cp -L -- "$target" "$backup"
        printf '%sを保存しました: %s\n' "$backup_message" "$backup"
    fi
    install -Dm644 -- "$template" "$target"
}
