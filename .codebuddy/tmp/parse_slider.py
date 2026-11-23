# -*- coding: utf-8 -*-
import json, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

base = r"C:\Users\luat\AppData\Local\CodeBuddyExtension\Data\540c125d-ea10-4134-af9c-e305a8e4e71e\CodeBuddyIDE\540c125d-ea10-4134-af9c-e305a8e4e71e\history\9b84ee5b687d217705e5a3b674716ccb\6054091ff82041a4a0dd8a90b541d6ae\tool-results"

def load(name):
    with open(base + "\\" + name, encoding="utf-8") as f:
        arr = json.load(f)
    return json.loads(arr[0]["text"])

cat = load("get_catalog-4e33f93a-f509-4d1d-a445-fd1051e718d4.txt")
for it in cat["items"]:
    if it["id"] in ("slider", "switch", "bar", "checkbox"):
        print("===", it["id"])
        for p in it.get("props", []):
            print(" ", p.get("key"), "| type=", p.get("type"), "| default=", p.get("default"), "| min=", p.get("min"), "| max=", p.get("max"))
