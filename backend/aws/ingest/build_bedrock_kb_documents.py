"""Build clean chapter documents and JSONL metadata for AWS ingestion."""

from __future__ import annotations

import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CHAPTER_CSV = ROOT / "data" / "processed" / "chapter_text.csv"
OUT_DIR = ROOT / "data" / "aws_kb_documents"


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT_DIR / "manifest.jsonl"
    with CHAPTER_CSV.open(newline="", encoding="utf-8") as f, manifest_path.open("w", encoding="utf-8") as manifest:
        reader = csv.DictReader(f)
        for row in reader:
            chapter = int(row["chapter"])
            if chapter == 12:
                continue
            file_name = f"chapter_{chapter:02d}.txt"
            out_path = OUT_DIR / file_name
            body = "\n".join([
                f"Title: Chapter {chapter}: {row['chapter_title']}",
                f"Life stage: {row.get('life_stage','')}",
                f"Primary locations: {row.get('primary_locations','')}",
                f"Approx years: {row.get('approx_start_year','')}–{row.get('approx_end_year','')}",
                "",
                row["text"],
            ])
            out_path.write_text(body, encoding="utf-8")
            manifest.write(json.dumps({
                "file": file_name,
                "chapter": chapter,
                "chapter_title": row["chapter_title"],
                "life_stage": row.get("life_stage", ""),
                "primary_locations": row.get("primary_locations", ""),
                "approx_start_year": row.get("approx_start_year", ""),
                "approx_end_year": row.get("approx_end_year", ""),
            }) + "\n")
    print(f"Wrote AWS KB documents to {OUT_DIR}")


if __name__ == "__main__":
    main()
