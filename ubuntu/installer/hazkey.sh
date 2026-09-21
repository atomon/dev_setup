#!/bin/bash
set -euo pipefail

readonly HAZKEY_INSTALLER_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$HAZKEY_INSTALLER_DIR/utils/hazkey_constants.sh"
source "$HAZKEY_INSTALLER_DIR/utils/input_method.sh"
source "$HAZKEY_INSTALLER_DIR/utils/hazkey_files.sh"
source "$HAZKEY_INSTALLER_DIR/utils/hazkey_toolchain.sh"
source "$HAZKEY_INSTALLER_DIR/utils/hazkey_setup.sh"
source "$HAZKEY_INSTALLER_DIR/utils/hazkey_install.sh"

hazkey_print_next_steps() {
cat <<'EOF'
Hazkey・Mozcの登録とZenzaiのモデル取得・バックエンドの自動選択が完了しました。
Fcitx 5の入力環境（GTK・Qt・SDL・XIM互換アプリ）を設定しました。
GNOMEのログイン環境にもFcitx 5を設定しました。
作業を保存し、ログアウト・再ログインしてください。設定画面での追加操作は不要です。
Fcitx 5のメニューからHazkeyまたはMozcを選んで入力・変換を確認してください。
既存の入力方式の既定値とキーボード配列は保持します。新規構成ではHazkeyを既定にします。
詳しい手順・IBusへ戻す方法: README.md の「日本語入力」
EOF
}

hazkey_configure_input_method() {
    ime_select_fcitx5
    ime_configure_environment
    ime_configure_login_environment
    hazkey_configure_autostart
}

hazkey_main() {
    if [[ ${1:-} == --help && $# == 1 ]]; then
        hazkey_usage
        return
    fi
    (( $# == 0 )) || ime_error '引数は不要です。--help を参照してください。'
    ime_require_session

    local architecture backend
    architecture=$(dpkg --print-architecture)
    case "$architecture" in
        amd64|arm64) ;;
        *) ime_error '対応アーキテクチャ: amd64 / arm64 (aarch64)' ;;
    esac

    ime_update_packages
    ime_install_packages curl ca-certificates python3-gi procps vulkan-tools
    backend=$(hazkey_select_zenzai_backend)
    printf 'Zenzaiバックエンド: %s\n' "$backend"
    hazkey_install "$architecture" "$backend"
    hazkey_configure_user "$backend"
    hazkey_configure_input_method
    hazkey_print_next_steps
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    hazkey_main "$@"
fi
