#!/bin/bash
# Sourced by hazkey.sh. Tools live under XDG_DATA_HOME; shell profiles stay intact.

hazkey_fetch() {
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 "$1" -o "$2"
}

hazkey_swift_ready() {
    local info version
    command -v swift >/dev/null || return 1
    info=$(swift --version 2>/dev/null) || return 1
    version=$(sed -nE 's/.*Swift version ([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p' <<< "$info")
    [[ -n $version && $info == *aarch64*linux* ]] && dpkg --compare-versions "$version" ge "$HAZKEY_SWIFT_VERSION"
}

hazkey_cmake_ready() {
    local version
    command -v cmake >/dev/null || return 1
    version=$(cmake --version 2>/dev/null) || return 1
    version=$(sed -nE '1s/cmake version ([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p' <<< "$version")
    [[ -n $version ]] && dpkg --compare-versions "$version" ge "$HAZKEY_MIN_CMAKE_VERSION"
}

hazkey_install_swift() (
    set -euo pipefail
    local destination=$1 platform=$2 stage url
    [[ ! -e $destination ]] || ime_error "Swift導入先を確認してください: $destination"
    stage=$(mktemp -d "${destination}.tmp.XXXXXX")
    trap 'rm -rf -- "$stage"' EXIT
    url="https://download.swift.org/swift-${HAZKEY_SWIFT_VERSION}-release/ubuntu${platform//./}-aarch64/swift-${HAZKEY_SWIFT_VERSION}-RELEASE/swift-${HAZKEY_SWIFT_VERSION}-RELEASE-ubuntu${platform}-aarch64.tar.gz"
    hazkey_fetch "$url" "$stage/swift.tar.gz"
    hazkey_fetch "$url.sig" "$stage/swift.tar.gz.sig"
    hazkey_fetch https://www.swift.org/keys/all-keys.asc "$stage/keys.asc"
    mkdir -m 700 "$stage/gnupg"
    gpg --homedir "$stage/gnupg" --batch --import "$stage/keys.asc"
    gpg --homedir "$stage/gnupg" --batch --verify "$stage/swift.tar.gz.sig" "$stage/swift.tar.gz"
    mkdir "$stage/unpacked"
    tar -xzf "$stage/swift.tar.gz" --strip-components=1 -C "$stage/unpacked"
    "$stage/unpacked/usr/bin/swift" --version
    mv -- "$stage/unpacked" "$destination"
)

hazkey_install_cmake() (
    set -euo pipefail
    local destination=$1 stage
    [[ ! -e $destination ]] || ime_error "CMake導入先を確認してください: $destination"
    stage=$(mktemp -d "${destination}.tmp.XXXXXX")
    trap 'rm -rf -- "$stage"' EXIT
    local archive="cmake-${HAZKEY_CMAKE_VERSION}-linux-aarch64.tar.gz"
    hazkey_fetch "https://github.com/Kitware/CMake/releases/download/v${HAZKEY_CMAKE_VERSION}/${archive}" "$stage/cmake.tar.gz"
    printf '%s  %s\n' "$HAZKEY_CMAKE_SHA256" "$stage/cmake.tar.gz" | sha256sum --check --status
    mkdir "$stage/unpacked"
    tar -xzf "$stage/cmake.tar.gz" --strip-components=1 -C "$stage/unpacked"
    "$stage/unpacked/bin/cmake" --version
    mv -- "$stage/unpacked" "$destination"
)

hazkey_ensure_toolchain() {
    local root platform VERSION_ID
    . /etc/os-release
    case "$VERSION_ID" in
        22.04) platform=22.04 ;;
        24.04|26.04) platform=24.04 ;;
        *) ime_error 'Swift自動導入の対象Ubuntu: 22.04 / 24.04 / 26.04' ;;
    esac
    ime_install_packages curl ca-certificates gnupg tar gzip build-essential \
        libcurl4-openssl-dev libedit-dev libicu-dev libncurses-dev libpython3-dev \
        libsqlite3-dev libxml2-dev libz3-dev pkg-config tzdata uuid-dev zlib1g-dev
    root="${XDG_DATA_HOME:-$HOME/.local/share}/hazkey/toolchains"
    mkdir -p -- "$root"
    if ! hazkey_swift_ready; then
        if [[ ! -x $root/swift-${HAZKEY_SWIFT_VERSION}-ubuntu$platform/usr/bin/swift ]]; then
            hazkey_install_swift "$root/swift-${HAZKEY_SWIFT_VERSION}-ubuntu$platform" "$platform"
        fi
        export PATH="$root/swift-${HAZKEY_SWIFT_VERSION}-ubuntu$platform/usr/bin:$PATH"
        hash -r
    fi
    if ! hazkey_cmake_ready; then
        if [[ ! -x $root/cmake-${HAZKEY_CMAKE_VERSION}/bin/cmake ]]; then
            hazkey_install_cmake "$root/cmake-${HAZKEY_CMAKE_VERSION}"
        fi
        export PATH="$root/cmake-${HAZKEY_CMAKE_VERSION}/bin:$PATH"
        hash -r
    fi
    hazkey_swift_ready || ime_error 'Swiftの自動導入後の確認に失敗しました。'
    hazkey_cmake_ready || ime_error 'CMakeの自動導入後の確認に失敗しました。'
}
