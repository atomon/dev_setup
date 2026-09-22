#!/usr/bin/env bash

# Restore after Byobu creates its first session, but only when byobu-resume
# placed an explicit request in the new tmux server's environment.
set -Eeuo pipefail

resume_request=$(tmux show-environment -g DEV_SETUP_BYOBU_RESUME_SESSION 2>/dev/null || true)
saved_session=${resume_request#*=}
[[ $resume_request == DEV_SETUP_BYOBU_RESUME_SESSION=* && -n $saved_session ]] || exit 0
tmux set-environment -gu DEV_SETUP_BYOBU_RESUME_SESSION

resurrect_dir=$(tmux show-option -gqv @resurrect-dir)
restore_script=$(tmux show-option -gqv @resurrect-restore-script-path)
[[ -n $resurrect_dir && -f $resurrect_dir/last && -x $restore_script ]] || exit 0

sidebar_dir=$(tmux show-option -gqv @agent_sidebar_dir)
sidebar_bin=$(tmux show-option -gqv @agent_sidebar_bin)
sidebar_auto_create=$(tmux show-option -gqv @sidebar_auto_create)
sidebar_config=''
if [[ -n $sidebar_dir && -f $sidebar_dir/agent-sidebar.conf && -x $sidebar_bin ]]; then
    sidebar_config="$sidebar_dir/agent-sidebar.conf"
    tmux set-option -g @sidebar_auto_create off
    tmux source-file "$sidebar_config"
    while IFS='|' read -r pane_id pane_role; do
        [[ $pane_role != sidebar ]] || tmux kill-pane -t "$pane_id"
    done < <(tmux list-panes -a -F '#{pane_id}|#{@pane_role}')
fi

current_session=$(tmux list-sessions -F '#{session_name}' | head -n 1)
[[ -n $current_session ]] || exit 1
if [[ -n $saved_session && $saved_session != "$current_session" ]] && \
    ! tmux has-session -t "=$saved_session" 2>/dev/null; then
    tmux rename-session -t "=$current_session" "$saved_session"
fi

"$restore_script"

if [[ -n $sidebar_config ]]; then
    while IFS= read -r saved_pane; do
        if [[ $(tmux display-message -p -t "$saved_pane" '#{window_panes}' 2>/dev/null || true) -gt 1 ]]; then
            tmux kill-pane -t "$saved_pane"
        fi
    done < <(awk -F '\t' '$1 == "pane" && $10 == "tmux-agent-sidebar" { print $2 ":" $3 "." $6 }' "$resurrect_dir/last")

    tmux set-option -g @sidebar_auto_create "${sidebar_auto_create:-on}"
    tmux source-file "$sidebar_config"
    if [[ ${sidebar_auto_create:-on} != off ]]; then
        while IFS='|' read -r window_id pane_path; do
            "$sidebar_bin" toggle --create-only "$window_id" "$pane_path"
        done < <(tmux list-windows -a -F '#{window_id}|#{pane_current_path}')
    fi
fi

tmux set-option -g @continuum-save-interval 3
