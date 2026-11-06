#!/bin/bash
# Helpers shared by the Byobu and tmux-agent-sidebar installers.

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_commands() {
    local command

    for command in "$@"; do
        command -v "$command" >/dev/null 2>&1 || die "Missing required command: $command"
    done
}

# Only an untouched checkout of the same upstream is replaced: no local changes
# and no commits that exist only locally, including stashes and commits left
# only in the reflog. Anything else stays for the user.
is_pristine_checkout() {
    local directory=$1 repository=$2 changes local_commits

    [[ $(git -C "$directory" remote get-url origin 2>/dev/null || true) == "$repository" ]] || return 1
    changes=$(git -C "$directory" status --porcelain 2>/dev/null) || return 1
    local_commits=$(git -C "$directory" rev-list --count --all --reflog --not --remotes --tags 2>/dev/null) || return 1
    [[ -z $changes && $local_commits == 0 ]]
}

install_plugin() {
    local name=$1 version=$2 commit=$3 repository=$4 plugin_root=$5 destination work

    destination="$plugin_root/$name"
    if [[ -e $destination ]]; then
        [[ -d $destination/.git ]] || die "$destination exists but is not a Git checkout."
        [[ $(git -C "$destination" rev-parse HEAD 2>/dev/null || true) != "$commit" ]] || return 0
        is_pristine_checkout "$destination" "$repository" || \
            die "$destination is not the expected $version and has local changes, local-only commits, or another origin; preserve it or move it before installing."
    fi

    work=$(mktemp -d "$plugin_root/.${name}.XXXXXX") || die "Could not create a temporary $name directory."
    if ! git clone --depth 1 --branch "$version" "$repository" "$work/new"; then
        rm -rf -- "$work"
        die "Could not clone $name."
    fi
    if [[ $(git -C "$work/new" rev-parse HEAD) != "$commit" ]]; then
        rm -rf -- "$work"
        die "$name source does not match the expected $version commit."
    fi
    [[ ! -e $destination ]] || mv -- "$destination" "$work/previous"
    mv -- "$work/new" "$destination"
    [[ ! -e $work/previous ]] || printf 'Updated %s to %s\n' "$name" "$version"
    rm -rf -- "$work"
}

# Write stdin as the "dev_setup NAME" block of a tmux configuration. An existing
# block is replaced where it stands, so blocks owned by other installers keep
# their order; a new block is appended. A changed file is backed up first.
write_managed_block() {
    local config_file=$1 name=$2 block config_input config_temp backup

    block=$(cat)
    mkdir -p -- "${config_file%/*}"
    config_input=/dev/null
    [[ ! -f $config_file ]] || config_input=$config_file
    config_temp=$(mktemp "${config_file%/*}/.${name}.XXXXXX") || die "Could not create a temporary $name configuration."
    if ! BLOCK=$block awk -v begin="# >>> dev_setup $name >>>" -v end="# <<< dev_setup $name <<<" '
        function emit() { print begin; print ENVIRON["BLOCK"]; print end; written = 1 }
        $0 == begin { managed = 1; if (!written) emit(); next }
        $0 == end { managed = 0; next }
        !managed { print }
        END { if (!written) emit() }
    ' "$config_input" > "$config_temp"; then
        rm -f -- "$config_temp"
        die "Could not create the $name configuration."
    fi
    if [[ -f $config_file ]] && cmp -s "$config_temp" "$config_file"; then
        rm -f -- "$config_temp"
        return
    fi
    if [[ -f $config_file ]]; then
        backup="$config_file.before-$name.$(date +%Y%m%d%H%M%S)"
        cp -p -- "$config_file" "$backup"
        printf 'Backed up %s\n' "$backup"
    fi
    mv -- "$config_temp" "$config_file"
}
