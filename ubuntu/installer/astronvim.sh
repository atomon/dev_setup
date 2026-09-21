#!/usr/bin/env bash

# Install a supported Neovim and the default AstroNvim configuration on Ubuntu.
set -Eeuo pipefail

readonly MIN_NVIM_MINOR=11
readonly NVIM_VERSION="${NVIM_VERSION:-v0.11.6}"
readonly ASTRONVIM_TEMPLATE_REPOSITORY="${ASTRONVIM_TEMPLATE_REPOSITORY:-https://github.com/atomon/astronvim_v6.git}"
readonly CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
readonly STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
readonly CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
readonly SYSTEM_OPT='/opt'
readonly SYSTEM_BIN='/usr/local/bin'
readonly BASH_ALIASES_PATH="$HOME/.bash_aliases"
readonly NVIM_ALIAS="alias v='nvim'"
readonly BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"

NVIM_BIN=''
declare -a TEMP_DIRECTORIES=()

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

path_exists() {
  [[ -e $1 || -L $1 ]]
}

is_enabled() {
  [[ ${1:-0} == 1 ]]
}

cleanup() {
  local directory
  for directory in "${TEMP_DIRECTORIES[@]}"; do
    [[ -d $directory ]] && rm -rf -- "$directory"
  done
  return 0
}
trap cleanup EXIT

backup_existing_path() {
  local path=$1 backup_path index=1
  path_exists "$path" || return 0

  backup_path="${path}.before-astronvim.${BACKUP_SUFFIX}"
  while path_exists "$backup_path"; do
    backup_path="${path}.before-astronvim.${BACKUP_SUFFIX}.${index}"
    ((index += 1))
  done
  mv -- "$path" "$backup_path"
  printf 'Backed up %s to %s\n' "$path" "$backup_path"
}

backup_system_path() {
  local path=$1 backup_path index=1
  path_exists "$path" || return 0

  backup_path="${path}.before-astronvim.${BACKUP_SUFFIX}"
  while path_exists "$backup_path"; do
    backup_path="${path}.before-astronvim.${BACKUP_SUFFIX}.${index}"
    ((index += 1))
  done
  sudo mv -- "$path" "$backup_path"
  printf 'Backed up %s to %s\n' "$path" "$backup_path"
}

detect_architecture() {
  case $(uname -m) in
    x86_64) printf '%s\n' x86_64 ;;
    aarch64|arm64) printf '%s\n' arm64 ;;
    *) die "Unsupported architecture: $(uname -m) (supported: x86_64, arm64)" ;;
  esac
}

nvim_version() {
  local version
  command -v nvim >/dev/null 2>&1 || return 1
  version=$(nvim --version 2>/dev/null | sed -n '1s/^NVIM v\([0-9][0-9.]*\).*/\1/p')
  [[ -n $version ]] || return 1
  printf '%s\n' "$version"
}

is_supported_nvim_version() {
  local version=$1 major minor
  [[ $version =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]] || return 1
  major=${BASH_REMATCH[1]}
  minor=${BASH_REMATCH[2]}
  (( 10#$major > 0 || (10#$major == 0 && 10#$minor >= MIN_NVIM_MINOR) ))
}

clipboard_package() {
  if [[ ${XDG_SESSION_TYPE:-} == wayland ]]; then
    printf '%s\n' wl-clipboard
  else
    printf '%s\n' xsel
  fi
}

install_requirements() {
  local -a packages=(ca-certificates curl git unzip tar gzip build-essential ripgrep)
  packages+=("$(clipboard_package)")

  # Mason can install Tree-sitter itself when the package is unavailable.
  if apt-cache show tree-sitter-cli >/dev/null 2>&1; then
    packages+=(tree-sitter-cli)
  else
    printf 'tree-sitter-cli is unavailable from APT; Mason will install it when needed.\n' >&2
  fi

  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
}

install_neovim() {
  local arch work_dir archive_path asset_url extracted_dir install_dir
  arch=$(detect_architecture)
  [[ $NVIM_VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'NVIM_VERSION must be a stable tag, e.g. v0.11.6'

  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/astronvim-nvim.XXXXXX")
  TEMP_DIRECTORIES+=("$work_dir")
  archive_path="$work_dir/nvim-linux-${arch}.tar.gz"
  asset_url="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-${arch}.tar.gz"
  extracted_dir="$work_dir/nvim-linux-${arch}"
  install_dir="$SYSTEM_OPT/nvim-${NVIM_VERSION#v}-${arch}"

  printf 'Installing Neovim %s for %s\n' "$NVIM_VERSION" "$arch"
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$asset_url" -o "$archive_path"
  tar -xzf "$archive_path" -C "$work_dir"
  [[ -x $extracted_dir/bin/nvim ]] || die 'Downloaded Neovim archive does not contain bin/nvim.'

  sudo install -d -m 755 "$SYSTEM_OPT"
  backup_system_path "$install_dir"
  sudo mv -- "$extracted_dir" "$install_dir"
  NVIM_BIN="$install_dir/bin/nvim"
  install_system_nvim_link "$NVIM_BIN"
  printf 'Neovim installed at %s\n' "$NVIM_BIN"
}

ensure_neovim() {
  local version
  if version=$(nvim_version) && is_supported_nvim_version "$version"; then
    NVIM_BIN=$(command -v nvim)
    printf 'Using existing supported Neovim %s at %s\n' "$version" "$NVIM_BIN"
  else
    install_neovim
  fi
}

install_system_nvim_link() {
  local target=$1 link="$SYSTEM_BIN/nvim" resolved_target backup_link
  sudo install -d -m 755 "$SYSTEM_BIN"

  if path_exists "$link"; then
    resolved_target=$(readlink -f -- "$link" 2>/dev/null || true)
    if [[ -L $link && $resolved_target == "$target" ]]; then
      return
    elif [[ -L $link && $resolved_target == "$SYSTEM_OPT"/nvim-*/bin/nvim ]]; then
      backup_link="${link}.before-astronvim.${BACKUP_SUFFIX}"
      sudo mv -- "$link" "$backup_link"
      printf 'Backed up %s to %s\n' "$link" "$backup_link"
    else
      die "$link already exists and is not managed by this installer; refusing to replace it."
    fi
  fi

  sudo ln -s -- "$target" "$link"
  printf 'Linked %s to %s\n' "$link" "$target"
}

ensure_nvim_alias() {
  touch "$BASH_ALIASES_PATH"
  if grep -Eq '^[[:space:]]*alias[[:space:]]+v=' "$BASH_ALIASES_PATH"; then
    printf 'Existing v alias preserved in %s\n' "$BASH_ALIASES_PATH"
    return
  fi

  printf '\n%s\n' "$NVIM_ALIAS" >> "$BASH_ALIASES_PATH"
  printf 'Added v alias to %s\n' "$BASH_ALIASES_PATH"
}

install_nerd_font() {
  local work_dir archive_path font_dir
  if ! is_enabled "${INSTALL_NERD_FONT:-1}"; then
    printf 'Nerd Font installation skipped (INSTALL_NERD_FONT=0).\n'
    return
  fi

  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/astronvim-font.XXXXXX")
  TEMP_DIRECTORIES+=("$work_dir")
  archive_path="$work_dir/CascadiaCode.zip"
  font_dir="$DATA_HOME/fonts/CascadiaCode"

  if [[ -f $font_dir/CaskaydiaCoveNerdFontMono-Regular.ttf ]]; then
    printf 'CascadiaCode Nerd Font is already installed in %s\n' "$font_dir"
    return
  fi

  mkdir -p "$font_dir"
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip \
    -o "$archive_path"
  unzip -oq "$archive_path" -d "$font_dir"
  command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$font_dir"
  printf 'Installed CascadiaCode Nerd Font in %s\n' "$font_dir"
}

backup_neovim_paths() {
  backup_existing_path "$CONFIG_HOME/nvim"
  backup_existing_path "$DATA_HOME/nvim"
  backup_existing_path "$STATE_HOME/nvim"
  backup_existing_path "$CACHE_HOME/nvim"
}

install_astronvim_config() {
  local config_dir work_dir template_dir
  config_dir="$CONFIG_HOME/nvim"
  [[ -n $ASTRONVIM_TEMPLATE_REPOSITORY ]] || die 'ASTRONVIM_TEMPLATE_REPOSITORY must not be empty.'

  if path_exists "$config_dir" && ! is_enabled "${ASTRONVIM_REINSTALL:-0}"; then
    printf 'Existing Neovim configuration preserved at %s\n' "$config_dir"
    return
  fi

  mkdir -p "$CONFIG_HOME"
  work_dir=$(mktemp -d "$CONFIG_HOME/.astronvim-template.XXXXXX")
  TEMP_DIRECTORIES+=("$work_dir")
  template_dir="$work_dir/nvim"

  # Clone before moving old data, so a failed download leaves it untouched.
  git clone --depth 1 "$ASTRONVIM_TEMPLATE_REPOSITORY" "$template_dir"
  if path_exists "$config_dir"; then
    backup_neovim_paths
  elif is_enabled "${ASTRONVIM_REINSTALL:-0}"; then
    backup_neovim_paths
  fi
  mv -- "$template_dir" "$config_dir"
  printf 'Installed the AstroNvim configuration from %s in %s\n' "$ASTRONVIM_TEMPLATE_REPOSITORY" "$config_dir"
}

bootstrap_astronvim() {
  printf 'Bootstrapping AstroNvim plugins with lazy.nvim...\n'
  "$NVIM_BIN" --headless '+Lazy! sync' '+qa'
  [[ -d $DATA_HOME/nvim/lazy/lazy.nvim ]] || die 'lazy.nvim was not installed successfully.'
  [[ -d $DATA_HOME/nvim/lazy/AstroNvim ]] || die 'AstroNvim was not installed successfully.'
}

main() {
  [[ $EUID -ne 0 ]] || die 'Run this script as the desktop user, not as root.'
  install_requirements
  ensure_neovim
  ensure_nvim_alias
  install_nerd_font
  install_astronvim_config
  bootstrap_astronvim
  printf 'AstroNvim installation completed. Run :checkhealth in Neovim to inspect optional providers.\n'
  printf 'Use a true-color terminal and select CascadiaCode Nerd Font in the terminal settings for icons.\n'
  printf 'Open a new Bash terminal before using the v alias.\n'
}

main "$@"
