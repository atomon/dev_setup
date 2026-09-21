#!/bin/bash
# Install Hazkey and its runtime. Configuration is handled by hazkey_setup.sh.

hazkey_usage() {
    echo 'Usage: bash installer/hazkey.sh'
    echo 'Hazkey + Fcitx 5 + Mozcを導入し、入力ソース登録とZenzaiの設定を自動で行います。'
    echo 'amd64: 公式deb / arm64: Swift・CMakeが不足していれば自動導入してビルド'
}

hazkey_assert_source_install_is_safe() {
    if [[ $(dpkg-query -W -f='${Status}' fcitx5-hazkey 2>/dev/null || true) == 'install ok installed' ]]; then
        ime_error '既存のfcitx5-hazkeyパッケージがあります。ソース版との混在を避けるため停止します。'
    fi
}

hazkey_download_deb() {
    local destination=$1

    ime_install_packages curl ca-certificates
    hazkey_fetch "${HAZKEY_REPOSITORY}/releases/download/$HAZKEY_VERSION/$HAZKEY_DEB_ASSET" "$destination"
    printf '%s  %s\n' "$HAZKEY_SHA256" "$destination" | sha256sum --check --status
}

hazkey_install_runtime() {
    ime_install_packages "$@" "${HAZKEY_RUNTIME_PACKAGES[@]}"
}

hazkey_build_arm64() {
    local build_dir=$1 backend=$2
    local -a build_packages=(
        ca-certificates git build-essential gettext
        ninja-build pkg-config libfcitx5core-dev libfcitx5config-dev libfcitx5utils-dev
        qt6-base-dev qt6-tools-dev qt6-tools-dev-tools qt6-l10n-tools
        libglx-dev libgl1-mesa-dev libxkbcommon-dev protobuf-compiler libprotobuf-dev
        libprotoc-dev libicu-dev libcurl4-openssl-dev libxml2-dev libsqlite3-dev
        libncurses-dev libedit-dev libzstd-dev zlib1g-dev
    )

    ime_install_packages "${build_packages[@]}"
    git clone --branch "$HAZKEY_VERSION" --depth 1 "${HAZKEY_REPOSITORY}.git" "$build_dir/source"
    [[ $(git -C "$build_dir/source" rev-parse HEAD) == "$HAZKEY_COMMIT" ]] || \
        ime_error 'Hazkeyのソースが検証済みコミットと一致しません。'
    git -C "$build_dir/source" submodule update --init --recursive
    cmake -S "$build_dir/source" -B "$build_dir/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
        -DHAZKEY_SERVER_ENABLE_ZENZAI=ON -DGGML_VULKAN="$(hazkey_vulkan_option "$backend")" \
        -DGGML_CPU_ALL_VARIANTS=OFF -DGGML_CPU_ARM_ARCH=armv8-a
    cmake --build "$build_dir/build" --parallel "${CMAKE_BUILD_PARALLEL_LEVEL:-2}"
}

hazkey_install_source() {
    local build_dir=$1

    # Use the preflighted CMake, even if sudo's secure_path differs.
    sudo "$(command -v cmake)" --install "$build_dir/build"
    printf 'ソース版の導入ファイル一覧: %s/build/install_manifest.txt\n' "$build_dir"
}

hazkey_install_amd64() (
    set -euo pipefail
    local download_dir

    download_dir=$(mktemp -d)
    trap 'rm -rf -- "$download_dir"' EXIT
    hazkey_download_deb "$download_dir/$HAZKEY_DEB_ASSET"
    hazkey_install_runtime "$download_dir/$HAZKEY_DEB_ASSET"
)

hazkey_install_arm64() {
    local backend=$1 build_root build_dir

    hazkey_assert_source_install_is_safe
    [[ $(hazkey_vulkan_option "$backend") == ON ]] && ime_install_packages libvulkan-dev glslc
    hazkey_ensure_toolchain
    build_root="${XDG_CACHE_HOME:-$HOME/.cache}/hazkey-build"
    mkdir -p -- "$build_root"
    build_dir=$(mktemp -d "$build_root/${HAZKEY_VERSION}-arm64.XXXXXX")
    printf 'ビルド保存先: %s\n' "$build_dir"
    hazkey_build_arm64 "$build_dir" "$backend"
    hazkey_install_runtime
    hazkey_install_source "$build_dir"
}

hazkey_install() {
    local architecture=$1 backend=$2

    case "$architecture" in
        amd64) hazkey_install_amd64 ;;
        arm64) hazkey_install_arm64 "$backend" ;;
        *) ime_error '対応アーキテクチャ: amd64 / arm64 (aarch64)' ;;
    esac
}
