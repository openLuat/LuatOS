# -*- coding: utf-8 -*-
import json, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

base = r"C:\Users\luat\AppData\Local\CodeBuddyExtension\Data\540c125d-ea10-4134-af9c-e305a8e4e71e\CodeBuddyIDE\540c125d-ea10-4134-af9c-e305a8e4e71e\history\9b84ee5b687d217705e5a3b674716ccb\6054091ff82041a4a0dd8a90b541d6ae\tool-results"

def load(name):
    with open(base + "\\" + name, encoding="utf-8") as f:
        arr = json.load(f)
    return json.loads(arr[0]["text"])

proj = load("get_project-f77e31ad-52ee-46a8-beef-a28282a1f837.txt")
d = proj["design"]
print("TOP KEYS:", list(proj.keys()))
print("DESIGN KEYS:", list(d.keys()))
lg = d.get("logic")
print("LOGIC KEYS:", list(lg.keys()) if isinstance(lg, dict) else lg)

seen = set()
for p in d["pages"]:
    print("PAGE:", p["id"], p.get("name"), "widgetCount=", len(p["widgets"]))
    for w in p["widgets"]:
        t = w["type"]
        if t not in seen:
            seen.add(t)
            print("=== SAMPLE WIDGET TYPE:", t)
            print(json.dumps(w, ensure_ascii=False, indent=1))

print("=== VARIABLES SAMPLE:", json.dumps(d.get("variables", [])[:3], ensure_ascii=False, indent=1))

nodes = lg.get("nodes", []) if isinstance(lg, dict) else []
ntypes = set()
for n in nodes:
    t = n["type"]
    if t not in ntypes:
        ntypes.add(t)
        print("=== SAMPLE NODE TYPE:", t)
        print(json.dumps(n, ensure_ascii=False, indent=1))
print("=== NODE GRAPH:")
for n in nodes:
    print(n["id"], "|", n["type"], "| next=", n.get("next"), "| otherwise=", n.get("otherwise"),
          "| trigger=", n.get("trigger"), "| event=", n.get("event"), "| var=", n.get("variable"),
          "| resultVariable=", n.get("resultVariable"), "| module=", n.get("module"), "| action=", n.get("action"))

files = []
if isinstance(lg, dict):
    files = lg.get("files", [])
files = files or d.get("files", [])
for fobj in files:
    print("=== FILE:", fobj.get("name"), "keys=", list(fobj.keys()), "actions:", [a.get("name") for a in fobj.get("actions", [])])
    print("--- content head ---")
    print(fobj.get("content", "")[:1200])
print("=== BUSINESS CODE:")
print(d.get("businessCode", ""))
