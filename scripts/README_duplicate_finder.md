# Duplicate File Finder & Deleter

Two Python scripts to find duplicate files by hash on network (or any) drives, log them to CSV, and delete only the ones you mark.

**No extra packages required** — uses only the Python standard library (Python 3.6+).

---

## 1. Find duplicates and create the log

```bash
# Scan only network drives (Windows; Z:, Y:, etc.)
python find_duplicate_files.py

# Scan all drives (local + network)
python find_duplicate_files.py --all-drives

# Scan specific paths (drives or UNC paths)
python find_duplicate_files.py Z:\ \\server\share\folder

# Custom output file and options
python find_duplicate_files.py -o my_duplicates.csv --min-size 1024 Z:\
```

**Options:**

| Option | Description |
|--------|-------------|
| `--network-only` | Scan only Windows network drives (default when no paths given) |
| `--all-drives` | Scan all local and network drives |
| `paths` | One or more roots to scan (e.g. `Z:\`, `\\server\share`) |
| `-o`, `--output` | Output CSV path (default: `duplicate_files_log.csv`) |
| `--min-size` | Minimum file size in bytes |
| `--max-size` | Skip files larger than this (bytes) |
| `--extensions` | Only these extensions, comma-separated (e.g. `.jpg,.png`) |
| `--hash` | `sha256` (default) or `md5` |

The CSV has columns: **file_name**, **full_path**, **file_size**, **date_modified**, **file_hash**, **duplicate_group_id**, **mark_for_deletion**.

---

## 2. Mark files to delete

Open the CSV in Excel or any editor. For each duplicate you want to remove, put one of these in the **mark_for_deletion** column:

- `Y` or `y`
- `1`
- `yes` or `true` or `x` or `delete`

Leave it **empty** for files you want to keep. Typically you keep one copy per duplicate group and mark the rest.

---

## 3. Delete the marked files

```bash
# Use default CSV name (duplicate_files_log.csv)
python delete_marked_duplicates.py

# Use a specific CSV
python delete_marked_duplicates.py my_duplicates.csv

# See what would be deleted without deleting
python delete_marked_duplicates.py --dry-run

# Skip confirmation (use with care)
python delete_marked_duplicates.py --no-confirm
```

**Options:**

| Option | Description |
|--------|-------------|
| `csv_file` | Path to the CSV (default: `duplicate_files_log.csv`) |
| `--dry-run` | List files that would be deleted; do not delete |
| `--no-confirm` | Do not ask for confirmation before deleting |

---

## Tips

- **Large scans**: Use `--max-size` to skip very large files and speed up hashing.
- **Network drives**: First script uses Windows “network drive” type when you run with no paths; you can also pass UNC paths like `\\server\share`.
- **Safety**: Always run `delete_marked_duplicates.py` with `--dry-run` first, then without `--no-confirm` so you can confirm before anything is deleted.
