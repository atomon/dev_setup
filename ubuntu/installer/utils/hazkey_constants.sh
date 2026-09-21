#!/bin/bash

# Release inputs are kept in one file so the deb, source, and model paths
# cannot silently drift apart when Hazkey is upgraded.
readonly HAZKEY_VERSION=0.2.1
readonly HAZKEY_COMMIT=596108c126449abcce2716a3e20d80106fb83890
readonly HAZKEY_SHA256=a9d394f38e6ee47e84f1e0f6aa742bc555a324501e3dca57d24027f784f0d758
readonly HAZKEY_REPOSITORY=https://github.com/7ka-Hiira/hazkey
readonly HAZKEY_DEB_ASSET="fcitx5-hazkey_${HAZKEY_VERSION}-1_amd64.deb"
readonly HAZKEY_SWIFT_VERSION=6.2
readonly HAZKEY_MIN_CMAKE_VERSION=3.31
readonly HAZKEY_CMAKE_VERSION=4.1.3
readonly HAZKEY_CMAKE_SHA256=06bb6c4d5d4a31b95ad419a4c8efb88364fa72077ba7a29c909e7b658760f6b3
readonly ZENZAI_MODEL_URL=https://huggingface.co/Miwa-Keita/zenz-v3.1-small-gguf/resolve/main/ggml-model-Q5_K_M.gguf
readonly ZENZAI_MODEL_SHA256=4de930c06bef8c263aa1aa40684af206db4ce1b96375b3b8ed0ea508e0b14f6c
readonly -a HAZKEY_RUNTIME_PACKAGES=(
    fcitx5 fcitx5-config-qt im-config
    fcitx5-frontend-gtk3 fcitx5-frontend-gtk4
    fcitx5-frontend-qt5 fcitx5-frontend-qt6
    fcitx5-mozc mozc-utils-gui fonts-noto-cjk
)
