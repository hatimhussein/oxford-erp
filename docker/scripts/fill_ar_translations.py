#!/usr/bin/env python3
"""Fill empty Arabic translations in Frappe/ERPNext ar.po files."""
from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

from babel.messages.pofile import read_po, write_po
from deep_translator import GoogleTranslator

REPO_ROOT = Path(__file__).resolve().parents[2]
PO_PATHS = [
    REPO_ROOT / "src/frappe/frappe/locale/ar.po",
    REPO_ROOT / "src/erpnext/erpnext/locale/ar.po",
]
CACHE_PATH = Path("/tmp/ar_translation_cache.json")

MANUAL_OVERRIDES: dict[str, str] = {
    "Document Naming": "تسمية المستندات",
    "Advanced Features": "ميزات متقدمة",
    "Enable tracking sales commissions": "تفعيل تتبع عمولات المبيعات",
    "Enable Urchin Tracking Module parameters in Quotation, Sales Order, Sales Invoice, POS Invoice, Lead,  and Delivery Note.": (
        "تفعيل معاملات وحدة UTM (Urchin Tracking Module) في عرض السعر، أمر البيع، فاتورة المبيعات، "
        "فاتورة نقطة البيع (POS)، العميل المحتمل، وإشعار التسليم."
    ),
    "Last Edited By You": "آخر تعديل بواسطتك",
    "Last Edited By {0}": "آخر تعديل بواسطة {0}",
}

KEEP_ENGLISH = [
    "ERPNext", "Frappe", "POS", "UTM", "API", "URL", "HTML", "PDF", "CSV", "JSON", "XML", "SQL",
    "OAuth", "SSO", "SMS", "SKU", "BOM", "GST", "VAT", "FIFO", "LIFO", "ERP", "CRM", "HRMS",
    "Urchin Tracking Module", "Google", "Microsoft", "AWS", "S3", "UUID", "ISO", "IMAP", "SMTP",
    "DNS", "SSL", "TLS", "HTTP", "HTTPS", "Webhook", "WhatsApp", "LinkedIn", "YouTube",
]

PH_RE = re.compile(r"(\{\{[^}]+\}\}|\{[0-9]+\}|%\([^)]+\)[sd]|%[sd])")
TAG_RE = re.compile(r"(<[^>]+>)")


def msgid_key(message) -> str | None:
    mid = message.id
    if not mid:
        return None
    if isinstance(mid, (list, tuple)):
        return mid[0] if mid else None
    return mid


def msgstr_empty(message) -> bool:
    s = message.string
    if s is None:
        return True
    if isinstance(s, (list, tuple)):
        return not any(part.strip() for part in s if part)
    return not str(s).strip()


def build_glossary(paths: list[Path]) -> dict[str, str]:
    glossary: dict[str, str] = {}
    for po_path in paths:
        with open(po_path, "rb") as f:
            catalog = read_po(f)
        for message in catalog:
            key = msgid_key(message)
            if not key or msgstr_empty(message):
                continue
            val = message.string
            if isinstance(val, (list, tuple)):
                val = val[0]
            glossary[key] = str(val)
    return glossary


def protect_text(text: str) -> tuple[str, list[str]]:
    tokens: list[str] = []

    def stash(match: re.Match) -> str:
        tokens.append(match.group(0))
        return f"__TOK{len(tokens) - 1}__"

    protected = TAG_RE.sub(stash, text)
    protected = PH_RE.sub(stash, protected)
    for term in sorted(set(KEEP_ENGLISH), key=len, reverse=True):
        protected = re.sub(re.escape(term), stash, protected, flags=re.IGNORECASE)
    return protected, tokens


def restore_text(text: str, tokens: list[str]) -> str:
    for i, tok in enumerate(tokens):
        text = text.replace(f"__TOK{i}__", tok)
    return text


def post_process_ar(text: str, source: str) -> str:
    if "Sales Order" in source:
        text = re.sub(r"طلب(?:\s+)?المبيعات", "أمر البيع", text)
        text = re.sub(r"أمر(?:\s+)?المبيعات(?!\s+فاتورة)", "أمر البيع", text)
    if "Quotation" in source:
        text = re.sub(r"عرض(?:\s+)?الأسعار", "عرض السعر", text)
    if "Delivery Note" in source:
        text = re.sub(r"مذكرة(?:\s+)?التسليم", "إشعار التسليم", text)
    return text


class Translator:
    def __init__(self, cache: dict[str, str]):
        self.cache = cache
        self.gt = GoogleTranslator(source="en", target="ar")

    def translate_one(self, text: str) -> str:
        if text in self.cache:
            return self.cache[text]
        protected, tokens = protect_text(text)
        last_err = None
        for attempt in range(4):
            try:
                out = self.gt.translate(protected)
                if not out:
                    raise RuntimeError("empty translation")
                out = restore_text(out, tokens)
                out = post_process_ar(out, text)
                self.cache[text] = out
                return out
            except Exception as exc:
                last_err = exc
                time.sleep(1.5 * (attempt + 1))
        raise RuntimeError(f"translation failed for {text[:80]!r}: {last_err}")

    def translate_batch(self, texts: list[str]) -> list[str]:
        results: list[str | None] = [None] * len(texts)
        pending: list[tuple[int, str]] = []
        for i, text in enumerate(texts):
            if text in self.cache:
                results[i] = self.cache[text]
            else:
                pending.append((i, text))

        batch_size = 40
        for batch_start in range(0, len(pending), batch_size):
            chunk = pending[batch_start : batch_start + batch_size]
            protected_list: list[str] = []
            token_lists: list[list[str]] = []
            for _, text in chunk:
                p, t = protect_text(text)
                protected_list.append(p)
                token_lists.append(t)

            translated: list[str] | None = None
            for attempt in range(4):
                try:
                    translated = self.gt.translate_batch(protected_list)
                    break
                except Exception:
                    time.sleep(2 * (attempt + 1))

            if translated is None:
                for idx, text in chunk:
                    results[idx] = self.translate_one(text)
                continue

            for j, (idx, orig) in enumerate(chunk):
                tr = restore_text(translated[j] or "", token_lists[j])
                tr = post_process_ar(tr, orig)
                self.cache[orig] = tr
                results[idx] = tr
            time.sleep(0.35)

        return [r or "" for r in results]


def fill_po(po_path: Path, glossary: dict[str, str], translator: Translator) -> int:
    with open(po_path, "rb") as f:
        catalog = read_po(f)

    to_translate: list[tuple[object, str]] = []
    filled = 0

    for message in catalog:
        key = msgid_key(message)
        if not key or not msgstr_empty(message):
            continue
        if key in MANUAL_OVERRIDES:
            message.string = MANUAL_OVERRIDES[key]
            filled += 1
            continue
        if key in glossary and glossary[key].strip():
            message.string = glossary[key]
            filled += 1
            continue
        to_translate.append((message, key))

    keys = [k for _, k in to_translate]
    if keys:
        print(f"  Translating {len(keys)} strings via API...")
        translated = translator.translate_batch(keys)
        for (message, _), tr in zip(to_translate, translated):
            message.string = tr
            filled += 1

    with open(po_path, "wb") as f:
        write_po(f, catalog, width=0)
    return filled


def verify_strings(paths: list[Path]) -> None:
    checks = list(MANUAL_OVERRIDES.keys()) + ["Subscription Settings"]
    expected = dict(MANUAL_OVERRIDES)
    expected["Subscription Settings"] = "إعدادات الاشتراك"
    for po_path in paths:
        with open(po_path, "rb") as f:
            catalog = read_po(f)
        by_id: dict[str, str] = {}
        for message in catalog:
            key = msgid_key(message)
            if not key:
                continue
            val = message.string
            if isinstance(val, (list, tuple)):
                val = val[0] if val else ""
            by_id[key] = val or ""
        print(f"\nVerification ({po_path.name}):")
        for key in checks:
            if key not in by_id:
                continue
            ok = by_id[key] == expected[key]
            status = "OK" if ok else "MISMATCH"
            print(f"  [{status}] {key!r}")


def main() -> int:
    paths = [p for p in PO_PATHS if p.exists()]
    if not paths:
        print("No ar.po files found", file=sys.stderr)
        return 1

    cache: dict[str, str] = {}
    if CACHE_PATH.exists():
        cache = json.loads(CACHE_PATH.read_text(encoding="utf-8"))

    glossary = build_glossary(paths)
    translator = Translator(cache)

    totals: dict[str, int] = {}
    for po_path in paths:
        print(f"Processing {po_path}...")
        count = fill_po(po_path, glossary, translator)
        totals[str(po_path)] = count
        print(f"  Filled {count} empty translations")

    try:
        CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError as exc:
        print(f"  Warning: could not write cache ({exc})")

    print("\nSummary:")
    for path, count in totals.items():
        print(f"  {path}: {count} translated")

    verify_strings(paths)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

