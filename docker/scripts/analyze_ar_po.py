#!/usr/bin/env python3
"""Analyze untranslated entries in ar.po files."""
from pathlib import Path
from babel.messages.pofile import read_po

APPS = [
    Path("/workspace/src/frappe/frappe/locale/ar.po"),
    Path("/workspace/src/erpnext/erpnext/locale/ar.po"),
]

for po_path in APPS:
    if not po_path.exists():
        po_path = Path(str(po_path).replace("/workspace/", "d:/FrappeDev/src/").replace("/", "\\"))
    if not po_path.exists():
        # try relative from repo root
        po_path = Path(__file__).resolve().parents[2] / po_path.name.replace("ar.po", "")
        candidates = list(Path(__file__).resolve().parents[2].glob(f"**/{po_path.name}"))
        if candidates:
            po_path = candidates[0]
        else:
            print(f"SKIP {po_path}")
            continue

    with open(po_path, "rb") as f:
        catalog = read_po(f)

    empty = [m.id for m in catalog if m.id and not m.string]
    print(f"{po_path}: {len(empty)} untranslated / {len([m for m in catalog if m.id])} total")
    for s in empty[:20]:
        print(f"  - {s[:80]}{'...' if len(s) > 80 else ''}")
