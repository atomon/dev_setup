#!/bin/bash
# Report network (TCP/UDP/raw) activity of the Hazkey processes owned by this user.
# Unix sockets are expected (fcitx5 <-> hazkey-server, D-Bus) and are not reported.
set -euo pipefail

# pgrep -x pattern.
readonly HAZKEY_NET_PROCESSES='hazkey-server|fcitx5|hazkey-settings'
readonly HAZKEY_NET_INTERVAL=0.2
readonly HAZKEY_NET_SYSCALLS=socket,connect,bind,sendto,sendmsg,sendmmsg
# Families that leave the host; AF_UNIX/AF_NETLINK stay local.
readonly HAZKEY_NET_REMOTE_FAMILIES='AF_INET6?|AF_PACKET'
readonly HAZKEY_NET_EXIT_FOUND=1 HAZKEY_NET_EXIT_ERROR=2
# Exit status of timeout(1) when the capture window ends normally.
readonly HAZKEY_NET_TIMEOUT_EXPIRED=124

hazkey_net_usage() {
    cat <<'EOF'
Usage: bash installer/utils/hazkey_network_check.sh [--watch 秒 | --strace 秒]
  (引数なし)    現時点でHazkey関連プロセスがTCP/UDP/rawソケットを持っていないか確認
  --watch 秒    指定秒数、0.2秒間隔で確認（root不要）。確認中に日本語入力・変換を行う
  --strace 秒   sudoのstraceでソケット作成・接続・送信を全件記録（短時間の通信も検出）
対象: hazkey-server / fcitx5 / hazkey-settings（hazkey-settingsはモデルDL時のみ通信）
終了コード: 0 = 外部通信なし / 1 = 検出 / 2 = 対象プロセスなし・引数エラー
EOF
}

hazkey_net_fail() {
    printf '%s\n' "$*" >&2
    exit "$HAZKEY_NET_EXIT_ERROR"
}

# Extra arguments go to pgrep, e.g. -l for "pid name".
hazkey_net_pids() {
    pgrep -u "$UID" "$@" -x "$HAZKEY_NET_PROCESSES" || true
}

# Prints TCP/UDP/raw sockets (listening or connected) owned by the target processes.
hazkey_net_sockets() {
    local pattern
    local -a pids
    mapfile -t pids < <(hazkey_net_pids)
    (( ${#pids[@]} )) || return 0
    printf -v pattern 'pid=%s,|' "${pids[@]}"
    ss -H -tuwanp 2>/dev/null | grep -E -- "${pattern%|}" || true
}

hazkey_net_require_targets() {
    local targets
    targets=$(hazkey_net_pids -l)
    [[ -n $targets ]] || hazkey_net_fail 'Hazkey関連プロセスが起動していません。Hazkeyで一度入力してから実行してください。'
    grep -q ' hazkey-server$' <<< "$targets" || \
        printf '注意: hazkey-serverが未起動です。Hazkeyで一度入力すると起動します。\n' >&2
    printf '対象プロセス:\n'
    sed 's/^/  /' <<< "$targets"
}

hazkey_net_report() {
    local findings=$1 label=$2
    if [[ -n $findings ]]; then
        printf '❌ %s: 外部通信の可能性があるソケット・システムコールを検出\n%s\n' "$label" "$findings"
        return "$HAZKEY_NET_EXIT_FOUND"
    fi
    printf '✅ %s: TCP/UDP/rawの通信なし（Unixソケットのみ）\n' "$label"
}

hazkey_net_snapshot() {
    hazkey_net_report "$(hazkey_net_sockets)" '現時点のソケット'
}

hazkey_net_watch() {
    local seconds=$1 deadline line
    local -A seen=()
    deadline=$(( SECONDS + seconds ))
    printf '%s秒間確認します。この間に日本語入力・変換を行ってください。\n' "$seconds"
    while (( SECONDS < deadline )); do
        # hazkey_net_sockets re-resolves pids: fcitx5 may restart hazkey-server.
        while IFS= read -r line; do
            [[ -z $line ]] || seen[$line]=1
        done <<< "$(hazkey_net_sockets)"
        sleep "$HAZKEY_NET_INTERVAL"
    done
    hazkey_net_report "$(printf '%s\n' "${!seen[@]}" | sort)" "${seconds}秒間の監視"
}

hazkey_net_strace() (
    local seconds=$1 log status=0 pid
    local -a attach=()
    command -v strace >/dev/null || hazkey_net_fail 'straceが必要です: sudo apt-get install strace'
    for pid in $(hazkey_net_pids); do
        attach+=(-p "$pid")
    done
    log=$(mktemp)
    trap 'rm -f -- "$log"' EXIT
    printf '%s秒間straceで記録します（sudoのパスワードを求められる場合があります）。\n' "$seconds"
    printf 'この間に日本語入力・変換を行ってください。\n'
    # Attaching to running processes needs root while kernel.yama.ptrace_scope >= 1.
    sudo timeout --signal=INT "$seconds" strace -f -qq -e signal=none \
        -e trace="$HAZKEY_NET_SYSCALLS" -o "$log" "${attach[@]}" || status=$?
    (( status == 0 || status == HAZKEY_NET_TIMEOUT_EXPIRED )) || hazkey_net_fail "straceが失敗しました（終了コード: $status）"
    printf '記録したシステムコール: %s件\n' "$(grep -c . "$log" || true)"
    hazkey_net_report "$(grep -E -- "$HAZKEY_NET_REMOTE_FAMILIES" "$log" || true)" \
        "${seconds}秒間のstrace記録"
)

hazkey_net_main() {
    local mode=snapshot seconds=0 result=0 status=0
    case "${1:-}" in
        '') ;;
        --help) hazkey_net_usage; return ;;
        --watch|--strace)
            mode=${1#--}
            seconds=${2:-}
            [[ $seconds =~ ^[1-9][0-9]*$ ]] || hazkey_net_fail "$1 には1以上の秒数を指定してください。"
            shift ;;
        *) hazkey_net_fail "$(hazkey_net_usage)" ;;
    esac
    (( $# <= 1 )) || hazkey_net_fail '引数が多すぎます。--help を参照してください。'

    hazkey_net_require_targets
    hazkey_net_snapshot || result=$?
    case "$mode" in
        watch) hazkey_net_watch "$seconds" || status=$? ;;
        strace) hazkey_net_strace "$seconds" || status=$? ;;
    esac
    # Report the most severe outcome: error (2) > found (1) > clean (0).
    return $(( status > result ? status : result ))
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    hazkey_net_main "$@"
fi
