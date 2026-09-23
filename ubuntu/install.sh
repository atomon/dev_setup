#!/bin/bash
set -euo pipefail

# Keep a deterministic execution order and one registry for all modes.
readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly -a PACKAGES=(general_apps ubuntu_setting mozc hazkey github_ssh python docker nvidia_container_toolkit nodejs ghostty byobu tmux_agent_sidebar astronvim)
declare -Ar PACKAGE_PATHS=(
    [general_apps]=general_apps [ubuntu_setting]=ubuntu_setting
    [mozc]=mozc [hazkey]=hazkey [github_ssh]=github_ssh [python]=python
    [docker]=docker [nvidia_container_toolkit]=nvidia_container_toolkit
    [nodejs]=nodejs [ghostty]=ghostty [byobu]=byobu
    [tmux_agent_sidebar]=tmux_agent_sidebar
    [astronvim]=astronvim
)

usage() {
    cat <<'HELP'
Usage: bash install.sh [OPTIONS]
  -i, --install NAME ...  Install selected packages
      --all              Install defaults (excludes hazkey, nvidia_container_toolkit, byobu, and tmux_agent_sidebar)
      --dry              Print selected scripts without running them
  -l, --list             List available packages
  -q, --quiet            Hide installer stdout (stderr remains visible)
  -h, --help             Show this help
HELP
}

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

main() {
    local all=false dry=false quiet=false dependency_failed=false name flag
    local -A requested=()
    local -a selected=() installed=() failed=()
    while (( $# )); do
        case "$1" in
            -h|--help) usage; return ;;
            -l|--list) printf '%s\n' "${PACKAGES[@]}"; return ;;
            --all) all=true; shift ;;
            --dry) dry=true; shift ;;
            -q|--quiet) quiet=true; shift ;;
            -i|--install)
                shift
                (( $# )) && [[ $1 != -* ]] || fail '--install requires at least one package name.'
                while (( $# )) && [[ $1 != -* ]]; do
                    name=$1
                    [[ -n ${PACKAGE_PATHS[$name]:-} ]] || fail "Unknown package: $name"
                    requested["$name"]=1
                    shift
                done
                ;;
            *) fail "Unknown option: $1" ;;
        esac
    done

    # AstroNvim uses Python and Node for its optional REPLs, and npm is needed
    # by plugins such as markdown-preview.nvim. Reuse their dedicated
    # installers instead of installing a second system-managed runtime.
    if [[ -n ${requested[astronvim]:-} ]]; then
        requested[python]=1
        requested[nodejs]=1
    fi

    for name in "${PACKAGES[@]}"; do
        if [[ -n ${requested[$name]:-} ]] ||
            { [[ $all == true ]] && [[ $name != hazkey ]] && [[ $name != nvidia_container_toolkit ]] &&
              [[ $name != byobu ]] && [[ $name != tmux_agent_sidebar ]]; }; then
            selected+=("$name")
        fi
    done
    (( ${#selected[@]} )) || fail 'Select packages with --install or --all. See --help.'
    # Other legacy installers use paths relative to the repository root.
    cd -- "$SCRIPT_DIR"
    for name in "${selected[@]}"; do
        [[ -f installer/${PACKAGE_PATHS[$name]}.sh ]] || fail "Missing installer: $name"
    done
    if [[ $dry == true ]]; then
        for name in "${selected[@]}"; do
            printf '  %s  -->  ./installer/%s.sh\n' "$name" "${PACKAGE_PATHS[$name]}"
        done
        return
    fi

    for name in "${selected[@]}"; do
        if [[ $name == astronvim && $dependency_failed == true ]]; then
            printf 'Skipping astronvim because its Python or Node.js installer failed.\n' >&2
            failed+=("$name")
            continue
        fi
        printf 'Installing %s\n' "$name"
        if [[ $quiet == true ]]; then
            if bash "installer/${PACKAGE_PATHS[$name]}.sh" > /dev/null; then
                installed+=("$name")
            else
                failed+=("$name")
                if [[ $name == python || $name == nodejs ]]; then
                    dependency_failed=true
                fi
            fi
        elif bash "installer/${PACKAGE_PATHS[$name]}.sh"; then
            installed+=("$name")
        else
            failed+=("$name")
            if [[ $name == python || $name == nodejs ]]; then
                dependency_failed=true
            fi
        fi
    done
    if (( ${#installed[@]} )); then
        printf 'Installed: %s\n' "${installed[@]}"
    fi
    if (( ${#failed[@]} )); then
        printf 'Installation failed: %s\n' "${failed[@]}" >&2
        return 1
    fi
    if [[ -t 0 ]] && read -r -p '✅ Logout-Login now? [y/N]: ' flag && [[ $flag == [yY] ]]; then
        gnome-session-quit --no-prompt
    fi
}

main "$@"
