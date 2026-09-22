#!/usr/bin/env bash

# Start a new Byobu tmux server and explicitly request restoration of the
# latest tmux-resurrect snapshot. Normal byobu-tmux startup remains fresh.
set -Eeuo pipefail

last_snapshot="${XDG_DATA_HOME:-"$HOME/.local/share"}/tmux/resurrect/last"

[[ -f $last_snapshot ]] || {
    printf 'No saved Byobu session found at %s\n' "$last_snapshot" >&2
    exit 1
}

saved_session=$(awk -F '\t' '
    $1 == "pane" && fallback == "" { fallback = $2 }
    $1 == "state" && $2 != "" { print $2; found = 1; exit }
    END { if (!found) print fallback }
' "$last_snapshot")
[[ -n $saved_session ]] || {
    printf 'The saved Byobu session does not contain an active session.\n' >&2
    exit 1
}

if tmux list-sessions >/dev/null 2>&1; then
    if ! tmux has-session -t "=$saved_session" 2>/dev/null; then
        printf 'A tmux server is already running without saved session %s.\n' "$saved_session" >&2
        printf '%s\n' 'Stop it explicitly before using byobu-resume; it will not be overwritten.' >&2
        exit 1
    fi
    if [[ -n ${TMUX:-} ]]; then
        exec tmux switch-client -t "=$saved_session"
    fi
    exec byobu-tmux attach-session -t "=$saved_session"
fi

export DEV_SETUP_BYOBU_RESUME_SESSION=$saved_session
exec byobu-tmux
