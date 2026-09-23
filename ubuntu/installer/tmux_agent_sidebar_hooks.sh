#!/usr/bin/env bash

# Configure one agent integration at a time. This script never uses sudo and
# writes only to the invoking user's agent configuration directories.
set -Eeuo pipefail

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'HELP'
Usage: bash tmux_agent_sidebar_hooks.sh --agent AGENT [--agent AGENT ...]

Agents:
  codex     Merge the sidebar hooks into ~/.codex/hooks.json.
  claude    Print the supported Claude Code plugin commands; run them in Claude.
  opencode  Create the user-level OpenCode plugin symlink.
HELP
}

configure_codex() {
    local config_dir config_file setup_json temporary backup config_input
    config_dir=${CODEX_HOME:-"$HOME/.codex"}
    config_file="$config_dir/config.toml"
    mkdir -p -- "$config_dir"
    setup_json=$(mktemp "${TMPDIR:-/tmp}/tmux-agent-sidebar-codex.XXXXXX") || die 'Could not create a temporary hook file.'
    if ! "$SIDEBAR_BINARY" setup codex > "$setup_json"; then
        rm -f -- "$setup_json"
        die 'Could not generate the Codex hook configuration.'
    fi
    if ! python3 - "$config_dir/hooks.json" "$setup_json" <<'PY'
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

target = Path(sys.argv[1])
snippet = json.loads(Path(sys.argv[2]).read_text())
if not isinstance(snippet.get("hooks"), dict):
    raise SystemExit("tmux-agent-sidebar returned an invalid Codex hook snippet")

current = {}
if target.exists():
    current = json.loads(target.read_text())
if not isinstance(current, dict):
    raise SystemExit(f"{target} must contain a JSON object")
hooks = current.setdefault("hooks", {})
if not isinstance(hooks, dict):
    raise SystemExit(f"{target} has a non-object hooks entry")

changed = False
for event, additions in snippet["hooks"].items():
    entries = hooks.setdefault(event, [])
    if not isinstance(entries, list):
        raise SystemExit(f"{target} has a non-list hooks.{event} entry")
    for entry in additions:
        if entry not in entries:
            entries.append(entry)
            changed = True

if not changed:
    print(f"Codex hooks are already configured in {target}")
    raise SystemExit(0)
if target.exists():
    backup = target.with_name(f"{target.name}.before-tmux-agent-sidebar.{time.strftime('%Y%m%d%H%M%S')}")
    shutil.copy2(target, backup)
    print(f"Backed up {backup}")
target.parent.mkdir(parents=True, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
with os.fdopen(fd, "w") as handle:
    json.dump(current, handle, indent=2)
    handle.write("\n")
os.replace(temporary, target)
os.chmod(target, 0o600)
print(f"Configured Codex hooks in {target}")
PY
    then
        rm -f -- "$setup_json"
        die 'Could not merge the Codex hook configuration.'
    fi
    rm -f -- "$setup_json"

    if [[ ! -f $config_file ]] || ! awk '
        /^[[:space:]]*\[features\][[:space:]]*(#.*)?$/ { inside = 1; next }
        /^[[:space:]]*\[/ { inside = 0 }
        inside && /^[[:space:]]*hooks[[:space:]]*=[[:space:]]*true([[:space:]]*(#.*)?)?$/ { canonical = 1 }
        inside && /^[[:space:]]*codex_hooks[[:space:]]*=/ { deprecated = 1 }
        END { exit(canonical && !deprecated ? 0 : 1) }
    ' "$config_file"; then
        config_input=/dev/null
        [[ ! -f $config_file ]] || config_input=$config_file
        temporary=$(mktemp "$config_dir/.config.toml.XXXXXX") || die 'Could not create a temporary Codex configuration.'
        awk '
            function add_setting() { if (!setting) print "hooks = true"; setting = 1 }
            /^[[:space:]]*\[features\][[:space:]]*(#.*)?$/ { seen = 1; inside = 1; print; next }
            inside && /^[[:space:]]*\[/ { add_setting(); inside = 0 }
            inside && /^[[:space:]]*hooks[[:space:]]*=/ { add_setting(); next }
            inside && /^[[:space:]]*codex_hooks[[:space:]]*=/ { add_setting(); next }
            { print }
            END {
                if (inside) add_setting()
                if (!seen) { print ""; print "[features]"; print "hooks = true" }
            }
        ' "$config_input" > "$temporary"
        if [[ -f $config_file ]]; then
            backup="$config_file.before-tmux-agent-sidebar.$(date +%Y%m%d%H%M%S)"
            cp -p -- "$config_file" "$backup"
            printf 'Backed up %s\n' "$backup"
        fi
        mv -- "$temporary" "$config_file"
        printf 'Enabled Codex hooks in %s\n' "$config_file"
    fi
    printf '%s\n' 'Restart Codex before expecting sidebar status updates.'
}

configure_claude() {
    cat <<EOF
Claude Code uses the upstream plugin mechanism rather than a manually written hook.
Run these commands inside Claude Code for this user:

  /plugin marketplace add $SIDEBAR_DIR
  /plugin install tmux-agent-sidebar@hiroppy
  /reload-plugins

This avoids the legacy ~/.claude/settings.json hook entries, which would run
in parallel with the plugin and report every event twice.
EOF
}

configure_opencode() {
    local config_home plugin_dir source
    config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
    plugin_dir="$config_home/opencode/plugins"
    source="$SIDEBAR_DIR/.opencode/plugins/tmux-agent-sidebar.js"
    [[ -f $source ]] || die "OpenCode bridge is missing from ${SIDEBAR_DIR}."
    mkdir -p -- "$plugin_dir"
    ln -sfn -- "$source" "$plugin_dir/tmux-agent-sidebar.js"
    printf 'Linked OpenCode bridge at %s\n' "$plugin_dir/tmux-agent-sidebar.js"
    printf '%s\n' 'Restart OpenCode before expecting sidebar status updates.'
}

main() {
    local agent
    local -a agents=()
    (( EUID != 0 )) || die 'Run this script as the target user, without sudo.'
    [[ -n ${HOME:-} && -d $HOME ]] || die 'A valid HOME directory is required.'
    while (( $# )); do
        case "$1" in
            --agent)
                (( $# >= 2 )) || die '--agent requires codex, claude, or opencode.'
                case "$2" in
                    codex|claude|opencode) ;;
                    *) die "Unsupported agent: $2 (supported: codex, claude, opencode)" ;;
                esac
                agents+=("$2")
                shift 2
                ;;
            -h|--help) usage; return ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    (( ${#agents[@]} )) || die 'Select an agent with --agent. See --help.'

    SIDEBAR_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux-agent-sidebar"
    SIDEBAR_BINARY="$SIDEBAR_DIR/bin/tmux-agent-sidebar"
    [[ -x $SIDEBAR_BINARY ]] || die "Install tmux-agent-sidebar first: ${SIDEBAR_BINARY} is missing."

    for agent in "${agents[@]}"; do
        case $agent in
            codex)
                command -v python3 >/dev/null 2>&1 || die 'Codex hook setup requires python3 for safe JSON merging.'
                configure_codex
                ;;
            claude) configure_claude ;;
            opencode) configure_opencode ;;
        esac
    done
}

main "$@"
