#!/bin/bash
hazkey_install_model() (
    set -euo pipefail
    local directory target temporary backup
    directory="${XDG_DATA_HOME:-$HOME/.local/share}/hazkey/zenzai"
    target="$directory/zenzai.gguf"
    mkdir -p -- "$directory"
    if [[ -f $target ]] && printf '%s  %s\n' "$ZENZAI_MODEL_SHA256" "$target" | sha256sum --check --status; then
        return
    fi
    temporary=$(mktemp "$directory/.zenzai.XXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    hazkey_fetch "$ZENZAI_MODEL_URL" "$temporary"
    printf '%s  %s\n' "$ZENZAI_MODEL_SHA256" "$temporary" | sha256sum --check --status
    if [[ -e $target ]]; then
        backup=$(mktemp "$directory/zenzai.gguf.before-hazkey.XXXXXX")
        cp -- "$target" "$backup"
        printf '既存モデルを保存しました: %s\n' "$backup"
    fi
    mv -- "$temporary" "$target"
)

hazkey_stop_process() {
    local process=$1 attempt
    if pgrep -u "$UID" -x "$process" >/dev/null; then
        printf '設定更新のため %s を終了します。再ログイン後に反映されます。\n' "$process"
        pkill -TERM -u "$UID" -x "$process" || true
        for attempt in {1..50}; do
            if ! pgrep -u "$UID" -x "$process" >/dev/null; then
                return
            fi
            sleep 0.1
        done
        ime_error "$process が終了しないため、設定更新を中止しました。"
    fi
}

hazkey_select_zenzai_backend() {
    local backend
    if backend=$(/usr/bin/python3 "$HAZKEY_INSTALLER_DIR/utils/detect_vulkan_backend.py"); then
        printf '%s\n' "$backend"
    else
        printf '%s\n' 'CPU'
    fi
}

hazkey_vulkan_option() {
    [[ $1 == Vulkan* ]] && printf '%s\n' ON || printf '%s\n' OFF
}

hazkey_configure_autostart() {
    local autostart_dir autostart_file template
    autostart_dir="$(hazkey_config_home)/autostart"
    autostart_file="$autostart_dir/fcitx5.desktop"
    template="$HAZKEY_INSTALLER_DIR/DB/fcitx5.desktop"
    hazkey_install_managed_file "$template" "$autostart_file" '既存のFcitx 5自動起動設定'
}

hazkey_configure_user() {
    local backend=$1

    # Validate all settings before downloading or replacing any user data.
    /usr/bin/python3 "$HAZKEY_INSTALLER_DIR/utils/configure_hazkey.py" --zenzai-backend "$backend" --check
    hazkey_install_model
    # Do not edit a live daemon's files: its shutdown would overwrite our changes.
    hazkey_stop_process fcitx5
    hazkey_stop_process hazkey-server
    /usr/bin/python3 "$HAZKEY_INSTALLER_DIR/utils/configure_hazkey.py" --zenzai-backend "$backend"
}
