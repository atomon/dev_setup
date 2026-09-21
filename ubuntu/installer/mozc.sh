#!/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/utils/input_method.sh"

if [[ ${1:-} == --help && $# == 1 ]]; then
    echo 'Usage: bash installer/mozc.sh'
    exit 0
fi
(( $# == 0 )) || ime_error '引数は不要です。--help を参照してください。'
ime_require_session
ime_update_packages
ime_install_packages ibus-mozc mozc-utils-gui python3-gi fonts-noto-cjk

# Preserve existing layouts and add Mozc only once.
/usr/bin/python3 <<'PY'
from gi.repository import Gio, GLib

settings = Gio.Settings.new('org.gnome.desktop.input-sources')
sources = settings.get_value('sources').unpack()
mozc = ('ibus', 'mozc-jp')
if mozc not in sources:
    if not settings.set_value('sources', GLib.Variant('a(ss)', sources + [mozc])):
        raise SystemExit('入力ソースの更新に失敗しました。')
    Gio.Settings.sync()
PY

printf '任意のキーマップ: %s/DB/keymap_switch_en_jp.txt\n' "$script_dir"
echo '設定GUI: /usr/lib/mozc/mozc_tool --mode=config_dialog'
echo 'キー設定の編集 → インポートで上記ファイルを選択できます。'
echo '再ログイン後、GNOMEの入力ソースからMozcを選択してください。'
echo 'Fcitx 5を利用中なら、その設定画面でMozcを選択してください。'
echo 'IBusへ切り替える場合の手順はREADME.mdの「日本語入力」を参照してください。'
