#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SETTINGS_UTIL="$SCRIPT_DIR/utils/ubuntu_settings.py"
readonly STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/dev_setup/ubuntu_setting"
readonly MEDIA_KEYS_SCHEMA='org.gnome.settings-daemon.plugins.media-keys'
readonly SHELL_KEYBINDINGS_SCHEMA='org.gnome.shell.keybindings'
readonly INPUT_SOURCES_SCHEMA='org.gnome.desktop.input-sources'
readonly SHORTCUT_BASE='/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings'
readonly SCREENSHOT_UI_KEY='show-screenshot-ui'
readonly XKB_OPTIONS_KEY='xkb-options'

dry_run=false
undo=false
local_rtc=false
backup_dir=''

usage() {
    cat <<'EOF'
Usage: bash installer/ubuntu_setting.sh [OPTIONS]

Apply personal Ubuntu GNOME settings.
  --local-rtc  Store the hardware clock in local time (for Windows dual boot).
  --dry-run    Show planned changes without modifying the system.
  --undo       Restore the most recent backup made by this script.
  -h, --help   Show this help.
EOF
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

run() {
    if [[ $dry_run == true ]]; then
        printf '+ '
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

require_gnome_session() {
    local desktop=${XDG_CURRENT_DESKTOP:-}
    [[ $EUID -ne 0 ]] || fail 'sudoを付けず、ログイン中のユーザーとして実行してください。'
    [[ ${desktop,,} == *gnome* ]] || fail 'Ubuntu GNOMEのログイン済みセッションで実行してください。'
    [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || fail 'GNOMEセッションのD-Busに接続できません。端末を開き直して実行してください。'
    command -v gsettings >/dev/null || fail 'gsettingsが見つかりません。'
    command -v dconf >/dev/null || fail 'dconfが見つかりません。'
    [[ $(gsettings writable "$MEDIA_KEYS_SCHEMA" custom-keybindings) == true ]] ||
        fail 'GNOMEのキーボードショートカット設定を書き込めません。'
}

new_backup() {
    mkdir -p -- "$STATE_ROOT"
    backup_dir=$(mktemp -d "$STATE_ROOT/backup-$(date +%Y%m%d-%H%M%S).XXXXXX")
    printf '設定バックアップ: %s\n' "$backup_dir"
}

activate_backup() {
    ln -sfn -- "$(basename -- "$backup_dir")" "$STATE_ROOT/latest"
}

snapshot_file() {
    local source=$1 label=$2
    if [[ -e $source ]]; then
        cp -a -- "$source" "$backup_dir/$label"
    else
        : > "$backup_dir/$label.absent"
    fi
}

snapshot_system_file() {
    local source=$1 label=$2
    if sudo test -e "$source"; then
        sudo cp -a -- "$source" "$backup_dir/$label"
    else
        : > "$backup_dir/$label.absent"
    fi
}

snapshot_directory_presence() {
    local directory=$1 label=$2
    if [[ -d $directory ]]; then
        : > "$backup_dir/$label.existed"
    else
        : > "$backup_dir/$label.absent"
    fi
}

snapshot_gsettings_value() {
    local schema=$1 key=$2 label=$3
    gsettings get "$schema" "$key" > "$backup_dir/$label.gvariant"
}

snapshot_settings() {
    snapshot_file "$HOME/.bashrc" bashrc
    snapshot_file "$HOME/.bash_aliases" bash_aliases
    snapshot_file "$HOME/.config/autostart/gnome-terminal.desktop" autostart-gnome-terminal.desktop
    snapshot_file "$HOME/.config/autostart/vivaldi.desktop" autostart-vivaldi.desktop
    snapshot_directory_presence "$HOME/Apps" apps
    snapshot_directory_presence "$HOME/.config/autostart" autostart-directory
    snapshot_system_file /etc/default/keyboard keyboard
    snapshot_system_file /etc/adjtime adjtime
    dconf dump "/org/gnome/settings-daemon/plugins/media-keys/" > "$backup_dir/media-keys.dconf"
    snapshot_gsettings_value "$SHELL_KEYBINDINGS_SCHEMA" "$SCREENSHOT_UI_KEY" show-screenshot-ui
    snapshot_gsettings_value "$INPUT_SOURCES_SCHEMA" "$XKB_OPTIONS_KEY" xkb-options
    timedatectl show -p LocalRTC --value > "$backup_dir/local-rtc"
}

restore_file() {
    local label=$1 target=$2
    if [[ -e $backup_dir/$label ]]; then
        cp -a -- "$backup_dir/$label" "$target"
    elif [[ -e $backup_dir/$label.absent ]]; then
        rm -f -- "$target"
    fi
}

restore_system_file() {
    local label=$1 target=$2
    if [[ -e $backup_dir/$label ]]; then
        sudo cp -a -- "$backup_dir/$label" "$target"
    elif [[ -e $backup_dir/$label.absent ]]; then
        sudo rm -f -- "$target"
    fi
}

remove_created_directory() {
    local label=$1 directory=$2
    if [[ -e $backup_dir/$label.absent ]]; then
        rmdir -- "$directory" 2>/dev/null || true
    fi
}

restore_gsettings_value() {
    local schema=$1 key=$2 label=$3
    gsettings set "$schema" "$key" "$(< "$backup_dir/$label.gvariant")"
}

restore_latest_backup() {
    local latest
    latest=$(readlink -f -- "$STATE_ROOT/latest" 2>/dev/null || true)
    [[ -n $latest && -d $latest ]] || fail '復元できるバックアップがありません。'
    backup_dir=$latest
    restore_file bashrc "$HOME/.bashrc"
    restore_file bash_aliases "$HOME/.bash_aliases"
    restore_file autostart-gnome-terminal.desktop "$HOME/.config/autostart/gnome-terminal.desktop"
    restore_file autostart-vivaldi.desktop "$HOME/.config/autostart/vivaldi.desktop"
    remove_created_directory apps "$HOME/Apps"
    remove_created_directory autostart-directory "$HOME/.config/autostart"
    restore_system_file keyboard /etc/default/keyboard
    restore_system_file adjtime /etc/adjtime
    dconf load "/org/gnome/settings-daemon/plugins/media-keys/" < "$backup_dir/media-keys.dconf"
    restore_gsettings_value "$SHELL_KEYBINDINGS_SCHEMA" "$SCREENSHOT_UI_KEY" show-screenshot-ui
    restore_gsettings_value "$INPUT_SOURCES_SCHEMA" "$XKB_OPTIONS_KEY" xkb-options
    if [[ -s $backup_dir/local-rtc ]]; then
        sudo timedatectl set-local-rtc "$(< "$backup_dir/local-rtc")"
    fi
    printf '復元しました: %s\n' "$backup_dir"
}

upsert_managed_block() {
    local target=$1 content=$2
    local begin='# >>> dev_setup ubuntu_setting >>>'
    local end='# <<< dev_setup ubuntu_setting <<<'
    if [[ $dry_run == true ]]; then
        printf '+ update managed block in %q\n' "$target"
        return
    fi
    mkdir -p -- "$(dirname -- "$target")"
    printf '%s\n' "$content" |
        /usr/bin/python3 "$SETTINGS_UTIL" upsert-block "$target" "$begin" "$end"
}

gvariant_append_string() {
    local value=$1 item=$2
    /usr/bin/python3 "$SETTINGS_UTIL" append-gvariant "$value" "$item"
}

gvariant_string_lines() {
    local value=$1
    /usr/bin/python3 "$SETTINGS_UTIL" gvariant-lines "$value"
}

append_gsettings_string() {
    local schema=$1 key=$2 item=$3 current updated
    current=$(gsettings get "$schema" "$key")
    updated=$(gvariant_append_string "$current" "$item")
    run gsettings set "$schema" "$key" "$updated"
}

assert_binding_available() {
    local current=$1 target_path=$2 binding=$3 path schema existing
    while IFS= read -r path; do
        [[ $path == "$target_path" ]] && continue
        schema="$MEDIA_KEYS_SCHEMA.custom-keybinding:$path"
        existing=$(gsettings get "$schema" binding)
        if [[ $existing == "'$binding'" ]]; then
            fail "ショートカット $binding は既存の $path と競合します。"
        fi
    done < <(gvariant_string_lines "$current")
}

add_shortcut() {
    local id=$1 name=$2 command=$3 binding=$4
    local path="$SHORTCUT_BASE/$id/"
    local schema="$MEDIA_KEYS_SCHEMA.custom-keybinding:$path"
    local current updated
    current=$(gsettings get "$MEDIA_KEYS_SCHEMA" custom-keybindings)
    assert_binding_available "$current" "$path" "$binding"
    updated=$(gvariant_append_string "$current" "$path")
    run gsettings set "$MEDIA_KEYS_SCHEMA" custom-keybindings "$updated"
    run gsettings set "$schema" name "$name"
    run gsettings set "$schema" command "$command"
    run gsettings set "$schema" binding "$binding"
}

enable_caps_to_ctrl() {
    local temporary
    append_gsettings_string "$INPUT_SOURCES_SCHEMA" "$XKB_OPTIONS_KEY" ctrl:nocaps

    if [[ $dry_run == true ]]; then
        printf '+ install -m 644 %q /etc/default/keyboard\n' '/tmp/dev_setup-keyboard'
        return
    fi
    temporary=$(mktemp)
    /usr/bin/python3 "$SETTINGS_UTIL" merge-xkb-option /etc/default/keyboard "$temporary" ctrl:nocaps
    sudo install -m 644 "$temporary" /etc/default/keyboard
    rm -f -- "$temporary"
}

configure_shell() {
    upsert_managed_block "$HOME/.bashrc" "HISTSIZE=20000
HISTFILESIZE=20000
HISTTIMEFORMAT='%F %T '"
    upsert_managed_block "$HOME/.bash_aliases" "alias reload='exec \$SHELL -l'"
}

configure_autostart() {
    run install -Dm644 "$SCRIPT_DIR/DB/gnome-terminal.desktop" \
        "$HOME/.config/autostart/gnome-terminal.desktop"
    if command -v vivaldi >/dev/null; then
        run install -Dm644 "$SCRIPT_DIR/DB/vivaldi.desktop" \
            "$HOME/.config/autostart/vivaldi.desktop"
    else
        printf 'Vivaldiが未導入のため、自動起動は登録しません。\n'
    fi
}

configure_power_shortcuts() {
    add_shortcut dev-setup-suspend 'Sleep' 'systemctl suspend' '<Super>s'
    add_shortcut dev-setup-reboot 'Reboot' 'gnome-session-quit --reboot' '<Super>r'
    add_shortcut dev-setup-shutdown 'Shutdown' 'gnome-session-quit --power-off' '<Super>u'
    add_shortcut dev-setup-logout 'Logout' 'gnome-session-quit --logout' '<Super>e'
}

configure_screenshot_shortcut() {
    append_gsettings_string "$SHELL_KEYBINDINGS_SCHEMA" "$SCREENSHOT_UI_KEY" '<Super><Shift>s'
}

main() {
    while (( $# )); do
        case "$1" in
            --local-rtc) local_rtc=true ;;
            --dry-run) dry_run=true ;;
            --undo) undo=true ;;
            -h|--help) usage; return ;;
            *) fail "不明なオプション: $1" ;;
        esac
        shift
    done
    [[ $undo == false || ( $dry_run == false && $local_rtc == false ) ]] ||
        fail '--undo は --dry-run や --local-rtc と併用できません。'
    require_gnome_session
    if [[ $undo == true ]]; then
        restore_latest_backup
        return
    fi
    if [[ $dry_run == false ]]; then
        new_backup
        snapshot_settings
        activate_backup
    fi
    run sudo apt-get update
    run sudo apt-get install -y bash-completion
    configure_shell
    run mkdir -p "$HOME/Apps"
    configure_autostart
    configure_power_shortcuts
    configure_screenshot_shortcut
    enable_caps_to_ctrl
    if [[ $local_rtc == true ]]; then
        run sudo timedatectl set-local-rtc true
    fi
    printf '完了しました。Caps Lock→Ctrl は再ログイン後に反映されます。\n'
}

main "$@"
