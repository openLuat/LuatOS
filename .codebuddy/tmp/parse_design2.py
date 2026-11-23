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

want = {"textarea", "switch", "slider", "dropdown", "label", "checkbox"}
seen = set()
for p in d["pages"]:
    for w in p["widgets"]:
        t = w["type"]
        if t in want and t not in seen:
            seen.add(t)
            print("=== WIDGET", t)
            print(json.dumps(w, ensure_ascii=False))
        # label with binding to see multi-line usage
        if t == "label" and w.get("binding") and "label_bound_shown" not in seen:
            seen.add("label_bound_shown")
            print("=== BOUND LABEL")
            print(json.dumps(w, ensure_ascii=False))

nodes = d["logic"]["nodes"]
ntypes = set()
for n in nodes:
    t = n["type"]
    if t not in ntypes:
        ntypes.add(t)
        print("=== NODE", t)
        print(json.dumps(n, ensure_ascii=False))
# any node with resultVariable or otherwise
for n in nodes:
    if n.get("resultVariable") or n.get("otherwise"):
        print("=== NODE SPECIAL", json.dumps(n, ensure_ascii=False))

print("=== VARS3", json.dumps(d["variables"][:3], ensure_ascii=False))
print("=== FILE KEYS", list(d["files"][0].keys()))
print("=== ACTION KEYS", list(d["files"][0]["actions"][0].keys()))
print("=== PAGE KEYS", list(d["pages"][0].keys()))
