#!/usr/bin/env python3
"""Prepend (or replace) this release's <item> in appcast.xml — Sparkle's update feed.

CI-owned (called from .github/workflows/release.yml); do NOT hand-edit appcast.xml.
Reads VERSION, BUILD, ED_LEN, ED_SIG, PUBDATE from the environment. Idempotent on
BUILD, so re-running a release just refreshes its entry instead of duplicating it.

Test locally without touching the tracked file:
    VERSION=9.9.9 BUILD=99999 ED_LEN=123 ED_SIG=deadbeef PUBDATE="$(date -R)" \
        python3 scripts/update-appcast.py && git checkout appcast.xml
"""
import os
import xml.etree.ElementTree as ET

SP = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SP)

version = os.environ["VERSION"]
build = os.environ["BUILD"]
url = f"https://github.com/yonigottesman/quill/releases/download/v{version}/Quill-{version}.dmg"
path = "appcast.xml"

if os.path.exists(path):
    tree = ET.parse(path)
    channel = tree.getroot().find("channel")
else:
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Quill"
    tree = ET.ElementTree(rss)

# Drop any existing entry for this build number before re-adding (idempotent).
for item in channel.findall("item"):
    el = item.find(f"{{{SP}}}version")
    if el is not None and el.text == build:
        channel.remove(item)

item = ET.Element("item")
ET.SubElement(item, "title").text = version
ET.SubElement(item, f"{{{SP}}}version").text = build
ET.SubElement(item, f"{{{SP}}}shortVersionString").text = version
ET.SubElement(item, f"{{{SP}}}minimumSystemVersion").text = "15.0"
ET.SubElement(item, "pubDate").text = os.environ["PUBDATE"]
ET.SubElement(item, "enclosure", {
    "url": url,
    "type": "application/octet-stream",
    "length": os.environ["ED_LEN"],
    f"{{{SP}}}edSignature": os.environ["ED_SIG"],
})
channel.insert(1, item)  # newest first, just after <title>

ET.indent(tree, space="  ")
tree.write(path, encoding="utf-8", xml_declaration=True)
