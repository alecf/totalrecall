#!/usr/bin/env python3
"""Prepend a new <item> to the Sparkle appcast for a freshly published release.

The Sparkle appcast lives at site/public/appcast.xml and is served from
GitHub Pages. Each release adds one <item> at the top of <channel>; older
items are preserved so users on older versions still see a valid feed.

The signature fragment comes from `sign_update`, which emits something like:
    sparkle:edSignature="abc..." length="12345678"
We append that verbatim to the <enclosure> element so the produced XML
matches Sparkle's expectations exactly.

Sparkle renders <description> as HTML in a web view, so the git-cliff
changelog is converted from markdown to HTML on the way in — raw markdown
renders as one run-together paragraph.
"""

from __future__ import annotations

import argparse
import re
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape


APPCAST_TEMPLATE = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Total Recall</title>
    <link>https://alecf.github.io/totalrecall/appcast.xml</link>
    <description>Most recent updates to Total Recall</description>
    <language>en</language>
{items}  </channel>
</rss>
"""

# The release-notes pane is small, so headings are toned down to body size and
# vertical rhythm is tightened. Colors are left alone: Sparkle's web view
# follows the system appearance, and hardcoding them would break dark mode.
RELEASE_NOTES_STYLE = """<style>
        h2, h3, h4, h5, h6 { font-size: 1em; margin: 1em 0 0.3em; }
        p { margin: 0.4em 0; }
        ul { margin: 0.2em 0; padding-left: 1.4em; }
        li { margin: 0.15em 0; }
        style + * { margin-top: 0; }
      </style>"""

_HEADING = re.compile(r"(#{1,6})\s+(.*)")
_BULLET = re.compile(r"[-*+]\s+(.*)")
_CODE = re.compile(r"`([^`]+)`")
_LINK = re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")
_BOLD = re.compile(r"\*\*([^*]+)\*\*")
_ITALIC = re.compile(r"(?<!\*)\*([^*]+)\*(?!\*)")


def _inline(text: str) -> str:
    """Escape a run of markdown text and expand its inline spans."""
    out = escape(text)
    out = _CODE.sub(lambda m: f"<code>{m.group(1)}</code>", out)
    out = _LINK.sub(
        lambda m: f'<a href="{m.group(2).replace(chr(34), "&quot;")}">{m.group(1)}</a>', out
    )
    out = _BOLD.sub(lambda m: f"<strong>{m.group(1)}</strong>", out)
    out = _ITALIC.sub(lambda m: f"<em>{m.group(1)}</em>", out)
    return out


def markdown_to_html(markdown: str) -> str:
    """Render the changelog subset git-cliff emits: headings, bullets, paragraphs."""
    html: list[str] = []
    paragraph: list[str] = []
    in_list = False

    def flush_paragraph() -> None:
        if paragraph:
            html.append(f"<p>{_inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            html.append("</ul>")
            in_list = False

    for raw in markdown.strip().splitlines():
        line = raw.strip()
        if not line:
            flush_paragraph()
            close_list()
            continue

        heading = _HEADING.fullmatch(line)
        if heading:
            flush_paragraph()
            close_list()
            # git-cliff's top level is `##`; demote one step so the largest
            # heading in the pane is an h3 rather than an oversized h2.
            level = min(len(heading.group(1)) + 1, 6)
            html.append(f"<h{level}>{_inline(heading.group(2))}</h{level}>")
            continue

        bullet = _BULLET.fullmatch(line)
        if bullet:
            flush_paragraph()
            if not in_list:
                html.append("<ul>")
                in_list = True
            html.append(f"<li>{_inline(bullet.group(1))}</li>")
            continue

        paragraph.append(line)

    flush_paragraph()
    close_list()
    return "\n".join(html)


def build_item(
    version: str,
    tag: str,
    download_url: str,
    signature_fragment: str,
    changelog: str,
    pub_date: str,
) -> str:
    notes = markdown_to_html(changelog) or f"<p>Total Recall {escape(version)}</p>"
    notes = "\n".join(f"      {line}" for line in notes.splitlines())
    return f"""    <item>
      <title>Version {escape(version)}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{escape(version)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
      {RELEASE_NOTES_STYLE}
{notes}
      ]]></description>
      <enclosure url="{escape(download_url, {chr(34): "&quot;"})}" type="application/octet-stream" {signature_fragment.strip()} />
    </item>
"""


def existing_items(appcast_path: Path) -> str:
    """Extract every existing <item>...</item> block, preserving order."""
    if not appcast_path.exists():
        return ""
    text = appcast_path.read_text()
    matches = re.findall(r"    <item>.*?</item>\n", text, re.DOTALL)
    return "".join(matches)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--appcast", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--signature-fragment", required=True)
    parser.add_argument("--changelog", default="")
    args = parser.parse_args()

    pub_date = datetime.now(tz=timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    new_item = build_item(
        version=args.version,
        tag=args.tag,
        download_url=args.download_url,
        signature_fragment=args.signature_fragment,
        changelog=args.changelog,
        pub_date=pub_date,
    )
    items = new_item + existing_items(args.appcast)

    args.appcast.parent.mkdir(parents=True, exist_ok=True)
    args.appcast.write_text(APPCAST_TEMPLATE.format(items=items))
    print(f"Wrote {args.appcast} with {items.count('<item>')} item(s)")


if __name__ == "__main__":
    main()
