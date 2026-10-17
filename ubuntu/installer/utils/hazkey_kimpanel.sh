#!/bin/bash
# Optional Kimpanel GNOME Shell extension (hazkey.sh --kimpanel), installed per user.

# Kimpanel v83; KIMPANEL_SHELL_VERSIONS mirrors shell-version in its metadata.json.
readonly KIMPANEL_UUID=kimpanel@kde.org
readonly KIMPANEL_URL="https://extensions.gnome.org/download-extension/${KIMPANEL_UUID}.shell-extension.zip?version_tag=57768"
readonly KIMPANEL_SHA256=b8d83c1bc6e903a280dc0492b9b4e3be4b2713ab96c669d1ae90e625eacf675f
readonly -a KIMPANEL_SHELL_VERSIONS=(45 46 47)
# Line height assumed by hazkey_patch_kimpanel (Ghostty font-size 12 is ~21px).
readonly KIMPANEL_POINT_LINE_HEIGHT=24

hazkey_kimpanel_supported() {
    local version
    version=$(gnome-shell --version | sed -nE 's/^GNOME Shell ([0-9]+).*/\1/p')
    [[ " ${KIMPANEL_SHELL_VERSIONS[*]} " == *" $version "* ]] || \
        ime_error "Kimpanelの対応外のGNOME Shellです: ${version:-不明}（対応: ${KIMPANEL_SHELL_VERSIONS[*]}）"
}

# Enabled on the next login: a running Wayland shell does not rescan new extensions.
hazkey_enable_kimpanel() {
    local enabled updated
    if [[ $(gsettings get org.gnome.shell disable-user-extensions) == true ]]; then
        printf '注意: ユーザー拡張機能が無効化されているため、Kimpanelは有効になりません（設定は変更しません）。\n' >&2
    fi
    enabled=$(gsettings get org.gnome.shell enabled-extensions)
    updated=$(/usr/bin/python3 "$HAZKEY_INSTALLER_DIR/utils/ubuntu_settings.py" append-gvariant \
        "$enabled" "$KIMPANEL_UUID")
    [[ $updated == "$enabled" ]] || gsettings set org.gnome.shell enabled-extensions "$updated"
}

# Ghostty reports the IME cursor as a 1px point at the bottom of the line, but Kimpanel
# treats only a 0px rect that way, so a popup flipped above the line covered the input.
# Both cases now assume a KIMPANEL_POINT_LINE_HEIGHT line (upstream used 20px for 0px).
hazkey_patch_kimpanel() {
    local panel="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$KIMPANEL_UUID/panel.js"
    /usr/bin/python3 -I - "$panel" "$KIMPANEL_POINT_LINE_HEIGHT" <<'EOF' || \
        ime_error "Kimpanelのpanel.jsが想定と異なるため修正できません: $panel"
import pathlib, sys
path, height = pathlib.Path(sys.argv[1]), sys.argv[2]
block = '        if (h {}) {{\n            h = {h};\n            y = y - {h};\n        }}\n'
original, patched = block.format('== 0', h=20), block.format('<= 1', h=height)
text = path.read_text()
if text.count(patched) == 1:
    sys.exit(0)
if text.count(original) != 1:
    sys.exit(1)
path.write_text(text.replace(original, patched))
EOF
}

hazkey_install_kimpanel() (
    set -euo pipefail
    local download_dir

    hazkey_kimpanel_supported
    download_dir=$(mktemp -d)
    trap 'rm -rf -- "$download_dir"' EXIT
    hazkey_fetch "$KIMPANEL_URL" "$download_dir/kimpanel.zip"
    hazkey_verify_sha256 "$KIMPANEL_SHA256" "$download_dir/kimpanel.zip"
    gnome-extensions install --force "$download_dir/kimpanel.zip"
    hazkey_patch_kimpanel
    hazkey_enable_kimpanel
    printf 'Kimpanel（%s）を導入しました。再ログイン後に有効になります。\n' "$KIMPANEL_UUID"
)
