#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import sqlite3
from pathlib import Path


IMPORT_FILES = [
    "cn_dicts/8105.dict.yaml",
    "cn_dicts/41448.dict.yaml",
    "cn_dicts/base.dict.yaml",
    "cn_dicts/ext.dict.yaml",
    "cn_dicts/tencent.dict.yaml",
    "cn_dicts/others.dict.yaml",
    "rime_ice.dict.yaml",
]

PINYIN_RE = re.compile(r"^[A-Za-z0-9 ':-]+$")
HAN_RE = re.compile(r"[\u3400-\u9fff]")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def normalize_code(code):
    return re.sub(r"[^0-9a-z]", "", code.lower())


def abbreviation(code):
    parts = [p for p in re.split(r"[^0-9A-Za-z]+", code.lower()) if p]
    if len(parts) > 1:
        return "".join(part[0] for part in parts)
    return normalize_code(code)[:1]


def parse_weight(value, default_weight):
    if not value:
        return default_weight
    try:
        return float(value)
    except ValueError:
        return default_weight


def split_entry(line):
    line = line.split("#", 1)[0].strip()
    if not line:
        return None
    if "\t" in line:
        parts = [p.strip() for p in line.split("\t") if p.strip()]
    else:
        parts = line.split()
    if not parts:
        return None
    text = parts[0]
    code = ""
    weight = ""
    if len(parts) >= 2:
        if PINYIN_RE.match(parts[1]):
            code = parts[1]
        else:
            weight = parts[1]
    if len(parts) >= 3:
        weight = parts[2]
    return text, code, weight


def iter_entries(path):
    in_entries = False
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if line == "...":
                in_entries = True
                continue
            if not in_entries:
                continue
            entry = split_entry(raw_line)
            if entry:
                yield entry


def build_char_readings(rime_root):
    readings = {}
    for rel in ("cn_dicts/8105.dict.yaml", "cn_dicts/41448.dict.yaml"):
        path = rime_root / rel
        if not path.exists():
            continue
        for text, code, weight in iter_entries(path):
            if len(text) != 1 or not code:
                continue
            freq = parse_weight(weight, 1.0)
            normalized = normalize_code(code)
            if not normalized:
                continue
            current = readings.get(text)
            if not current or freq > current[1]:
                readings[text] = (code, freq)
    return readings


def infer_code(text, char_readings):
    codes = []
    for ch in text:
        if ch in char_readings:
            codes.append(char_readings[ch][0])
        elif ch.isascii() and ch.isalnum():
            codes.append(ch)
        else:
            return ""
    return " ".join(codes)


def load_entries(rime_root):
    char_readings = build_char_readings(rime_root)
    entries = {}
    source_counts = {}
    inferred_count = 0
    skipped_count = 0

    for rel in IMPORT_FILES:
        path = rime_root / rel
        if not path.exists():
            raise FileNotFoundError(f"Missing rime-ice dictionary: {path}")
        source_counts[rel] = 0
        default_weight = 1.0
        for text, code, weight in iter_entries(path):
            if not text or not HAN_RE.search(text):
                continue
            if not code:
                code = infer_code(text, char_readings)
                if code:
                    inferred_count += 1
            if not code:
                skipped_count += 1
                continue
            py = normalize_code(code)
            if not py:
                skipped_count += 1
                continue
            freq = parse_weight(weight, default_weight)
            abbr = abbreviation(code)
            key = (text, py)
            prev = entries.get(key)
            if not prev or freq > prev["freq"]:
                entries[key] = {"hz": text, "py": py, "abbr": abbr, "freq": freq, "source": rel}
            source_counts[rel] += 1

    return list(entries.values()), {
        "source_counts": source_counts,
        "inferred_count": inferred_count,
        "skipped_count": skipped_count,
        "char_reading_count": len(char_readings),
    }


def prune_entries(entries, max_low_freq, min_low_freq_length):
    kept = []
    pruned = 0
    for entry in entries:
        if len(entry["hz"]) > min_low_freq_length and entry["freq"] <= max_low_freq:
            pruned += 1
        else:
            kept.append(entry)
    return kept, pruned


def write_sqlite(entries, output_path):
    if output_path.exists():
        output_path.unlink()
    conn = sqlite3.connect(output_path)
    try:
        conn.execute("PRAGMA journal_mode=OFF")
        conn.execute("PRAGMA synchronous=OFF")
        conn.execute(
            """
            CREATE TABLE pinyin_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hz TEXT NOT NULL,
                py TEXT NOT NULL,
                abbr TEXT NOT NULL,
                freq REAL NOT NULL
            )
            """
        )
        conn.executemany(
            "INSERT INTO pinyin_data (hz, py, abbr, freq) VALUES (?, ?, ?, ?)",
            ((e["hz"], e["py"], e["abbr"], e["freq"]) for e in entries),
        )
        conn.execute("CREATE INDEX idx_pinyin_freq ON pinyin_data(py, freq DESC)")
        conn.execute("CREATE INDEX idx_abbr_freq ON pinyin_data(abbr, freq DESC)")
        conn.execute("ANALYZE")
        conn.commit()
        conn.execute("VACUUM")
    finally:
        conn.close()


def write_frequency(entries, output_path):
    frequencies = {}
    for entry in entries:
        hz = entry["hz"]
        frequencies[hz] = max(frequencies.get(hz, 0), entry["freq"])
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(frequencies, f, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        f.write("\n")
    return len(frequencies)


def sqlite_stats(path):
    conn = sqlite3.connect(path)
    try:
        row_count = conn.execute("SELECT COUNT(*) FROM pinyin_data").fetchone()[0]
        py_count = conn.execute("SELECT COUNT(DISTINCT py) FROM pinyin_data").fetchone()[0]
        hz_count = conn.execute("SELECT COUNT(DISTINCT hz) FROM pinyin_data").fetchone()[0]
    finally:
        conn.close()
    return {"rows": row_count, "distinct_py": py_count, "distinct_hz": hz_count}


def main():
    parser = argparse.ArgumentParser(description="Build YingHan pinyin data from rime-ice dictionaries.")
    parser.add_argument("--rime-root", required=True, type=Path)
    parser.add_argument("--sqlite-output", required=True, type=Path)
    parser.add_argument("--frequency-output", required=True, type=Path)
    parser.add_argument("--metadata-output", required=True, type=Path)
    parser.add_argument("--source-ref", default="")
    parser.add_argument("--source-commit", default="")
    parser.add_argument("--max-low-frequency", type=float, default=20.0)
    parser.add_argument("--min-low-frequency-length", type=int, default=4)
    args = parser.parse_args()

    entries, build_stats = load_entries(args.rime_root)
    original_entry_count = len(entries)
    entries, pruned_count = prune_entries(entries, args.max_low_frequency, args.min_low_frequency_length)
    entries.sort(key=lambda e: (e["py"], -e["freq"], e["hz"]))

    args.sqlite_output.parent.mkdir(parents=True, exist_ok=True)
    args.frequency_output.parent.mkdir(parents=True, exist_ok=True)
    args.metadata_output.parent.mkdir(parents=True, exist_ok=True)

    write_sqlite(entries, args.sqlite_output)
    frequency_count = write_frequency(entries, args.frequency_output)
    stats = sqlite_stats(args.sqlite_output)

    metadata = {
        "source": "https://github.com/iDvel/rime-ice",
        "source_ref": args.source_ref,
        "source_commit": args.source_commit,
        "import_files": IMPORT_FILES,
        "sqlite": {
            **stats,
            "bytes": os.path.getsize(args.sqlite_output),
            "sha256": sha256(args.sqlite_output),
        },
        "frequency": {
            "entries": frequency_count,
            "bytes": os.path.getsize(args.frequency_output),
            "sha256": sha256(args.frequency_output),
        },
        "build": build_stats,
        "pruning": {
            "original_entries": original_entry_count,
            "pruned_entries": pruned_count,
            "kept_entries": len(entries),
            "max_low_frequency": args.max_low_frequency,
            "min_low_frequency_length": args.min_low_frequency_length,
        },
        "samples": {},
    }

    frequency_data = json.loads(args.frequency_output.read_text(encoding="utf-8"))
    for sample in ("你好", "中国", "测试", "软件", "3D打印"):
        metadata["samples"][sample] = frequency_data.get(sample)

    with open(args.metadata_output, "w", encoding="utf-8") as f:
        json.dump(metadata, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")

    print(json.dumps(metadata, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
