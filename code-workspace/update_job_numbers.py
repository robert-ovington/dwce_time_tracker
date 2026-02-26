"""
Update Job_Number field in Access Database

This script updates the Job_Number field in the "2026" table for records
where ID ranges from 1611 to 1810. The new Job_Number format is "W6-0" + xxx
where xxx ranges from 001 to 200.

Mapping:
- ID 1611 -> Job_Number = "W6-0001"
- ID 1612 -> Job_Number = "W6-0002"
- ...
- ID 1810 -> Job_Number = "W6-0200"

Requirements:
    pip install pyodbc

Setup:
    1. Install Microsoft Access Database Engine (if not already installed)
       Download from: https://www.microsoft.com/en-us/download/details.aspx?id=54920
    2. Update the ACCESS_DB_PATH below to point to your database
"""

import pyodbc
import os
import sys
from datetime import datetime
from pathlib import Path

# ============================================================================
# CONFIGURATION
# ============================================================================

# Access Database Configuration
# Can be set via environment variable ACCESS_DB_PATH or hardcoded below
ACCESS_DB_PATH = os.environ.get("ACCESS_DB_PATH", r"W:\Master Files\Master Job List.accdb")

# Table name
TABLE_NAME = "2026"

# ID range to update
ID_START = 1611
ID_END = 1810

# Job number prefix
JOB_NUMBER_PREFIX = "W6-0"

# Logging Configuration
SCRIPT_DIR = Path(__file__).parent.absolute()
LOG_DIR = SCRIPT_DIR / "logs"
LOG_DIR.mkdir(exist_ok=True)
LOG_FILE = LOG_DIR / f"update_job_numbers_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

# Access Database Connection String
ACCESS_CONN_STRING = (
    r"Driver={{Microsoft Access Driver (*.mdb, *.accdb)}};"
    r"DBQ={};"
).format(ACCESS_DB_PATH)

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

def generate_job_number(record_id: int) -> str:
    """
    Generate Job_Number based on record ID
    
    Args:
        record_id: The ID field value from the record
    
    Returns:
        Job_Number in format "W6-0" + xxx where xxx is 001-200
    """
    # Calculate the sequence number (001 to 200)
    sequence = record_id - ID_START + 1
    
    # Format as 3-digit number with leading zeros
    sequence_str = f"{sequence:03d}"
    
    return f"{JOB_NUMBER_PREFIX}{sequence_str}"

def update_job_numbers():
    """Update Job_Number field for records in the specified ID range"""
    
    log_message("=" * 70, LOG_FILE)
    log_message("🔄 Starting Job_Number update...", LOG_FILE)
    log_message("=" * 70, LOG_FILE)
    log_message(f"📁 Access DB: {ACCESS_DB_PATH}", LOG_FILE)
    log_message(f"📊 Table: {TABLE_NAME}", LOG_FILE)
    log_message(f"🔢 ID Range: {ID_START} to {ID_END}", LOG_FILE)
    log_message("", LOG_FILE)
    
    try:
        # Connect to Access database
        log_message("📡 Connecting to Access database...", LOG_FILE)
        conn = pyodbc.connect(ACCESS_CONN_STRING)
        cursor = conn.cursor()
        
        # First, verify the table exists and get record count
        log_message(f"🔍 Checking records in table '{TABLE_NAME}'...", LOG_FILE)
        count_query = f"SELECT COUNT(*) FROM [{TABLE_NAME}] WHERE [ID] >= ? AND [ID] <= ?"
        cursor.execute(count_query, (ID_START, ID_END))
        record_count = cursor.fetchone()[0]
        log_message(f"✅ Found {record_count} records in ID range {ID_START}-{ID_END}", LOG_FILE)
        
        if record_count == 0:
            log_message("⚠️  No records found in the specified ID range", LOG_FILE)
            log_message("   Please verify the ID range and table name", LOG_FILE)
            cursor.close()
            conn.close()
            return
        
        # Show preview of what will be updated
        log_message("", LOG_FILE)
        log_message("📋 Preview of updates (first 5 records):", LOG_FILE)
        preview_query = f"SELECT [ID], [Job_Number] FROM [{TABLE_NAME}] WHERE [ID] >= ? AND [ID] <= ? ORDER BY [ID]"
        cursor.execute(preview_query, (ID_START, ID_END))
        preview_rows = cursor.fetchmany(5)
        
        for row in preview_rows:
            record_id, current_job_number = row
            new_job_number = generate_job_number(record_id)
            log_message(f"   ID {record_id}: '{current_job_number}' -> '{new_job_number}'", LOG_FILE)
        
        if record_count > 5:
            log_message(f"   ... and {record_count - 5} more records", LOG_FILE)
        
        # Ask for confirmation
        log_message("", LOG_FILE)
        response = input("⚠️  Do you want to proceed with the update? (yes/no): ").strip().lower()
        
        if response not in ['yes', 'y']:
            log_message("❌ Update cancelled by user", LOG_FILE)
            cursor.close()
            conn.close()
            return
        
        # Perform the update
        log_message("", LOG_FILE)
        log_message("🔄 Updating records...", LOG_FILE)
        
        updated_count = 0
        error_count = 0
        
        # Update each record individually to ensure proper formatting
        for record_id in range(ID_START, ID_END + 1):
            new_job_number = generate_job_number(record_id)
            
            try:
                update_query = f"UPDATE [{TABLE_NAME}] SET [Job_Number] = ? WHERE [ID] = ?"
                cursor.execute(update_query, (new_job_number, record_id))
                
                if cursor.rowcount > 0:
                    updated_count += 1
                    if updated_count % 20 == 0:
                        log_message(f"   Updated {updated_count}/{record_count} records...", LOG_FILE)
                else:
                    # Record with this ID doesn't exist (not an error, just skip)
                    pass
                    
            except Exception as e:
                error_count += 1
                log_message(f"   ❌ Error updating ID {record_id}: {e}", LOG_FILE)
        
        # Commit the transaction
        conn.commit()
        
        log_message("", LOG_FILE)
        log_message("=" * 70, LOG_FILE)
        log_message("✅ Update completed!", LOG_FILE)
        log_message("=" * 70, LOG_FILE)
        log_message(f"📊 Summary:", LOG_FILE)
        log_message(f"   - Records updated: {updated_count}", LOG_FILE)
        if error_count > 0:
            log_message(f"   - Errors: {error_count}", LOG_FILE)
        log_message(f"📝 Log saved to: {LOG_FILE}", LOG_FILE)
        log_message("=" * 70, LOG_FILE)
        
        # Close connection
        cursor.close()
        conn.close()
        
    except pyodbc.Error as e:
        log_message("", LOG_FILE)
        log_message("=" * 70, LOG_FILE)
        log_message("❌ ERROR: Database connection or query failed", LOG_FILE)
        log_message("=" * 70, LOG_FILE)
        log_message(f"Error details: {e}", LOG_FILE)
        log_message("", LOG_FILE)
        log_message("💡 Troubleshooting:", LOG_FILE)
        log_message(f"   1. Check that the Access database file exists at: {ACCESS_DB_PATH}", LOG_FILE)
        log_message(f"   2. Ensure the table '{TABLE_NAME}' exists in the database", LOG_FILE)
        log_message("   3. Verify Microsoft Access Database Engine is installed", LOG_FILE)
        log_message("      Download: https://www.microsoft.com/en-us/download/details.aspx?id=54920", LOG_FILE)
        log_message("   4. Check that the database is not locked (close Access if open)", LOG_FILE)
        log_message("   5. Verify you have write permissions for the database file", LOG_FILE)
        log_message("   6. Ensure the 'Job_Number' and 'ID' fields exist in the table", LOG_FILE)
        raise
        
    except Exception as e:
        log_message("", LOG_FILE)
        log_message("=" * 70, LOG_FILE)
        log_message("❌ UNEXPECTED ERROR", LOG_FILE)
        log_message("=" * 70, LOG_FILE)
        log_message(f"Error: {e}", LOG_FILE)
        import traceback
        log_message("", LOG_FILE)
        log_message("Full traceback:", LOG_FILE)
        log_message(traceback.format_exc(), LOG_FILE)
        raise

# ============================================================================
# MAIN
# ============================================================================

if __name__ == "__main__":
    try:
        update_job_numbers()
        print()
        input("Press Enter to exit...")
    except KeyboardInterrupt:
        print()
        print("❌ Update cancelled by user")
        sys.exit(1)
    except Exception as e:
        print()
        print(f"❌ Fatal error: {e}")
        print()
        input("Press Enter to exit...")
        sys.exit(1)
