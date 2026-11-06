#!/usr/bin/env python3
"""Hazkey 0.2.1・Fcitx 5 のオフライン設定（両方の停止後に実行）"""

import argparse
import configparser
import io
import json
import os
import re
import shutil
import tempfile
from collections.abc import Callable
from pathlib import Path

Profile = dict[str, object]

ZENZAI_INFER_LIMIT = 10
ZENZAI_BACKEND_PATTERN = re.compile(r'CPU|Vulkan[0-9]+')
XKB_RULES = Path('/usr/share/X11/xkb/rules/evdev.lst')
# Fcitx 表記 "us-dvorak" と GNOME 表記 "us+dvorak" の両対応、バリアントは "-" を含みうる
XKB_LAYOUT_PATTERN = re.compile(r'([a-z0-9_]+)(?:[+-]([A-Za-z0-9_-]+))?')
FCITX_ENGINES = ('hazkey', 'mozc')


class _FcitxConfig(configparser.ConfigParser):
    """キー名の大文字・小文字を保持する Fcitx 設定パーサ"""

    def __init__(self) -> None:
        super().__init__(interpolation=None, delimiters=('=',), strict=True)

    def optionxform(self, optionstr: str) -> str:
        return optionstr


def atomic_write(path: Path, content: str) -> None:
    """内容が変わる場合のみ、既存ファイルを退避してから原子的に置き換え"""
    data = content.encode('utf-8')
    if path.exists() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        fd, backup = tempfile.mkstemp(prefix=path.name + '.before-hazkey.', dir=path.parent)
        os.close(fd)
        shutil.copy2(path, backup)
        print(f'設定を保存しました: {backup}')
    fd, temporary = tempfile.mkstemp(prefix=path.name + '.tmp.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def default_hazkey_profile(zenzai_backend: str) -> Profile:
    """上流 0.2.1 の config.swift genDefaultConfig() と同じ既定プロファイル

    Args:
        zenzai_backend: Zenzai の推論デバイス名（CPU・Vulkan0 など）
    """
    keymaps = ['Fullwidth Number', 'Fullwidth Symbol', 'Japanese Symbol', 'Fullwidth Space']
    return {
        'profileName': 'Default',
        'autoConvertMode': 3,
        'auxTextMode': 3,
        'suggestionListMode': 3,
        'numSuggestions': 3,
        'useRichSuggestion': False,
        'numCandidatesPerPage': 9,
        'useRichCandidates': False,
        'useInputHistory': True,
        'stopStoreNewHistory': False,
        'specialConversionMode': dict.fromkeys(
            [
                'commaSeparatedNumber',
                'mailDomain',
                'calendar',
                'time',
                'romanTypography',
                'unicodeCodepoint',
                'hazkeyVersion',
                'halfwidthKatakana',
                'extendedEmoji',
            ],
            True,
        ),
        'enabledKeymaps': [{'name': n, 'isBuiltIn': True, 'filename': n} for n in keymaps],
        'enabledTables': [{'name': 'Romaji', 'isBuiltIn': True, 'filename': 'Romaji'}],
        'submodeEntryPointChars': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        'zenzaiEnable': True,
        'zenzaiBackendDeviceName': zenzai_backend,
        'zenzaiInferLimit': ZENZAI_INFER_LIMIT,
        'zenzaiContextualMode': True,
        'zenzaiProfile': '',
    }


def _snake_case(key: str) -> str:
    """camelCase キーの snake_case 表記"""
    return re.sub(r'(?<!^)(?=[A-Z])', '_', key).lower()


def _has_field(profile: Profile, key: str) -> bool:
    """camelCase・snake_case いずれかの表記でのキー有無"""
    return key in profile or _snake_case(key) in profile


def _set_field(profile: Profile, key: str, value: object) -> None:
    """snake_case 表記の除去と camelCase 表記での値設定

    Protobuf JSON は両表記を受け付けるため、重複表現を防止
    """
    profile.pop(_snake_case(key), None)
    profile[key] = value


def hazkey_config(
    text: str | None, zenzai_backend: str = 'CPU', *, disable_input_history: bool = False
) -> str:
    """全プロファイルで Zenzai を有効化した Hazkey 設定

    Args:
        text: 既存の config.json の内容（未作成なら None）

    Returns:
        書き込む config.json の内容

    Raises:
        ValueError: config.json がプロファイルの配列でない場合
    """
    profiles = json.loads(text) if text is not None else []
    if not isinstance(profiles, list) or any(not isinstance(p, dict) for p in profiles):
        raise ValueError('Hazkey config.json must contain an array of profiles')
    if not profiles:
        profiles = [default_hazkey_profile(zenzai_backend)]
    overrides: Profile = {
        'zenzaiEnable': True,
        'zenzaiBackendDeviceName': zenzai_backend,
        'useDefaultZenzaiSettings': False,
    }
    for profile in profiles:
        for key, value in overrides.items():
            _set_field(profile, key, value)
        if not _has_field(profile, 'zenzaiInferLimit'):
            profile['zenzaiInferLimit'] = ZENZAI_INFER_LIMIT
        if disable_input_history:
            # LearningType.nothing 相当（学習データの読み書きを停止）
            _set_field(profile, 'useInputHistory', False)
    return json.dumps(profiles, ensure_ascii=False, indent=2) + '\n'


def keyboard_layouts() -> list[str]:
    """GNOME の入力ソースから引き継ぐキーボード配列（Fcitx 表記）

    Returns:
        重複を除いた配列名の一覧

    Raises:
        ValueError: 配列を取得できない場合
    """
    from gi.repository import Gio

    settings = Gio.Settings.new('org.gnome.desktop.input-sources')
    sources: list[tuple[str, str]] = settings.get_value('sources').unpack()
    layouts = [name.replace('+', '-', 1) for kind, name in sources if kind == 'xkb']
    if not layouts:
        # 入力ソースが IBus エンジンのみの場合はシステム既定の配列を採用
        text = Path('/etc/default/keyboard').read_text()
        layout = re.search(r'^XKBLAYOUT=[\"\']?([a-z0-9_,]+)', text, re.MULTILINE)
        variant = re.search(r'^XKBVARIANT=[\"\']?([a-z0-9_,]*)', text, re.MULTILINE)
        if layout:
            variants = variant[1].split(',') if variant else []
            layouts = [
                name + ('-' + variants[i] if i < len(variants) and variants[i] else '')
                for i, name in enumerate(layout[1].split(','))
            ]
    if not layouts:
        raise ValueError('既存のキーボード配列を取得できません。GNOMEで配列を設定してください。')
    return list(dict.fromkeys(layouts))


def _xkb_rules(rules: Path) -> tuple[set[str], set[tuple[str, str]]]:
    """XKB ルール一覧（evdev.lst）の配列名と（配列, バリアント）の集合"""
    layouts: set[str] = set()
    variants: set[tuple[str, str]] = set()
    section = None
    for line in rules.read_text().splitlines():
        fields = line.split()
        if line.startswith('!'):
            section = line[1:].strip()
        elif fields and section == 'layout':
            layouts.add(fields[0])
        elif len(fields) >= 2 and section == 'variant':
            # 書式: "  dvorak          us: English (Dvorak)"
            variants.add((fields[1].rstrip(':'), fields[0]))
    return layouts, variants


def xkb_layout(name: str, rules: Path = XKB_RULES) -> str:
    """XKB 配列名の検証と Fcitx 表記への変換

    Args:
        name: 配列名（us・us-dvorak・GNOME 表記の us+dvorak）
        rules: 存在確認に使う XKB ルール一覧（ファイルがなければ形式のみ確認）

    Returns:
        Fcitx 表記の配列名（us・us-dvorak）

    Raises:
        ValueError: 形式が不正、または XKB に存在しない配列の場合
    """
    match = XKB_LAYOUT_PATTERN.fullmatch(name)
    if not match:
        raise ValueError(f'キーボード配列名が不正です: {name!r}（例: us, jp, us+dvorak）')
    layout, variant = match.groups()
    if rules.exists():
        layouts, variants = _xkb_rules(rules)
        if layout not in layouts or (variant and (layout, variant) not in variants):
            raise ValueError(f'XKBに存在しないキーボード配列です: {name}（一覧: {rules}）')
    return f'{layout}-{variant}' if variant else layout


def _switch_layout(config: _FcitxConfig, group: str, items: list[str], layout: str) -> None:
    """グループの既定配列の切り替え

    旧既定配列の keyboard 項目を新配列へ置き換え（新配列が登録済みなら置き換えなし）、
    その他の keyboard 項目は保持
    """
    old, new = 'keyboard-' + config[group]['Default Layout'], f'keyboard-{layout}'
    config[group]['Default Layout'] = layout
    if old == new or any(config[s].get('Name') == new for s in items):
        return
    for section in items:
        if config[section].get('Name') == old:
            config[section]['Name'] = new
    if config[group].get('DefaultIM') == old:
        config[group]['DefaultIM'] = new


def fcitx_profile(
    text: str | None,
    layouts_provider: Callable[[], list[str]] | None = None,
    *,
    layout: str | None = None,
) -> str:
    """全グループに keyboard・Hazkey・Mozc を登録した Fcitx の profile

    Args:
        text: 既存の profile の内容（未作成なら None）
        layouts_provider: 新規作成時の配列取得関数（既定は keyboard_layouts）
        layout: 全グループの既定配列とする配列（Fcitx 表記、None なら既存設定を維持）

    Returns:
        書き込む profile の内容

    Raises:
        ValueError: グループ設定が不完全な場合
    """
    config = _FcitxConfig()
    if text:
        config.read_string(text)
    groups = [s for s in config.sections() if re.fullmatch(r'Groups/\d+', s)]
    if not groups:
        layouts = [layout] if layout else (layouts_provider or keyboard_layouts)()
        config['Groups/0'] = {
            'Name': 'Default',
            'Default Layout': layouts[0],
            'DefaultIM': 'hazkey',
        }
        config['GroupOrder'] = {'0': 'Default'}
        for i, name in enumerate(layouts):
            config[f'Groups/0/Items/{i}'] = {'Name': f'keyboard-{name}', 'Layout': ''}
        groups = ['Groups/0']
    for group in groups:
        if not config[group].get('Name') or not config[group].get('Default Layout'):
            raise ValueError(f'Fcitxのグループ設定が不完全です: {group}')
        items = [s for s in config.sections() if re.fullmatch(re.escape(group) + r'/Items/\d+', s)]
        if layout:
            _switch_layout(config, group, items, layout)
        names = [config[s].get('Name') for s in items]
        keyboard = 'keyboard-' + config[group]['Default Layout']
        has_keyboard = (
            keyboard in names
            if layout
            else any(name and name.startswith('keyboard-') for name in names)
        )
        missing = ([] if has_keyboard else [keyboard]) + [
            e for e in FCITX_ENGINES if e not in names
        ]
        index = max((int(s.rsplit('/', 1)[1]) for s in items), default=-1) + 1
        for offset, name in enumerate(missing):
            config[f'{group}/Items/{index + offset}'] = {'Name': name, 'Layout': ''}
    stream = io.StringIO()
    config.write(stream, space_around_delimiters=False)
    return stream.getvalue()


def configure(
    config_home: Path,
    zenzai_backend: str = 'CPU',
    *,
    disable_input_history: bool = False,
    layout: str | None = None,
    check: bool = False,
) -> None:
    """Hazkey・Fcitx 設定の検証と書き込み（両ファイルの検証後に書き込み）

    Args:
        config_home: XDG_CONFIG_HOME
        layout: Fcitx の既定配列（None なら既存設定を維持）
        check: 検証のみで書き込まないか
    """
    paths = [config_home / 'hazkey/config.json', config_home / 'fcitx5/profile']
    texts = [p.read_text() if p.exists() else None for p in paths]
    outputs = [
        hazkey_config(texts[0], zenzai_backend, disable_input_history=disable_input_history),
        fcitx_profile(texts[1], layout=layout),
    ]
    if check:
        return
    for path, output in zip(paths, outputs, strict=True):
        atomic_write(path, output)


def main() -> None:
    """コマンドライン引数に従った設定の適用"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zenzai-backend', default='CPU', help='Hazkey backend device name')
    parser.add_argument(
        '--no-input-history',
        action='store_true',
        help='Disable learning from input history in every profile',
    )
    parser.add_argument(
        '--layout', help='XKB keyboard layout for every Fcitx group, e.g. us, jp, us+dvorak'
    )
    parser.add_argument('--check', action='store_true')
    arguments = parser.parse_args()
    if not ZENZAI_BACKEND_PATTERN.fullmatch(arguments.zenzai_backend):
        parser.error('--zenzai-backend must be CPU or Vulkan followed by a device number')
    try:
        layout = xkb_layout(arguments.layout) if arguments.layout is not None else None
    except ValueError as error:
        parser.error(str(error))
    home = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    configure(
        home,
        arguments.zenzai_backend,
        disable_input_history=arguments.no_input_history,
        layout=layout,
        check=arguments.check,
    )


if __name__ == '__main__':
    main()
