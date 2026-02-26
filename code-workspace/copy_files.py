"""
Copy Files and Folders Script

This script copies files and folders from a source location to a destination location,
only copying files modified after a specified date (01-01-2026) and ignoring empty folders.

Features:
- Recursively copies files and maintains folder structure
- Only copies files modified after 01-01-2026
- Creates destination sub-folders as needed
- Ignores empty folders
- Provides detailed logging
"""

import os
import shutil
import sys
from datetime import datetime
from pathlib import Path
from typing import Tuple

# ============================================================================
# CONFIGURATION
# ============================================================================

# Source and destination paths
SOURCE_PATH = r"R:\E\E4-0001 - Shanrath Housing Development, Athy, Co. Kildare\5. Photos"
DESTINATION_PATH = r"C:\Users\robie\Downloads\E4-0001 - Shanrath Housing Development, Athy, Co. Kildare"

# Date filter - only copy files modified after this date
DATE_CUTOFF = datetime(2026, 1, 1)

# Logging Configuration
SCRIPT_DIR = Path(__file__).parent.absolute()
LOG_DIR = SCRIPT_DIR / "logs"
LOG_DIR.mkdir(exist_ok=True)
LOG_FILE = LOG_DIR / f"copy_files_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

# ============================================================================
# FUNCTIONS
# ============================================================================

def log_message(message: str, log_file: Path = None):
    """Log message to both console and file"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    log_line = f"{timestamp} - {message}"
    print(log_line)
    
    if log_file:
        try:
            with open(log_file, 'a', encoding='utf-8') as f:
                f.write(log_line + '\n')
        except Exception as e:
            print(f"Warning: Could not write to log file: {e}")

def should_copy_file(file_path: Path) -> bool:
    """
    Check if a file should be copied based on its modification date
    
    Args:
        file_path: Path to the file to check
    
    Returns:
        True if file should be copied (modified after DATE_CUTOFF), False otherwise
    """
    try:
        # Get the file's modification time
        mod_time = datetime.fromtimestamp(os.path.getmtime(file_path))
        return mod_time > DATE_CUTOFF
    except (OSError, ValueError) as e:
        log_message(f"   ⚠️  Could not check modification time for {file_path}: {e}", LOG_FILE)
        # If we can't check the date, skip the file to be safe
        return False

def copy_files_recursive(source: Path, destination: Path) -> Tuple[int, int, int]:
    """
    Recursively copy files from source to destination, maintaining folder structure
    
    Args:
        source: Source directory path
        destination: Destination directory path
    
    Returns:
        Tuple of (files_copied, files_skipped, errors)
    """
    files_copied = 0
    files_skipped = 0
    errors = 0
    
    try:
        # Ensure destination directory exists
        destination.mkdir(parents=True, exist_ok=True)
        
        # Iterate through all items in the source directory
        for item in source.iterdir():
            source_item = source / item.name
            dest_item = destination / item.name
            
            try:
                if source_item.is_file():
                    # Check if file should be copied based on modification date
                    if should_copy_file(source_item):
                        try:
                            # Copy the file
                            shutil.copy2(source_item, dest_item)
                            mod_time = datetime.fromtimestamp(os.path.getmtime(source_item))
                            log_message(f"   ✓ Copied: {source_item.name} (modified: {mod_time.strftime('%Y-%m-%d %H:%M:%S')})", LOG_FILE)
                            files_copied += 1
                        except Exception as e:
                            log_message(f"   ❌ Error copying file {source_item}: {e}", LOG_FILE)
                            errors += 1
                    else:
                        mod_time = datetime.fromtimestamp(os.path.getmtime(source_item))
                        log_message(f"   ⊘ Skipped (before cutoff): {source_item.name} (modified: {mod_time.strftime('%Y-%m-%d %H:%M:%S')})", LOG_FILE)
                        files_skipped += 1
                
                elif source_item.is_dir():
                    # Recursively process subdirectories
                    sub_files_copied, sub_files_skipped, sub_errors = copy_files_recursive(source_item, dest_item)
                    files_copied += sub_files_copied
                    files_skipped += sub_files_skipped
                    errors += sub_errors
                    
                    # After processing subdirectory, check if destination folder is empty
                    # If empty, remove it (ignore empty folders)
                    try:
                        if dest_item.exists() and dest_item.is_dir():
                            if not any(dest_item.iterdir()):
                                dest_item.rmdir()
                                log_message(f"   🗑️  Removed empty folder: {dest_item.relative_to(Path(DESTINATION_PATH))}", LOG_FILE)
                    except Exception as e:
                        # If we can't remove the folder, just log and continue
                        log_message(f"   ⚠️  Could not remove empty folder {dest_item}: {e}", LOG_FILE)
            
            except Exception as e:
                log_message(f"   ❌ Error processing {source_item}: {e}", LOG_FILE)
                errors += 1
    
    except PermissionError as e:
        log_message(f"   ❌ Permission denied accessing {source}: {e}", LOG_FILE)
        errors += 1
    except Exception as e:
        log_message(f"   ❌ Unexpected error processing {source}: {e}", LOG_FILE)
        errors += 1
    
    return files_copied, files_skipped, errors

def main():
    """Main function to perform the file copy operation"""
    
    log_message("=" * 70, LOG_FILE)
    log_message("📋 Starting File Copy Operation...", LOG_FILE)
    log_message("=" * 70, LOG_FILE)
    log_message(f"📁 Source: {SOURCE_PATH}", LOG_FILE)
    log_message(f"📁 Destination: {DESTINATION_PATH}", LOG_FILE)
    log_message(f"📅 Date Cutoff: Files modified after {DATE_CUTOFF.strftime('%Y-%m-%d')}", LOG_FILE)
    log_message("", LOG_FILE)
    
    # Validate source path
    source_path = Path(SOURCE_PATH)
    if not source_path.exists():
        log_message(f"❌ ERROR: Source path does not exist: {SOURCE_PATH}", LOG_FILE)
        return 1
    
    if not source_path.is_dir():
        log_message(f"❌ ERROR: Source path is not a directory: {SOURCE_PATH}", LOG_FILE)
        return 1
    
    # Create destination path if it doesn't exist
    destination_path = Path(DESTINATION_PATH)
    
    log_message("🔄 Starting copy operation...", LOG_FILE)
    log_message("", LOG_FILE)
    
    start_time = datetime.now()
    
    # Perform the copy operation
    files_copied, files_skipped, errors = copy_files_recursive(source_path, destination_path)
    
    end_time = datetime.now()
    duration = end_time - start_time
    
    log_message("", LOG_FILE)
    log_message("=" * 70, LOG_FILE)
    log_message("✅ Copy operation completed!", LOG_FILE)
    log_message("=" * 70, LOG_FILE)
    log_message(f"📊 Summary:", LOG_FILE)
    log_message(f"   - Files copied: {files_copied}", LOG_FILE)
    log_message(f"   - Files skipped (before cutoff): {files_skipped}", LOG_FILE)
    log_message(f"   - Errors: {errors}", LOG_FILE)
    log_message(f"   - Duration: {duration}", LOG_FILE)
    log_message(f"📝 Log saved to: {LOG_FILE}", LOG_FILE)
    log_message("=" * 70, LOG_FILE)
    
    return 0 if errors == 0 else 1

# ============================================================================
# MAIN
# ============================================================================

if __name__ == "__main__":
    try:
        exit_code = main()
        print()
        input("Press Enter to exit...")
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print()
        print("❌ Operation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print()
        print(f"❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        print()
        input("Press Enter to exit...")
        sys.exit(1)