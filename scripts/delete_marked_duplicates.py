#!/usr/bin/env python3
"""
Read the duplicate-files CSV produced by find_duplicate_files.py and delete
all files where mark_for_deletion is set (Y, y, 1, yes, true).
"""

import argparse
import csv
import os
import sys
from pathlib import Path


# Values that mean "mark for deletion"
MARK_VALUES = frozenset({"y", "yes", "1", "true", "x", "delete"})


def is_marked(value):
    if value is None:
        return False
    return str(value).strip().lower() in MARK_VALUES


def main():
    ap = argparse.ArgumentParser(
        description="Delete files marked in the duplicate-files CSV (mark_for_deletion = Y)."
    )
    ap.add_argument(
        "csv_file",
        nargs="?",
        default="duplicate_files_log.csv",
        help="Path to the CSV from find_duplicate_files.py (default: duplicate_files_log.csv).",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Only list files that would be deleted; do not delete.",
    )
    ap.add_argument(
        "--no-confirm",
        action="store_true",
        help="Skip confirmation prompt (use with caution).",
    )
    args = ap.parse_args()

    csv_path = Path(args.csv_file)
    if not csv_path.exists():
        print(f"CSV file not found: {csv_path}", file=sys.stderr)
        sys.exit(1)

    # Find column index for full_path and mark_for_deletion
    to_delete = []
    with open(csv_path, newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if not header:
            print("CSV is empty.", file=sys.stderr)
            sys.exit(1)
        try:
            path_idx = header.index("full_path")
            mark_idx = header.index("mark_for_deletion")
        except ValueError as e:
            print(f"CSV must have columns 'full_path' and 'mark_for_deletion'. {e}", file=sys.stderr)
            sys.exit(1)
        for row in reader:
            if len(row) <= max(path_idx, mark_idx):
                continue
            path = row[path_idx].strip()
            if not path:
                continue
            if is_marked(row[mark_idx]):
                to_delete.append(path)

    if not to_delete:
        print("No files are marked for deletion (mark_for_deletion = Y, 1, yes, etc.).")
        return

    print(f"{len(to_delete)} file(s) marked for deletion:")
    for p in to_delete[:20]:
        print(f"  {p}")
    if len(to_delete) > 20:
        print(f"  ... and {len(to_delete) - 20} more.")

    if args.dry_run:
        print("Dry run: no files were deleted.")
        return

    if not args.no_confirm:
        reply = input("Proceed with deletion? [y/N]: ").strip().lower()
        if reply not in ("y", "yes"):
            print("Aborted.")
            return

    deleted = 0
    failed = []
    for path in to_delete:
        try:
            p = Path(path)
            if p.is_file():
                p.unlink()
                deleted += 1
            else:
                failed.append((path, "not found or not a file"))
        except PermissionError as e:
            failed.append((path, str(e)))
        except OSError as e:
            failed.append((path, str(e)))

    print(f"Deleted {deleted} file(s).")
    if failed:
        print(f"Failed {len(failed)} file(s):")
        for path, err in failed[:10]:
            print(f"  {path}: {err}")
        if len(failed) > 10:
            print(f"  ... and {len(failed) - 10} more.")


if __name__ == "__main__":
    main()
