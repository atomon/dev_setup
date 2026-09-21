#!/usr/bin/env bash
# Install Docker Engine with Docker's official convenience installer.
set -Eeuo pipefail

readonly DOCKER_INSTALLER_URL='https://get.docker.com'
readonly -a CONFLICTING_PACKAGES=(
  docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker
  containerd runc
)
WORK_DIR=''
DOCKER_INSTALLER=''

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -n ${WORK_DIR:-} && -d $WORK_DIR ]] && rm -rf -- "$WORK_DIR"
  return 0
}
trap cleanup EXIT

require_ubuntu() {
  local architecture

  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == ubuntu ]] || die 'This installer currently supports Ubuntu only.'
  architecture=$(dpkg --print-architecture)
  case "$architecture" in
    amd64|arm64|armhf|ppc64el|s390x) ;;
    *) die "Unsupported Docker Engine architecture: $architecture" ;;
  esac
}

docker_is_installed() {
  command -v docker >/dev/null 2>&1
}

user_in_docker_group() {
  local user=$1 groups

  groups=$(id -nG "$user")
  [[ " $groups " == *' docker '* ]]
}

ensure_docker_group_membership() {
  local user
  user=$(id -un)

  sudo groupadd --force docker
  if user_in_docker_group "$user"; then
    printf 'User %s is already in the docker group.\n' "$user"
  else
    sudo usermod -aG docker "$user"
    printf 'Added %s to the docker group. Log out and log back in before using Docker without sudo.\n' "$user"
  fi
}

warn_if_plugin_missing() {
  local plugin=$1
  shift

  "$@" >/dev/null 2>&1 || printf 'Warning: Docker %s plugin is not available in the existing installation.\n' "$plugin" >&2
}

verify_existing_docker() {
  sudo docker info >/dev/null || die 'Docker is installed but its daemon is unavailable. Start or repair the existing Docker installation first.'
  printf 'Docker is already installed; preserving the existing installation.\n'
  warn_if_plugin_missing compose sudo docker compose version
  warn_if_plugin_missing buildx sudo docker buildx version
}

package_is_installed() {
  local package=$1 status

  status=$(dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null || true)
  [[ $status == installed ]]
}

find_conflicting_packages() {
  CONFLICTING_INSTALLED=()
  local package

  for package in "${CONFLICTING_PACKAGES[@]}"; do
    if package_is_installed "$package"; then
      CONFLICTING_INSTALLED+=("$package")
    fi
  done
}

remove_conflicting_packages() {
  find_conflicting_packages
  if (( ${#CONFLICTING_INSTALLED[@]} )); then
    printf 'Packages that conflict with Docker Engine: %s\n' "${CONFLICTING_INSTALLED[*]}"
    [[ ${DOCKER_REMOVE_CONFLICTING_PACKAGES:-0} == 1 ]] || die \
      'Review the impact of removing these packages, then rerun with DOCKER_REMOVE_CONFLICTING_PACKAGES=1.'
    printf 'Removing conflicting packages.\n'
    sudo apt-get remove -y "${CONFLICTING_INSTALLED[@]}"
  fi
}

prepare_download() {
  WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/docker-install.XXXXXX")
  DOCKER_INSTALLER="$WORK_DIR/get-docker.sh"
}

download_docker_installer() {
  prepare_download
  curl -fsSL "$DOCKER_INSTALLER_URL" -o "$DOCKER_INSTALLER"
  [[ -s $DOCKER_INSTALLER ]] || die "Could not download Docker's official installer."
}

install_docker_engine() {
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends ca-certificates curl
  remove_conflicting_packages
  download_docker_installer
  sudo sh "$DOCKER_INSTALLER"
}

start_docker_service() {
  sudo systemctl enable --now docker
  sudo systemctl is-active --quiet docker || die 'Docker did not become active after installation.'
}

verify_docker_installation() {
  # The current login session does not gain the new docker group until logout/login.
  sudo docker version --format '{{.Server.Version}}' >/dev/null || die 'Docker CLI cannot communicate with the daemon.'
  sudo docker compose version >/dev/null || die 'Docker Compose plugin is unavailable after installation.'
  sudo docker buildx version >/dev/null || die 'Docker Buildx plugin is unavailable after installation.'
  printf 'Verifying Docker with the hello-world container...\n'
  sudo docker run --rm hello-world
}

setup_docker() {
  if docker_is_installed; then
    verify_existing_docker
  else
    install_docker_engine
    start_docker_service
    verify_docker_installation
  fi
}

main() {
  (( EUID != 0 )) || die 'Run this installer as a regular user; it invokes sudo only where required.'
  require_ubuntu

  setup_docker
  ensure_docker_group_membership
  printf '%s\n' 'Docker setup completed.'
  printf '%s\n' 'Warning: membership in the docker group grants root-level privileges. Log out and log back in for the membership change to take effect.'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
