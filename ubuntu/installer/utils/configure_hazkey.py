#!/usr/bin/env python3
"""Offline settings for Hazkey 0.2.1 and Fcitx 5. Call only after stopping them."""
import configparser
import io
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile


def atomic_write(path, content):
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


def default_hazkey_profile(zenzai_backend):
    # Mirrors genDefaultConfig() in upstream 0.2.1 config.swift.
    return {
        'profileName': 'Default', 'autoConvertMode': 3, 'auxTextMode': 3,
        'suggestionListMode': 3, 'numSuggestions': 3, 'useRichSuggestion': False,
        'numCandidatesPerPage': 9, 'useRichCandidates': False, 'useInputHistory': True,
        'stopStoreNewHistory': False,
        'specialConversionMode': dict.fromkeys([
            'commaSeparatedNumber', 'mailDomain', 'calendar', 'time', 'romanTypography',
            'unicodeCodepoint', 'hazkeyVersion', 'halfwidthKatakana', 'extendedEmoji'], True),
        'enabledKeymaps': [dict(name=name, isBuiltIn=True, filename=name) for name in
                          ['Fullwidth Number', 'Fullwidth Symbol', 'Japanese Symbol', 'Fullwidth Space']],
        'enabledTables': [dict(name='Romaji', isBuiltIn=True, filename='Romaji')],
        'submodeEntryPointChars': 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        'zenzaiEnable': True, 'zenzaiBackendDeviceName': zenzai_backend,
        'zenzaiInferLimit': 10, 'zenzaiContextualMode': True, 'zenzaiProfile': '',
    }


def hazkey_config(text, zenzai_backend='CPU'):
    profiles = json.loads(text) if text is not None else []
    if not isinstance(profiles, list) or any(not isinstance(p, dict) for p in profiles):
        raise ValueError('Hazkey config.json must contain an array of profiles')
    if not profiles:
        profiles = [default_hazkey_profile(zenzai_backend)]
    for profile in profiles:
        # Protobuf JSON accepts both spellings; avoid duplicate representations.
        for key in ('zenzai_enable', 'zenzai_backend_device_name', 'use_default_zenzai_settings'):
            profile.pop(key, None)
        profile.update(zenzaiEnable=True, zenzaiBackendDeviceName=zenzai_backend,
                       useDefaultZenzaiSettings=False)
        if 'zenzaiInferLimit' not in profile and 'zenzai_infer_limit' not in profile:
            profile['zenzaiInferLimit'] = 10
    return json.dumps(profiles, ensure_ascii=False, indent=2) + '\n'


def keyboard_layouts():
    from gi.repository import Gio
    sources = Gio.Settings.new('org.gnome.desktop.input-sources').get_value('sources').unpack()
    layouts = [name.replace('+', '-', 1) for kind, name in sources if kind == 'xkb']
    if not layouts:
        # GNOME may only contain an IBus engine; retain the system keyboard layout.
        text = Path('/etc/default/keyboard').read_text()
        layout = re.search(r'^XKBLAYOUT=[\"\']?([a-z0-9_,]+)', text, re.M)
        variant = re.search(r'^XKBVARIANT=[\"\']?([a-z0-9_,]*)', text, re.M)
        if layout:
            variants = variant[1].split(',') if variant else []
            layouts = [name + ('-' + variants[i] if i < len(variants) and variants[i] else '')
                       for i, name in enumerate(layout[1].split(','))]
    if not layouts:
        raise ValueError('既存のキーボード配列を取得できません。GNOMEで配列を設定してください。')
    return list(dict.fromkeys(layouts))


def fcitx_profile(text, layouts_provider=None):
    config = configparser.ConfigParser(interpolation=None, delimiters=('=',), strict=True)
    config.optionxform = str
    if text:
        config.read_string(text)
    groups = [s for s in config.sections() if re.fullmatch(r'Groups/\d+', s)]
    if not groups:
        layouts = (layouts_provider or keyboard_layouts)()
        config['Groups/0'] = {'Name': 'Default', 'Default Layout': layouts[0], 'DefaultIM': 'hazkey'}
        config['GroupOrder'] = {'0': 'Default'}
        for i, layout in enumerate(layouts):
            config[f'Groups/0/Items/{i}'] = {'Name': f'keyboard-{layout}', 'Layout': ''}
        groups = ['Groups/0']
    for group in groups:
        if not config[group].get('Name') or not config[group].get('Default Layout'):
            raise ValueError(f'Fcitxのグループ設定が不完全です: {group}')
        items = [s for s in config.sections() if re.fullmatch(re.escape(group) + r'/Items/\d+', s)]
        names = [config[s].get('Name') for s in items]
        index = max((int(s.rsplit('/', 1)[1]) for s in items), default=-1) + 1
        if not any(name and name.startswith('keyboard-') for name in names):
            config[f'{group}/Items/{index}'] = {'Name': 'keyboard-' + config[group]['Default Layout'], 'Layout': ''}
            index += 1
        for engine in ('hazkey', 'mozc'):
            if engine not in names:
                config[f'{group}/Items/{index}'] = {'Name': engine, 'Layout': ''}
                index += 1
    stream = io.StringIO()
    config.write(stream, space_around_delimiters=False)
    return stream.getvalue()


def prepare(config_home, zenzai_backend='CPU'):
    paths = [config_home / 'hazkey/config.json', config_home / 'fcitx5/profile']
    # Validate both files before changing either one.
    texts = [p.read_text() if p.exists() else None for p in paths]
    outputs = [hazkey_config(texts[0], zenzai_backend), fcitx_profile(texts[1])]
    return paths, outputs


def configure(config_home, zenzai_backend='CPU'):
    paths, outputs = prepare(config_home, zenzai_backend)
    for path, output in zip(paths, outputs):
        atomic_write(path, output)


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zenzai-backend', default='CPU',
                        help='Hazkey backend device name')
    parser.add_argument('--check', action='store_true')
    arguments = parser.parse_args()
    if not re.fullmatch(r'(?:CPU|Vulkan[0-9]+)', arguments.zenzai_backend):
        parser.error('--zenzai-backend must be CPU or Vulkan followed by a device number')
    home = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    paths, outputs = prepare(home, arguments.zenzai_backend)
    if arguments.check:
        raise SystemExit(0)
    for path, output in zip(paths, outputs):
        atomic_write(path, output)
