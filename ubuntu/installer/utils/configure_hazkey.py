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


def hazkey_config(text, zenzai_backend='CPU', disable_input_history=False):
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
        if disable_input_history:
            # Hazkey maps useInputHistory=false to LearningType.nothing: the learning
            # memory is neither read nor written. Existing memory files are kept.
            profile.pop('use_input_history', None)
            profile['useInputHistory'] = False
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


def xkb_layout(name, rules=Path('/usr/share/X11/xkb/rules/evdev.lst')):
    """Validate an XKB layout and return Fcitx's form: "us", "us-dvorak" (GNOME: "us+dvorak")."""
    match = re.fullmatch(r'([a-z0-9_]+)(?:[+-]([A-Za-z0-9_-]+))?', name)
    if not match:
        raise ValueError(f'キーボード配列名が不正です: {name!r}（例: us, jp, us+dvorak）')
    if rules.exists():
        layouts, variants, section = set(), set(), None
        for line in rules.read_text().splitlines():
            if line.startswith('!'):
                section = line[1:].strip()
            elif line.split() and section == 'layout':
                layouts.add(line.split()[0])
            elif line.split() and section == 'variant':
                # "  dvorak          us: English (Dvorak)"
                variant, parent = line.split()[:2]
                variants.add((parent.rstrip(':'), variant))
        if match[1] not in layouts or (match[2] and (match[1], match[2]) not in variants):
            raise ValueError(f'XKBに存在しないキーボード配列です: {name}（一覧: {rules}）')
    return match[1] + (f'-{match[2]}' if match[2] else '')


def fcitx_profile(text, layouts_provider=None, layout=None):
    config = configparser.ConfigParser(interpolation=None, delimiters=('=',), strict=True)
    config.optionxform = str
    if text:
        config.read_string(text)
    groups = [s for s in config.sections() if re.fullmatch(r'Groups/\d+', s)]
    if not groups:
        layouts = [layout] if layout else (layouts_provider or keyboard_layouts)()
        config['Groups/0'] = {'Name': 'Default', 'Default Layout': layouts[0], 'DefaultIM': 'hazkey'}
        config['GroupOrder'] = {'0': 'Default'}
        for i, name in enumerate(layouts):
            config[f'Groups/0/Items/{i}'] = {'Name': f'keyboard-{name}', 'Layout': ''}
        groups = ['Groups/0']
    for group in groups:
        if not config[group].get('Name') or not config[group].get('Default Layout'):
            raise ValueError(f'Fcitxのグループ設定が不完全です: {group}')
        items = [s for s in config.sections() if re.fullmatch(re.escape(group) + r'/Items/\d+', s)]
        names = [config[s].get('Name') for s in items]
        if layout and config[group]['Default Layout'] != layout:
            # Switch the group's layout: the old default keyboard becomes the new one,
            # unless the new one is already listed. Other keyboard entries are kept.
            old = 'keyboard-' + config[group]['Default Layout']
            config[group]['Default Layout'] = layout
            if f'keyboard-{layout}' not in names:
                for section in items:
                    if config[section].get('Name') == old:
                        config[section]['Name'] = f'keyboard-{layout}'
                if config[group].get('DefaultIM') == old:
                    config[group]['DefaultIM'] = f'keyboard-{layout}'
            names = [config[s].get('Name') for s in items]
        index = max((int(s.rsplit('/', 1)[1]) for s in items), default=-1) + 1
        has_keyboard = any(name and name.startswith('keyboard-') for name in names)
        if not has_keyboard or (layout and f'keyboard-{layout}' not in names):
            config[f'{group}/Items/{index}'] = {'Name': 'keyboard-' + config[group]['Default Layout'], 'Layout': ''}
            index += 1
        for engine in ('hazkey', 'mozc'):
            if engine not in names:
                config[f'{group}/Items/{index}'] = {'Name': engine, 'Layout': ''}
                index += 1
    stream = io.StringIO()
    config.write(stream, space_around_delimiters=False)
    return stream.getvalue()


def prepare(config_home, zenzai_backend='CPU', disable_input_history=False, layout=None):
    paths = [config_home / 'hazkey/config.json', config_home / 'fcitx5/profile']
    # Validate both files before changing either one.
    texts = [p.read_text() if p.exists() else None for p in paths]
    outputs = [hazkey_config(texts[0], zenzai_backend, disable_input_history),
               fcitx_profile(texts[1], layout=layout)]
    return paths, outputs


def configure(config_home, zenzai_backend='CPU', disable_input_history=False, layout=None):
    paths, outputs = prepare(config_home, zenzai_backend, disable_input_history, layout)
    for path, output in zip(paths, outputs):
        atomic_write(path, output)


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zenzai-backend', default='CPU',
                        help='Hazkey backend device name')
    parser.add_argument('--no-input-history', action='store_true',
                        help='Disable learning from input history in every profile')
    parser.add_argument('--layout',
                        help='XKB keyboard layout for every Fcitx group, e.g. us, jp, us+dvorak')
    parser.add_argument('--check', action='store_true')
    arguments = parser.parse_args()
    if not re.fullmatch(r'(?:CPU|Vulkan[0-9]+)', arguments.zenzai_backend):
        parser.error('--zenzai-backend must be CPU or Vulkan followed by a device number')
    try:
        layout = xkb_layout(arguments.layout) if arguments.layout is not None else None
    except ValueError as error:
        parser.error(str(error))
    home = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    paths, outputs = prepare(home, arguments.zenzai_backend, arguments.no_input_history, layout)
    if arguments.check:
        raise SystemExit(0)
    for path, output in zip(paths, outputs):
        atomic_write(path, output)
