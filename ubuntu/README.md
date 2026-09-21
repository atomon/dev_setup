# Setup Linux

## Install git
```bash
sudo apt update && sudo apt install git
```

## Clone repository
```bash
mkdir -p Documents/Github
git clone https://github.com/atomon/dev_setup.git
```

## Usage command
```bash
$ cd dev_setup/ubuntu
$ bash install.sh -i general_apps python
```

## Docker

```bash
bash install.sh -i docker
```

新規導入では Docker 公式の convenience script (`https://get.docker.com`) を一時領域へ
ダウンロードして実行し、`hello-world` コンテナで動作確認します。既に `docker` コマンドが
ある環境では、導入済みのパッケージ・コンテナ・イメージ・設定を置換せず、デーモンの
 疎通だけを確認します。

この公式スクリプトは開発・検証環境向けです。本番環境では、Docker のスクリプト内容を
確認してから実行してください。

Docker を `sudo` なしで実行できるように、実行ユーザーを `docker` グループに追加します。
反映にはデスクトップまたは SSH セッションから一度ログアウト・ログインが必要です。
このグループには root 相当の権限があるため、信頼できるユーザーだけを追加してください。

`docker.io`、`containerd`、`runc` など Docker Engine と競合するパッケージがある場合、
スクリプトは削除対象を表示して停止します。Kubernetes などへの影響を確認した上で削除を
許可する場合だけ、次を実行してください。

```bash
DOCKER_REMOVE_CONFLICTING_PACKAGES=1 bash install.sh -i docker
```

## Python

`python` は uv と uv 管理の CPython 3.13 を導入します。pyenv、Poetry、pipx は導入しません。
別の Python minor version を使う場合は、実行時に指定できます。

```bash
PYTHON_VERSION=3.14 bash install.sh -i python
```

## Ubuntu GNOMEの個人設定

```bash
bash install.sh -i ubuntu_setting
```

ログイン済みのUbuntu GNOMEセッションで実行してください。Bash履歴を20,000件・時刻表示に設定し、
`reload` alias、`~/Apps`、端末の最大化起動、Vivaldi導入済み時の自動起動、
Caps Lock→Ctrl、個人用ショートカットを設定します。既存のカスタムショートカットは保持します。

ショートカットは `Super`+`Shift`+`S`（サスペンド）、`R`（再起動）、`U`（電源オフ）、
`E`（ログアウト）です。再起動・電源オフ・ログアウトにはGNOMEの確認画面を表示します。
設定前の状態は `${XDG_STATE_HOME:-~/.local/state}/dev_setup/ubuntu_setting/` に保存されます。

```bash
bash installer/ubuntu_setting.sh --dry-run
bash installer/ubuntu_setting.sh --undo
```

WindowsとのデュアルブートでRTCをローカル時刻にする必要がある場合だけ、次を使います。

```bash
bash installer/ubuntu_setting.sh --local-rtc
```

## AstroNvim

```bash
bash install.sh -i astronvim
```

AstroNvim v6 requires Neovim 0.11 or newer. The installer reuses a compatible
existing `nvim`; otherwise it installs the pinned stable Neovim release into
`/opt/nvim-*` and creates `/usr/local/bin/nvim`. It installs the AstroNvim
`https://github.com/atomon/astronvim_v6.git` configuration template and
bootstraps its plugins with lazy.nvim. The configuration remains a Git clone so
it can be updated later. To use a different template for one installation, set
`ASTRONVIM_TEMPLATE_REPOSITORY` to its clone URL.

The installer adds `alias v='nvim'` to `~/.bash_aliases` when no `v` alias is
already configured. Open a new Bash terminal to use the alias.

An existing `~/.config/nvim` is never replaced by default. To replace it after
timestamped backups of the config, data, state, and cache directories, run:

```bash
ASTRONVIM_REINSTALL=1 bash install.sh -i astronvim
```

Without `ASTRONVIM_REINSTALL=1`, subsequent runs preserve the existing
configuration and synchronize its installed plugins.

The installer installs CascadiaCode Nerd Font by default. To skip it:

```bash
INSTALL_NERD_FONT=0 bash install.sh -i astronvim
```

The installer uses `wl-clipboard` in Wayland sessions and `xsel` otherwise.
`ripgrep` and Tree-sitter CLI are installed when available; Node, Python,
lazygit, gdu, and bottom remain optional tools and are not pulled in solely by
AstroNvim.

## Ghostty

```bash
bash install.sh -i ghostty
```

Ubuntu 26.04以降ではUbuntu公式リポジトリの `ghostty` パッケージを導入します。
Ubuntu 24.04では、[Ghostty公式ドキュメント](https://ghostty.org/docs/install/binary#debian-and-ubuntu)
で案内される `mkasberg/ghostty-ubuntu` の最新 `.deb` を一時ディレクトリへダウンロードして導入します。
この `.deb` はコミュニティビルドであり、Ghosttyプロジェクトは公式・ディストリビューション提供の
パッケージより信頼上のリスクが高いと明記しています。必要に応じてリリース内容を確認してから実行してください。

導入後は `ghostty --version` で確認できます。設定ファイルは
`${XDG_CONFIG_HOME:-~/.config}/ghostty/config` です。
インストーラーは既定ターミナルもGhosttyへ変更します。Ubuntu 24.04ではシステムの
`x-terminal-emulator` alternatives、26.04以降ではユーザーの
`${XDG_CONFIG_HOME:-~/.config}/ubuntu-xdg-terminals.list` を設定します。

## NVIDIA GPU を Docker で使用する

NVIDIA GPU と動作する NVIDIA ドライバ、および Docker を導入済みの場合は、次を
実行します。

```bash
bash install.sh -i nvidia_container_toolkit
```

NVIDIA の公式 APT リポジトリから NVIDIA Container Toolkit を導入し、Docker の
`nvidia` runtime を設定して、`ubuntu nvidia-smi` コンテナで GPU が見えることまで
確認します。Docker の設定変更時にはサービスを再起動するため、実行中のコンテナが
ある場合は停止します。明示的に許可する場合だけ、次で続行できます。

```bash
NVIDIA_CONTAINER_TOOLKIT_ALLOW_DOCKER_RESTART=1 bash install.sh -i nvidia_container_toolkit
```

GPU のないマシンでは設定を変更せず正常終了します。Docker コンテナを通常ユーザーで
実行するには、Docker のセットアップ後に一度ログアウト・ログインしてください。
このセットアップは副作用が大きいため `--all` には含めません。

## 日本語入力

Ubuntu GNOMEのログイン済み端末から、スクリプト全体に `sudo` を付けず実行します。
パッケージ導入時だけスクリプトが `sudo` を使います。

### Hazkey＋Zenzaiを試す（Mozcも残す）

```bash
bash installer/hazkey.sh
# または bash install.sh -i hazkey
```

Ubuntu amd64では公式Hazkey 0.2.1を固定SHA-256で検証して導入します。
arm64（aarch64）では0.2.1の固定コミットからソースビルドします。実行コマンドは同じです。
Fcitx 5と `fcitx5-mozc` も導入し、同じ入力基盤上でHazkeyとMozcを比較できます。
既存のIBusパッケージ・Mozc辞書・GNOME入力ソースは削除しません。
`im-config -n fcitx5`、`~/.config/environment.d/90-fcitx5.conf`、`~/.pam_environment` によるユーザー設定の変更は再ログイン後に反映されます。
GNOMEのログインセッションにもFcitx 5の環境変数を渡すため、`~/.pam_environment` を作成します。
既存の `~/.xinputrc`、`~/.config/environment.d/90-fcitx5.conf`、`~/.pam_environment` があれば、変更前に `*.before-hazkey.*` へ保存します。
`--all` ではHazkeyは導入しません。試す場合は明示的に指定してください。

スクリプトが次を自動で行います。

1. arm64で不足しているSwift・CMakeをユーザー領域へ導入します。
2. Hazkey・Fcitx 5・Mozcを導入します。
3. 公式GUIと同じZenzaiモデルをダウンロードし、SHA-256を検証します。
4. 既存のキーボード配列と入力ソースを保持して、Fcitx 5の各グループにHazkey・Mozcを追加します。
5. `~/.config/environment.d/90-fcitx5.conf` と `~/.pam_environment` を作成し、GTK・Qt・SDL・XIM互換アプリおよびGNOMEログインセッションの入力環境をFcitx 5へ統一します。
6. Hazkeyの各プロファイルでZenzaiを有効にし、Vulkan GPUが利用できればGPUを選択します。

完了後は作業を保存してログアウト・再ログインしてください。
`fcitx5-configtool` での追加や `hazkey-settings` からのモデル取得は不要です。
新規のFcitx 5設定ではHazkeyを既定にします。既存設定がある場合は現在の既定入力方式を保持するため、
Fcitx 5のメニューでHazkeyを選択してください。Mozcにも同じメニューから切り替えられます。

モデルは約80MBで、保存先は `$XDG_DATA_HOME/hazkey/zenzai/zenzai.gguf`
（通常は `~/.local/share/hazkey/zenzai/zenzai.gguf`）です。
有効な同一モデルは再ダウンロードしません。異なる既存モデルと、変更前の設定ファイルは
同じディレクトリの `*.before-hazkey.*` にバックアップします。
Hazkeyのカスタムキー設定・辞書設定などは保持します。Fcitxの設定ファイルのコメント・整形は再生成されます。

設定ファイルの競合を防ぐため、実行中のFcitx 5とHazkeyサーバーをSIGTERMで終了します。
実行前に編集中の入力を確定し、設定画面を閉じてください。スクリプトは強制ログアウトしません。
モデル取得に失敗した場合は、既存モデル・入力方式設定を変更せず停止します。
IBusとFcitx 5のデーモンを手動で同時起動したり、`.bashrc` に入力関連の環境変数を一律追記したりしないでください。
GNOME Waylandでアプリ固有の入力・候補表示の問題がある場合は、`fcitx5-diagnose` と下記の公式資料を確認してください。

確認する項目は、ブラウザ・エディタ・GTK/Qtアプリでの日本語入力、候補位置、確定、英数への復帰、
`Ctrl+Space` とエディタの補完キーの競合です。よく使う固有名詞や同音異義語で候補の正しさと待ち時間も比較します。
Zenzaiの前文脈利用は、アプリ側の文脈取得への対応にも依存します。

### arm64（aarch64）の自動ビルド

公式0.2.1リリースにはarm64用debがないため、ネイティブビルドを使用します。
Swift ≥ 6.2、CMake ≥ 3.31がPATH上にあれば再利用し、不足しているものだけ自動導入します。
自動導入版はSwift 6.2とCMake 4.1.3に固定しています。
Swiftは公式署名鍵によるGPG検証、CMakeは公式SHA-256による検証を行います。
保存先は `${XDG_DATA_HOME:-~/.local/share}/hazkey/toolchains/` で、シェルの起動設定は変更しません。
ビルド時だけPATHへ追加するため、インストーラー外で利用する場合はこの配下のbinをPATHに追加してください。

Swiftの自動導入はUbuntu 22.04／24.04／26.04を対象とします。
22.04は対応する公式ビルド、24.04と26.04はUbuntu 24.04向けビルドを使います。
26.04との互換性およびaarch64実機でのコンパイルは未検証です。
Swiftのアーカイブは約1GBあり、展開・依存関係・Hazkeyのビルドにもディスク容量と時間が必要です。
その他の依存パッケージはAPTで自動導入します。

Vulkan GPUを検出した場合はZenzaiのVulkanバックエンドも有効にしてビルドします。
検出できない場合はCPUバックエンドのみでビルドします。
CMakeの並列数は既定で2です。必要なら `CMAKE_BUILD_PARALLEL_LEVEL=4 bash installer/hazkey.sh` のように変更できます。
ソース・ビルド結果は `~/.cache/hazkey-build/`（または `$XDG_CACHE_HOME/hazkey-build/`）に残ります。

arm64のHazkey本体は `/usr` にソースインストールするため、APT管理の対象外です。
削除時は実行時に表示される `build/install_manifest.txt` の一覧を確認して対象ファイルを削除してください。
後からdeb版へ移行する場合も、先にソース版の導入ファイルを整理してください。
既存の `fcitx5-hazkey` debがある場合は上書きを避けるため停止します。
Swift標準ライブラリのビルドエラーが出る場合は [Hazkey公式ビルド手順](https://hazkey.hiira.dev/docs/development/build/) の既知問題を確認してください。
スクリプトは既存Swiftツールチェーンのヘッダーを書き換えません。

### IBus＋Mozcを使う／戻す

Fcitx 5上でMozcに切り替えるだけなら、上記メニュー操作で十分です。
GNOME標準のIBus構成へ戻す場合は次を実行し、再ログインしてください。

```bash
bash installer/mozc.sh
im-config -n ibus
rm -f ~/.config/environment.d/90-fcitx5.conf
rm -f ~/.pam_environment
```

GNOMEの「設定 → キーボード → 入力ソース」でMozcを選択します。
Hazkeyスクリプトが作成した `~/.config/autostart/fcitx5.desktop` も不要なら削除し、別途Fcitx 5を自動起動に登録した場合は、そちらも解除してください。
導入前の入力方式設定そのものへ戻したい場合は、保存した `.xinputrc.before-hazkey.*` の該当ファイルを `.xinputrc` に復元します。
導入前に `.xinputrc` がなかった場合は `im-config -n default` でディストリビューションの既定設定に戻せます。

Mozcスクリプトは既存入力ソースにMozcを追加し、日本語UI翻訳パッケージは導入しません。
同梱キーマップを使う場合は、表示される絶対パスのファイルをMozc設定GUIでインポートします。

検証範囲: Ubuntu 26.04.1で公式 `.deb` のハッシュ・メタデータとAPTの依存解決を確認。
実際のインストール、再ログイン後の入力、変換品質は未検証です。
arm64経路は上流のaarch64 CI設定と照合し、分岐・失敗時の停止を模擬検証しています。
aarch64実機でのコンパイル・入力動作は未検証です。

参考: [Hazkey Ubuntu導入](https://hazkey.hiira.dev/docs/install/ubuntu/)、
[0.2.1リリース](https://github.com/7ka-Hiira/hazkey/releases/tag/0.2.1)、
[Zenzaiモデル設定](https://hazkey.hiira.dev/docs/zenzai/setup/)、
[Fcitx 5とWayland](https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland)、
[Swift公式導入](https://www.swift.org/install/linux/tarball/)、
[CMake 4.1.3](https://github.com/Kitware/CMake/releases/tag/v4.1.3)。

## スクリプトの構成と検証

`install.sh` はパッケージ選択・実行順序・結果報告を担当します。
`--dry` で実行対象を確認でき、別の作業ディレクトリからも呼び出せます。
入力方式の共通処理（Ubuntu GNOMEの確認、APT操作、Fcitx 5の選択）は
`installer/utils/input_method.sh` にまとめています。
`installer/hazkey.sh` は事前確認、amd64用deb取得、arm64ビルド、導入後の設定を関数に分けています。
`hazkey_constants.sh` にリリース、CMake、Zenzaiモデルのバージョンと検証値を集約しています。
`hazkey_toolchain.sh` がSwift・CMake、`hazkey_setup.sh` がモデル取得・プロセス停止、
`configure_hazkey.py` が既存ユーザー設定の読み込み・検証・更新を担当します。
Hazkey導入時には `vulkan-tools` も導入し、Vulkan GPUを検出できればZenzaiを
`Vulkan0` などのGPUバックエンドへ自動設定します。複数GPUでは離散GPUを優先します。
検出できない場合はCPUへフォールバックします。arm64ではGPU検出時だけ
`libvulkan-dev` と `glslc` を導入してVulkan対応でビルドします。

回帰テストはパッケージ操作・ネットワーク・デスクトップ設定を模擬し、実環境を変更せずに実行します。

```bash
python3 -B -m unittest discover -s tests -v
```
