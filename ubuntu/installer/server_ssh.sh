#!/usr/bin/env bash
# =============================================================================
# SSH鍵のパスワードレスログイン セットアップスクリプト (Linux クライアント用)
#
# やること (すべて実行済みならスキップされるので、何度実行しても重複しません):
#   1. 専用フォルダと鍵ペア(ed25519)の作成
#   2. 公開鍵をサーバーに登録
#   3. ~/.ssh/config に alias を追記
#   4. 鍵でログインできるかテスト
# =============================================================================
set -euo pipefail

# ------------------------------ 設定(ここだけ編集) ------------------------------
ALIAS="jetson"             # ssh <ALIAS> で接続できるようになる名前
SERVER_HOST="jetson.local" # ← JetsonのIPアドレスまたはホスト名.local
SERVER_USER="jetson"       # ← Jetson側のユーザー名
SERVER_PORT="22"           # SSHポート

KEY_DIR="${HOME}/.ssh/${ALIAS}" # 鍵の保存フォルダ (~/.ssh/aniki-jetson/)
KEY_NAME="id_ed25519"           # 鍵ファイル名
KEY_COMMENT="${ALIAS}"          # 公開鍵に付くコメント
USE_PASSPHRASE="false"          # true: パスフレーズを設定(推奨) / false: 設定しない
# ---------------------------------------------------------------------------------

KEY_PATH="${KEY_DIR}/${KEY_NAME}"
SSH_DIR="${HOME}/.ssh"
SSH_CONFIG="${SSH_DIR}/config"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[SKIP]\033[0m %s\n' "$*"; }
die() {
    printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2
    exit 1
}

# --- 事前チェック ---
for cmd in ssh ssh-keygen ssh-copy-id; do
    command -v "$cmd" >/dev/null 2>&1 || die "'${cmd}' が見つかりません。openssh-client をインストールしてください。"
done

cat <<EOF
以下の設定で実行します。
  alias       : ${ALIAS}
  接続先      : ${SERVER_USER}@${SERVER_HOST}:${SERVER_PORT}
  鍵          : ${KEY_PATH}
  パスフレーズ: ${USE_PASSPHRASE}
EOF
read -r -p "続行しますか? [y/N] " ans
[[ "${ans}" =~ ^[Yy]$ ]] || {
    echo "中止しました。"
    exit 0
}

# --- 1. フォルダと鍵ペアの作成 ---
log "1. 鍵ペアの作成"
mkdir -p "${SSH_DIR}" "${KEY_DIR}"
chmod 700 "${SSH_DIR}" "${KEY_DIR}"

if [[ -f "${KEY_PATH}" ]]; then
    warn "秘密鍵が既に存在します: ${KEY_PATH}"
    if [[ ! -f "${KEY_PATH}.pub" ]]; then
        echo "公開鍵が無いため、秘密鍵から再生成します。"
        ssh-keygen -y -f "${KEY_PATH}" >"${KEY_PATH}.pub"
    fi
else
    if [[ "${USE_PASSPHRASE}" == "true" ]]; then
        ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "${KEY_COMMENT}"
    else
        ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "${KEY_COMMENT}" -N ""
    fi
fi
chmod 600 "${KEY_PATH}"
chmod 644 "${KEY_PATH}.pub"

# --- 2. 公開鍵をサーバーに登録 ---
log "2. 公開鍵をサーバーに登録"
if ssh -i "${KEY_PATH}" -o IdentitiesOnly=yes \
    -o PasswordAuthentication=no -o PreferredAuthentications=publickey \
    -o ConnectTimeout=10 -p "${SERVER_PORT}" \
    "${SERVER_USER}@${SERVER_HOST}" true 2>/dev/null; then
    warn "この鍵は既にサーバーに登録済みです。"
else
    echo "(サーバーのパスワードを聞かれます)"
    ssh-copy-id -i "${KEY_PATH}.pub" -p "${SERVER_PORT}" "${SERVER_USER}@${SERVER_HOST}"
fi

# --- 3. ~/.ssh/config に alias を追記 ---
log "3. ~/.ssh/config に alias を設定"
touch "${SSH_CONFIG}"
chmod 600 "${SSH_CONFIG}"

if grep -qE "^[[:space:]]*Host[[:space:]]+(.*[[:space:]])?${ALIAS}([[:space:]]|\$)" "${SSH_CONFIG}"; then
    warn "Host ${ALIAS} は既に ${SSH_CONFIG} に存在します。"
else
    cp -a "${SSH_CONFIG}" "${SSH_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    cat >>"${SSH_CONFIG}" <<EOF

Host ${ALIAS}
    HostName ${SERVER_HOST}
    User ${SERVER_USER}
    Port ${SERVER_PORT}
    IdentityFile ${KEY_PATH}
    IdentitiesOnly yes
EOF
    echo "追記しました: Host ${ALIAS}"
fi

# --- 4. 鍵でのログインテスト ---
log "4. 鍵でのログインテスト"
if ssh -o PasswordAuthentication=no -o PreferredAuthentications=publickey \
    -o ConnectTimeout=10 "${ALIAS}" 'echo "login OK: $(whoami)@$(hostname)"'; then
    echo "鍵でのログインに成功しました。"
else
    die "鍵でのログインに失敗しました。'ssh -v ${ALIAS}' で原因を確認してください。"
fi

log "完了"
echo "  ssh ${ALIAS}"
if [[ "${USE_PASSPHRASE}" == "true" ]]; then
    echo "  (パスフレーズ入力を省くなら: ssh-add ${KEY_PATH})"
fi
