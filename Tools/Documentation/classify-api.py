#!/usr/bin/env python3
"""Classify compiler-exported public declarations using the reviewed API contract."""

import json
from pathlib import Path
import re
import shutil
import sys

scratch = Path(sys.argv[1])
output = Path(sys.argv[2])
graphs = list(scratch.rglob("ApogeeCore.symbols.json"))
if len(graphs) != 1:
    raise SystemExit("Expected one ApogeeCore symbol graph; use a single-toolchain scratch path")
for generated_graph in graphs[0].parent.glob("AppStoreConnectGenerated*.symbols.json"):
    if json.loads(generated_graph.read_text())["symbols"]:
        raise SystemExit("The generated implementation target must not export public declarations")
classifications = dict(re.findall(
    r"^\| `([^`]+)` \| (Supported|Provisional) \|",
    Path("docs/public-api.md").read_text(), re.MULTILINE
))
graph = json.loads(graphs[0].read_text())
rows = []
seen = set()
for symbol in graph["symbols"]:
    components = symbol["pathComponents"]
    owner = components[0]
    if owner not in classifications:
        raise SystemExit("Unclassified public declaration: " + ".".join(components))
    seen.add(owner)
    status = classifications[owner]
    if owner == "ReleaseAutomation" and len(components) > 1:
        if components[1].startswith("updateScreenshots("):
            status = "Provisional"
        elif "screenshotLoader:" in components[1]:
            status = "Supported; screenshotLoader parameter provisional"
    declaration = "".join(fragment["spelling"] for fragment in symbol["declarationFragments"])
    rows.append({"symbol": ".".join(components), "declaration": declaration, "status": status})
missing = classifications.keys() - seen
if missing:
    raise SystemExit("Classified types absent from public API: " + ", ".join(sorted(missing)))
symbols = output / "symbols"
symbols.mkdir(parents=True, exist_ok=True)
shutil.copy2(graphs[0], symbols / graphs[0].name)
(output / "public-api.json").write_text(json.dumps(sorted(
    rows, key=lambda row: (row["symbol"], row["declaration"])
), indent=2) + "\n")
print(f"Classified {len(rows)} public declarations across {len(seen)} types")
