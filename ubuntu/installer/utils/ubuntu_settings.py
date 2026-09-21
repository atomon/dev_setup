#!/usr/bin/env python3
"""Helpers for the personal Ubuntu GNOME settings installer."""

from __future__ import annotations

import ast
from pathlib import Path
import re
import sys


def gvariant_string_list(value: str) -> list[str]:
    """Parse the string-array format emitted by ``gsettings get``."""
    try:
        parsed = ast.literal_eval(value.removeprefix("@as ").strip())
    except (SyntaxError, ValueError) as error:
        raise ValueError("GSettingsの配列値を読み取れません。") from error
    if not isinstance(parsed, list) or not all(isinstance(item, str) for item in parsed):
        raise ValueError("GSettingsの配列値を読み取れません。")
    return parsed


def append_gvariant_string(value: str, item: str) -> str:
    items = gvariant_string_list(value)
    if item not in items:
        items.append(item)
    return repr(items)


def upsert_managed_block(path: Path, begin: str, end: str, content: str) -> None:
    """Replace this installer's marked block while preserving surrounding text."""
    text = path.read_text() if path.exists() else ""
    pattern = re.compile(
        rf"(?:^|\n){re.escape(begin)}\n.*?\n{re.escape(end)}(?:\n|$)", re.DOTALL
    )
    block = f"{begin}\n{content.rstrip()}\n{end}\n"
    updated = pattern.sub("\n", text).rstrip("\n")
    if updated:
        updated += "\n\n"
    updated += block
    if updated != text:
        path.write_text(updated)


def merge_xkb_option(source: Path, target: Path, option: str) -> None:
    """Add an XKB option to /etc/default/keyboard without dropping others."""
    text = source.read_text() if source.exists() else ""
    match = re.search(r'^XKBOPTIONS="([^"]*)"[ \t]*$', text, re.MULTILINE)
    if match:
        options = [item for item in match.group(1).split(",") if item]
        if option not in options:
            options.append(option)
        replacement = f'XKBOPTIONS="{",".join(options)}"'
        text = text[: match.start()] + replacement + text[match.end() :]
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += f'XKBOPTIONS="{option}"\n'
    target.write_text(text)


def main(arguments: list[str]) -> None:
    command, *args = arguments
    if command == "upsert-block" and len(args) == 3:
        path, begin, end = args
        upsert_managed_block(Path(path), begin, end, sys.stdin.read())
    elif command == "append-gvariant" and len(args) == 2:
        print(append_gvariant_string(*args))
    elif command == "gvariant-lines" and len(args) == 1:
        sys.stdout.write("\n".join(gvariant_string_list(args[0])))
    elif command == "merge-xkb-option" and len(args) == 3:
        source, target, option = args
        merge_xkb_option(Path(source), Path(target), option)
    else:
        raise SystemExit("使い方が不正です。")


if __name__ == "__main__":
    main(sys.argv[1:])
