#!/usr/bin/env python3
"""
Scan network drives (and optionally other paths) for files with duplicate hash values.
Searches all subfolders recursively. Outputs a CSV log that you can edit to mark
files for deletion, then run delete_marked_duplicates.py.
"""

import argparse
import csv
import hashlib
import os
import sys
from pathlib import Path
from datetime import datetime

# Windows drive type constants
DRIVE_REMOTE = 4
DRIVE_FIXED = 3
DRIVE_REMOVABLE = 2


def get_network_drives_windows():
    """Return list of network drive letters on Windows (e.g. ['Z:', 'Y:'])."""
    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32
        buffer_size = 256
        buffer = ctypes.create_unicode_buffer(buffer_size)
        if kernel32.GetLogicalDriveStringsW(buffer_size, buffer):
            drives = buffer.value.split('\x00')[:-1]
            network = []
            for d in drives:
                if kernel32.GetDriveTypeW(d) == DRIVE_REMOTE:
                    network.append(d)
            return network
    except Exception:
        pass
    return []


def get_all_drives_windows():
    """Return all available drive letters on Windows."""
    try:
        import ctypes
        buffer_size = 256
        buffer = ctypes.create_unicode_buffer(buffer_size)
        if ctypes.windll.kernel32.GetLogicalDriveStringsW(buffer_size, buffer):
            return buffer.value.split('\x00')[:-1]
    except Exception:
        pass
    return []


def file_hash(path, block_size=65536, algo='sha256'):
    """Compute hash of file contents. Uses chunked reading for large files."""
    h = hashlib.new(algo)
    try:
        with open(path, 'rb') as f:
            for chunk in iter(lambda: f.read(block_size), b''):
                h.update(chunk)
        return h.hexdigest()
    except (OSError, PermissionError):
        return None


def safe_stat(path):
    """Get size and mtime; return None on error."""
    try:
        st = os.stat(path)
        return st.st_size, st.st_mtime
    except (OSError, PermissionError):
        return None


def _skip_on_error(err):
    """On permission/access errors during walk, skip the directory and continue."""
    pass


def scan_path(root_path, min_size=0, max_size=None, extensions=None, hash_algo='sha256'):
    """
    Recursively walk root_path and all subfolders; yield (path, size, mtime) for each file.
    Optionally filter by size and extension. Inaccessible subfolders are skipped and scanning continues.
    """
    root = Path(root_path).resolve()
    if not root.exists():
        return
    if extensions is not None:
        extensions = { e.lower().lstrip('.') for e in extensions }
    for dirpath, _dirnames, filenames in os.walk(root, topdown=True, onerror=_skip_on_error):
        try:
            dirpath = Path(dirpath)
        except Exception:
            continue
        for name in filenames:
            try:
                fp = dirpath / name
                if not fp.is_file():
                    continue
                stat = safe_stat(fp)
                if stat is None:
                    continue
                size, mtime = stat
                if size < min_size:
                    continue
                if max_size is not None and size > max_size:
                    continue
                if extensions is not None and fp.suffix.lstrip('.').lower() not in extensions:
                    continue
                yield str(fp), size, mtime
            except Exception:
                continue


def find_duplicates(roots, min_size=0, max_size=None, extensions=None, hash_algo='sha256'):
    """
    Scan all roots, compute hashes, return dict: hash -> list of (path, size, mtime).
    Only includes hashes that have more than one file (duplicates).
    """
    hash_to_files = {}
    total = 0
    for root in roots:
        for path, size, mtime in scan_path(root, min_size, max_size, extensions, hash_algo):
            total += 1
            if total % 500 == 0:
                print(f"\rScanned {total} files...", end="", flush=True)
            h = file_hash(path, algo=hash_algo)
            if h is None:
                continue
            if h not in hash_to_files:
                hash_to_files[h] = []
            hash_to_files[h].append((path, size, mtime))
    print(f"\rScanned {total} files. Computing duplicate groups...")
    # Keep only groups with duplicates
    return { h: files for h, files in hash_to_files.items() if len(files) > 1 }


def main():
    ap = argparse.ArgumentParser(
        description="Find duplicate files by hash on network (or other) drives. "
                    "Searches all subfolders recursively. Writes a CSV log."
    )
    ap.add_argument(
        "--network-only",
        action="store_true",
        help="Scan only Windows network drives (e.g. Z:, Y:). Default if no paths given.",
    )
    ap.add_argument(
        "--all-drives",
        action="store_true",
        help="Scan all local and network drives (Windows).",
    )
    ap.add_argument(
        "paths",
        nargs="*",
        help="Additional or alternative paths to scan (e.g. Z:\\, \\\\server\\share).",
    )
    ap.add_argument(
        "-o", "--output",
        default="duplicate_files_log.csv",
        help="Output CSV path (default: duplicate_files_log.csv).",
    )
    ap.add_argument(
        "--min-size",
        type=int,
        default=0,
        help="Minimum file size in bytes (default: 0).",
    )
    ap.add_argument(
        "--max-size",
        type=int,
        default=None,
        help="Maximum file size in bytes (skip larger files).",
    )
    ap.add_argument(
        "--extensions",
        type=str,
        default=None,
        help="Comma-separated extensions to include only (e.g. .jpg,.png). Omit to include all.",
    )
    ap.add_argument(
        "--hash",
        choices=["sha256", "md5"],
        default="sha256",
        help="Hash algorithm (default: sha256).",
    )
    args = ap.parse_args()

    roots = list(args.paths)
    if not roots:
        if args.all_drives and sys.platform == "win32":
            roots = get_all_drives_windows()
            print("Scanning all drives:", roots)
        elif sys.platform == "win32":
            roots = get_network_drives_windows()
            if not roots:
                print("No network drives found. Use --all-drives or pass paths, e.g. find_duplicate_files.py Z:\\")
                sys.exit(1)
            print("Scanning network drives:", roots)
        else:
            print("Please pass at least one path to scan, e.g. find_duplicate_files.py /mnt/nas")
            sys.exit(1)

    extensions = None
    if args.extensions:
        extensions = [e.strip() for e in args.extensions.split(",")]

    dupes = find_duplicates(
        roots,
        min_size=args.min_size,
        max_size=args.max_size,
        extensions=extensions,
        hash_algo=args.hash,
    )

    total_duplicate_files = sum(len(files) for files in dupes.values())
    print(f"Found {len(dupes)} duplicate groups ({total_duplicate_files} files total).")

    outpath = Path(args.output)
    with open(outpath, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow([
            "file_name", "full_path", "file_size", "date_modified", "file_hash",
            "duplicate_group_id", "mark_for_deletion"
        ])
        group_id = 0
        for h, files in dupes.items():
            group_id += 1
            for path, size, mtime in files:
                name = os.path.basename(path)
                try:
                    dt = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
                except Exception:
                    dt = str(mtime)
                writer.writerow([
                    name, path, size, dt, h, group_id, ""
                ])

    print(f"Wrote {outpath}")
    print("Next: open the CSV, set mark_for_deletion to Y for files you want to remove, then run delete_marked_duplicates.py")


if __name__ == "__main__":
    main()
