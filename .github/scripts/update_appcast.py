#!/usr/bin/env python3
"""Prepend a new <item> to the Sparkle appcast for a freshly published release.

The Sparkle appcast lives at site/public/appcast.xml and is served from
GitHub Pages. Each release adds one <item> at the top of <channel>; older
items are preserved so users on older versions still see a valid feed.

The signature fragment comes from `sign_update`, which emits something like:
    sparkle:edSignature="abc..." length="12345678"
We append that verbatim to the <enclosure> element so the produced XML
matches Sparkle's expectations exactly.

Sparkle renders <description> as HTML in a web view, so --notes-file takes
release notes that are already HTML. release.yml produces them by running
git-cliff a second time against .github/appcast-body.tera; the markdown run
still feeds the GitHub Release body.
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

def build_item(
    version: str,
    tag: str,
    download_url: str,
    signature_fragment: str,
    notes_html: str,
    pub_date: str,
) -> str:
    notes = notes_html.strip() or f"<p>Total Recall {escape(version)}</p>"
    # The template escapes `>`, so this can't come from a commit subject — but a
    # stray `]]>` would end the CDATA section early, so split it across two.
    notes = notes.replace("]]>", "]]]]><![CDATA[>")
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
    parser.add_argument(
        "--notes-file",
        type=Path,
        help="HTML release notes from git-cliff --body .github/appcast-body.tera",
    )
    args = parser.parse_args()

    pub_date = datetime.now(tz=timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    new_item = build_item(
        version=args.version,
        tag=args.tag,
        download_url=args.download_url,
        signature_fragment=args.signature_fragment,
        notes_html=args.notes_file.read_text() if args.notes_file else "",
        pub_date=pub_date,
    )
    items = new_item + existing_items(args.appcast)

    args.appcast.parent.mkdir(parents=True, exist_ok=True)
    args.appcast.write_text(APPCAST_TEMPLATE.format(items=items))
    print(f"Wrote {args.appcast} with {items.count('<item>')} item(s)")


if __name__ == "__main__":
    main()
