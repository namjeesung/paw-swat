#!/usr/bin/env python3
"""Copy the authoritative Web head into Godot's export preset string."""
from pathlib import Path
import json
import re

project = Path(__file__).resolve().parent.parent
head = (project / "web/head_include.html").read_text(encoding="utf-8")
adapter = (project / "web/toy_bridge.js").read_text(encoding="utf-8")
marker = "<!-- PAW_TOY_ADAPTER -->"
if marker in head:
    head = head.split(marker)[0].rstrip() + "\n"
head += marker + "\n<script>\n" + adapter + "\n</script>\n"
(project / "web/head_include.html").write_text(head, encoding="utf-8")
preset = project / "export_presets.cfg"
text = preset.read_text(encoding="utf-8")
text, count = re.subn(
    r'html/head_include="(?:[^"\\]|\\.)*"',
    lambda _: "html/head_include=" + json.dumps(head, ensure_ascii=False),
    text,
    flags=re.S,
)
if count != 1:
    raise SystemExit(f"Expected one html/head_include entry, found {count}; unchanged")
preset.write_text(text, encoding="utf-8")
print("Web head synchronized to export_presets.cfg")
