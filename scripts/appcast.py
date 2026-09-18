#!/usr/bin/env python3
"""Maintains appcast.xml, the Sparkle feed. One command: `add`, which
prepends a release item. Kept separate from release.sh so the XML handling
is readable and can be dry-run on its own."""
import argparse
import html
import sys
from datetime import datetime, timezone
from pathlib import Path

CHANNEL_HEAD = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Ascend</title>
    <link>https://github.com/Duarte0903/Ascend</link>
    <description>Ascend releases</description>
"""
CHANNEL_TAIL = """  </channel>
</rss>
"""
ITEM_MARK = "    <item>"


def render_item(a) -> str:
    pub = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    lines = [
        "    <item>",
        f"      <title>{html.escape(a.version)}</title>",
        f"      <pubDate>{pub}</pubDate>",
        f"      <sparkle:version>{a.build}</sparkle:version>",
        f"      <sparkle:shortVersionString>{html.escape(a.version)}</sparkle:shortVersionString>",
        "      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>",
    ]
    if a.notes:
        lines.append(f"      <description><![CDATA[{a.notes}]]></description>")
    lines += [
        f'      <enclosure url="{html.escape(a.url, quote=True)}"',
        f'                 length="{a.length}"',
        '                 type="application/octet-stream"',
        f'                 sparkle:edSignature="{html.escape(a.signature, quote=True)}"/>',
        "    </item>",
    ]
    return "\n".join(lines) + "\n"


def add(a) -> int:
    path = Path(a.file)
    text = path.read_text() if path.exists() else CHANNEL_HEAD + CHANNEL_TAIL
    if f"<sparkle:version>{a.build}</sparkle:version>" in text:
        print(f"appcast.py: build {a.build} is already in {path}", file=sys.stderr)
        return 1
    # New item goes first: Sparkle picks the highest version, but humans read
    # the file top-down.
    if ITEM_MARK in text:
        head, rest = text.split(ITEM_MARK, 1)
        text = head + render_item(a) + ITEM_MARK + rest
    else:
        head, tail = text.split(CHANNEL_TAIL, 1)
        text = head + render_item(a) + CHANNEL_TAIL + tail
    path.write_text(text)
    print(f"appcast.py: added {a.version} (build {a.build}) to {path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("add", help="prepend a release item")
    p.add_argument("--file", default="appcast.xml")
    p.add_argument("--version", required=True, help="marketing version, e.g. 1.1")
    p.add_argument("--build", required=True, type=int, help="CFBundleVersion")
    p.add_argument("--url", required=True, help="enclosure download URL")
    p.add_argument("--length", required=True, type=int, help="zip size in bytes")
    p.add_argument("--signature", required=True, help="sparkle:edSignature")
    p.add_argument("--notes", default="", help="release notes shown by Sparkle (HTML allowed)")
    p.set_defaults(run=add)
    a = parser.parse_args()
    return a.run(a)


if __name__ == "__main__":
    sys.exit(main())
