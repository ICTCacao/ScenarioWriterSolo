#!/usr/bin/env python3
# Mac 版と同じ Word テンプレート（Packages/ScenarioWriterCore/Sources/ScenarioWriterCore/Resources/docx）を
# 1 つの JSON にまとめる（src/docx-templates.json）。テンプレートを直したら実行し直す。
import json, os, sys
root = os.path.join(os.path.dirname(__file__), "..", "..", "Packages", "ScenarioWriterCore", "Sources", "ScenarioWriterCore", "Resources", "docx")
out = {}
for tpl in sorted(os.listdir(root)):
    d = os.path.join(root, tpl)
    if not os.path.isdir(d): continue
    entry = {"template": {}, "snippets": {}}
    tdir = os.path.join(d, "template")
    for dp, _, files in os.walk(tdir):
        for f in files:
            if f.startswith("."): continue
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, tdir).replace(os.sep, "/")
            entry["template"][rel] = open(p, encoding="utf-8").read()
    for f in sorted(os.listdir(os.path.join(d, "snippets"))):
        if f.endswith(".xml"):
            entry["snippets"][f[:-4]] = open(os.path.join(d, "snippets", f), encoding="utf-8").read()
    out[tpl] = entry
dst = os.path.join(os.path.dirname(__file__), "..", "src", "docx-templates.json")
json.dump(out, open(dst, "w", encoding="utf-8"), ensure_ascii=False)
print("wrote", dst, {k: (len(v["template"]), len(v["snippets"])) for k, v in out.items()})
