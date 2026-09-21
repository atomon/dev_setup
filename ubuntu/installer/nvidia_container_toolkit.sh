#!/usr/bin/env bash
# Configure Docker to expose an installed NVIDIA GPU to containers on Ubuntu.
set -Eeuo pipefail

readonly NVIDIA_KEYRING='/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg'
readonly NVIDIA_REPOSITORY='/etc/apt/sources.list.d/nvidia-container-toolkit.list'
readonly DOCKER_DAEMON_CONFIG='/etc/docker/daemon.json'
readonly BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"

WORK_DIR=''

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -n ${WORK_DIR:-} && -d $WORK_DIR ]] && rm -rf -- "$WORK_DIR"
  return 0
}
trap cleanup EXIT

has_nvidia_gpu() {
  if command -v lspci >/dev/null 2>&1; then
    lspci -nn | grep -qi 'nvidia'
  elif [[ -d /proc/driver/nvidia/gpus ]]; then
    find /proc/driver/nvidia/gpus -mindepth 1 -maxdepth 1 -print -quit | grep -q .
  else
    command -v nvidia-smi >/dev/null 2>&1
  fi
}

require_ubuntu() {
  # The NVIDIA repository configured below is the official Debian/Ubuntu one.
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ ${ID:-} == ubuntu ]] || die 'This installer currently supports Ubuntu only.'
}

require_docker_and_driver() {
  command -v docker >/dev/null 2>&1 || die 'Docker is not installed. Run: bash install.sh -i docker'
  command -v nvidia-smi >/dev/null 2>&1 || die 'The NVIDIA driver is not installed or nvidia-smi is unavailable.'
  nvidia-smi -L >/dev/null || die 'The NVIDIA driver is installed but no GPU is usable by nvidia-smi.'
  sudo systemctl is-active --quiet docker || die 'The Docker service is not active.'
}

configure_nvidia_repository() {
  local key_file repository_file

  WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nvidia-container-toolkit.XXXXXX")
  key_file="$WORK_DIR/nvidia-container-toolkit-keyring.gpg"
  repository_file="$WORK_DIR/nvidia-container-toolkit.list"

  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey |
    gpg --dearmor --batch --yes --output "$key_file"
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' \
      > "$repository_file"
  [[ -s $key_file && -s $repository_file ]] || die 'Could not retrieve the NVIDIA Container Toolkit repository.'

  sudo install -d -m 755 /usr/share/keyrings /etc/apt/sources.list.d
  sudo install -m 644 "$key_file" "$NVIDIA_KEYRING"
  sudo install -m 644 "$repository_file" "$NVIDIA_REPOSITORY"
}

install_toolkit() {
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends ca-certificates curl gnupg
  configure_nvidia_repository
  sudo apt-get update
  sudo apt-get install -y nvidia-container-toolkit
  command -v nvidia-ctk >/dev/null 2>&1 || die 'nvidia-container-toolkit was installed but nvidia-ctk is unavailable.'
}

ensure_safe_to_restart_docker() {
  local running_containers

  running_containers=$(sudo docker ps -q)
  if [[ -n $running_containers && ${NVIDIA_CONTAINER_TOOLKIT_ALLOW_DOCKER_RESTART:-0} != 1 ]]; then
    die 'Docker has running containers. Stop them first, or explicitly set NVIDIA_CONTAINER_TOOLKIT_ALLOW_DOCKER_RESTART=1.'
  fi
}

configure_docker_runtime() {
  local runtimes

  runtimes=$(sudo docker info --format '{{json .Runtimes}}')
  if grep -q '"nvidia"' <<< "$runtimes"; then
    printf 'NVIDIA runtime is already registered with Docker.\n'
    return
  fi

  ensure_safe_to_restart_docker
  if sudo test -f "$DOCKER_DAEMON_CONFIG"; then
    sudo cp -- "$DOCKER_DAEMON_CONFIG" "${DOCKER_DAEMON_CONFIG}.before-nvidia-container-toolkit-${BACKUP_SUFFIX}"
    printf 'Backed up %s before updating it.\n' "$DOCKER_DAEMON_CONFIG"
  fi
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
  sudo systemctl is-active --quiet docker || die 'Docker did not become active after configuring the NVIDIA runtime.'
}

verify_gpu_container() {
  printf 'Verifying GPU access from a Docker container...\n'
  sudo docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
}

main() {
  (( EUID != 0 )) || die 'Run this installer as a regular user; it invokes sudo only where required.'
  require_ubuntu
  if ! has_nvidia_gpu; then
    printf 'No NVIDIA GPU detected; skipping NVIDIA Container Toolkit setup.\n'
    return
  fi

  require_docker_and_driver
  install_toolkit
  configure_docker_runtime
  verify_gpu_container
  printf '%s\n' 'NVIDIA Container Toolkit setup completed.'
  printf '%s\n' 'Note: on some systems, `systemctl daemon-reload` can make GPUs disappear from running containers; restart affected containers if that occurs.'
}

main "$@"
