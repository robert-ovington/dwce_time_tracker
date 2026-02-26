"""
Sync Projects from Microsoft Access to Supabase

This script automatically syncs projects from the current year's table in Access
(e.g., "2026", "2027") to Supabase's projects table.

Requirements:
    pip install pyodbc supabase pandas

Setup:
    1. Install Microsoft Access Database Engine (if not already installed)
       Download from: https://www.microsoft.com/en-us/download/details.aspx?id=54920
    2. Set your Supabase credentials below
    3. Update the Access database path
"""

import pyodbc
from supabase import create_client, Client
from typing import List, Dict, Any, Optional
from datetime import datetime
import re
import os
import sys
import logging
from pathlib import Path

# ============================================================================
# CONFIGURATION
# ============================================================================

# Supabase Configuration
# Can be set via environment variables (recommended for production) or hardcoded below
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ifvbajmmjkkuvhigcgad.supabase.co")
# ⚠️ CRITICAL: You MUST use the service_role key (NOT anon key) for bulk syncs
# The anon key will fail with "new row violates row-level security policy" errors
# Find your service_role key in: Supabase Dashboard → Settings → API → service_role key (secret)
# The service_role key bypasses RLS policies and is required for bulk inserts/updates
# For production, set SUPABASE_SERVICE_ROLE_KEY environment variable instead
SUPABASE_KEY = os.environ.get(
    "SUPABASE_SERVICE_ROLE_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlmdmJham1tamtrdXZoaWdjZ2FkIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDQzNzU1NiwiZXhwIjoyMDgwMDEzNTU2fQ.9n7QrMbp__ZlIHxVv99Dzs4jjkmPwNSayzyNUTZe1C8"
)

# Access Database Configuration
# Can be set via environment variable ACCESS_DB_PATH or hardcoded below
ACCESS_DB_PATH = os.environ.get("ACCESS_DB_PATH", r"W:\Master Files\Master Job List.accdb")

# Logging Configuration
# Log file will be created in the same directory as the script
SCRIPT_DIR = Path(__file__).parent.absolute()
LOG_DIR = SCRIPT_DIR / "logs"
LOG_DIR.mkdir(exist_ok=True)  # Create logs directory if it doesn't exist
LOG_FILE = LOG_DIR / f"sync_projects_{datetime.now().strftime('%Y%m%d')}.log"

# Access Database Connection String
ACCESS_CONN_STRING = (
    r"Driver={{Microsoft Access Driver (*.mdb, *.accdb)}};"
    r"DBQ={};"
).format(ACCESS_DB_PATH)

# ============================================================================
# LOGGING SETUP
# ============================================================================

def setup_logging():
    """Configure logging to both file and console"""
    # Create logs directory if it doesn't exist
    LOG_DIR.mkdir(exist_ok=True)
    
    # Configure logging
    log_format = '%(asctime)s - %(levelname)s - %(message)s'
    date_format = '%Y-%m-%d %H:%M:%S'
    
    # File handler - logs everything
    file_handler = logging.FileHandler(LOG_FILE, encoding='utf-8')
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(logging.Formatter(log_format, date_format))
    
    # Console handler - logs INFO and above
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(logging.Formatter(log_format, date_format))
    
    # Root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)
    root_logger.addHandler(file_handler)
    root_logger.addHandler(console_handler)
    
    return root_logger

# Initialize logging
logger = setup_logging()

# ============================================================================
# FIELD MAPPING
# ============================================================================

# Map Access column names to Supabase column names
# Based on Access table structure and Supabase projects table
FIELD_MAPPING = {
    # Core fields
    "Job_Number": "project_number",  # Job_Number becomes project_number in Supabase
    "Description_of_Work": "description_of_work",  # Description of work
    "Folder_Description": "project_name",  # If Supabase has this field
    
    # Location fields
    "Address": "address",  # Job address
    "Townland": "townland",  # Townland
    "Town": "town",  # Town
    "County": "county",  # County
  
    # Client information
    "Client_Name": "client_name",  # Client name
    
    # Status fields
    "Enabled": "is_active",  # Enabled flag maps to is_active
#   "Status": "status",  # Status field
#   "Task_Status": "task_status",  # Task status
    
    # Dates
    "Completion_Date": "completion_date",  # Completion date
    
    # Coordinates (will be converted)
    "Latitude_North": "latitude",  # Will convert to numeric
    "Longitude_West": "longitude",  # Will convert to numeric (negative for West)
    
    # Additional fields that might be useful
}

# ============================================================================
# SYNC FUNCTIONS
# ============================================================================

def get_current_year_table_name() -> str:
    """Get the current year's table name (e.g., '2026', '2027')"""
    current_year = datetime.now().year
    return str(current_year)


def read_access_projects(table_name: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Read projects from Access database
    
    Args:
        table_name: Table name to read from (defaults to current year)
    """
    if table_name is None:
        table_name = get_current_year_table_name()
    
    try:
        conn = pyodbc.connect(ACCESS_CONN_STRING)
        cursor = conn.cursor()
        
        # Query the year-based table (e.g., "2026")
        # Only get records where Enabled = True (active projects)
        # Note: Calculated fields like Folder_Description are included in SELECT *
        query = f"SELECT * FROM [{table_name}] WHERE [Enabled] = True"
        
        logger.info(f"📊 Reading from table: {table_name}")
        cursor.execute(query)
        columns = [column[0] for column in cursor.description]
        rows = cursor.fetchall()
        
        projects = []
        for row in rows:
            project = dict(zip(columns, row))
            projects.append(project)
        
        cursor.close()
        conn.close()
        
        # Verify calculated fields are present (Folder_Description might not always be returned)
        if projects and "Folder_Description" not in projects[0]:
            logger.warning("⚠️  Folder_Description (calculated field) not found in query results - will use Job_Number as fallback")
        
        logger.info(f"✅ Read {len(projects)} active projects from Access table '{table_name}'")
        if projects:
            logger.debug(f"   Sample columns: {list(projects[0].keys())[:5]}...")
        return projects
        
    except Exception as e:
        logger.error(f"❌ Error reading from Access table '{table_name}': {e}")
        logger.error(f"💡 Make sure the table '{table_name}' exists in the database")
        raise


def convert_coordinate(coord_str: Optional[str], is_longitude: bool = False) -> Optional[float]:
    """
    Convert coordinate string to numeric value
    
    Args:
        coord_str: Coordinate string (e.g., "53.1234" or "53°12'34")
        is_longitude: If True, negate West longitude values
    
    Returns:
        Numeric coordinate value or None
    """
    if not coord_str:
        return None
    
    try:
        # Try direct numeric conversion first
        coord_str_clean = str(coord_str).strip()
        if not coord_str_clean:
            return None
        
        # Remove any degree symbols or other characters
        coord_str_clean = re.sub(r'[^\d.\-]', '', coord_str_clean)
        
        if not coord_str_clean:
            return None
        
        value = float(coord_str_clean)
        
        # For West longitude, make it negative (standard convention)
        if is_longitude and value > 0:
            value = -abs(value)
        
        return value
    except (ValueError, TypeError):
        print(f"⚠️  Could not convert coordinate: {coord_str}")
        return None


def map_fields(access_project: Dict[str, Any]) -> Dict[str, Any]:
    """
    Map Access fields to Supabase fields with data type conversions
    """
    supabase_project = {}
    
    for access_field, supabase_field in FIELD_MAPPING.items():
        if access_field in access_project:
            value = access_project[access_field]
            
            # Handle None/empty values
            if value is None:
                supabase_project[supabase_field] = None
                continue
            
            # Special handling for coordinates
            if supabase_field == "latitude":
                supabase_project[supabase_field] = convert_coordinate(value, is_longitude=False)
            elif supabase_field == "longitude":
                supabase_project[supabase_field] = convert_coordinate(value, is_longitude=True)
            # Special handling for boolean fields (Yes/No in Access)
            elif supabase_field == "is_active":
                # Access Yes/No fields are stored as True/False or -1/0
                if isinstance(value, bool):
                    supabase_project[supabase_field] = value
                elif value == -1 or value == 1 or str(value).upper() == "TRUE":
                    supabase_project[supabase_field] = True
                else:
                    supabase_project[supabase_field] = False
            # Handle date fields
            elif supabase_field == "completion_date" and value:
                if isinstance(value, datetime):
                    supabase_project[supabase_field] = value.strftime("%Y-%m-%d")
                elif isinstance(value, str):
                    # Try to parse the date string
                    try:
                        dt = datetime.strptime(value, "%Y-%m-%d")
                        supabase_project[supabase_field] = dt.strftime("%Y-%m-%d")
                    except:
                        supabase_project[supabase_field] = None
                else:
                    supabase_project[supabase_field] = None
            # Handle text fields - trim whitespace
            elif isinstance(value, str):
                supabase_project[supabase_field] = value.strip() if value.strip() else None
            else:
                # For other types, use as-is
                supabase_project[supabase_field] = value
    
    # Ensure project_name is set (REQUIRED field for Supabase and the app)
    # project_name is used in dropdowns and lookups, so it must be populated
    if "project_name" not in supabase_project or not supabase_project["project_name"]:
        # Folder_Description is a calculated field - try it first if available
        if "Folder_Description" in access_project and access_project["Folder_Description"]:
            folder_desc = str(access_project["Folder_Description"]).strip()
            if folder_desc:
                supabase_project["project_name"] = folder_desc
        # Fallback to Job_Number if Folder_Description is empty or missing
        if "project_name" not in supabase_project or not supabase_project["project_name"]:
            if "Job_Number" in access_project and access_project["Job_Number"]:
                job_number = str(access_project["Job_Number"]).strip()
                # Try to enhance with address if available for better identification
                if "Address" in access_project and access_project["Address"]:
                    address = str(access_project["Address"]).strip()
                    if address:
                        supabase_project["project_name"] = f"{job_number} - {address}"
                    else:
                        supabase_project["project_name"] = job_number
                else:
                    supabase_project["project_name"] = job_number
            else:
                # Last resort: use ID if nothing else available
                record_id = str(access_project.get("ID", "Unknown")).strip()
                print(f"⚠️  Warning: No project_name found for record ID {record_id}")
                print(f"   Available fields: {list(access_project.keys())[:10]}...")
                supabase_project["project_name"] = f"Project {record_id}"  # Use ID as last resort instead of skipping
    
    # Ensure is_active is set (default to True if not mapped)
    if "is_active" not in supabase_project:
        supabase_project["is_active"] = True
    
    return supabase_project


def sync_to_supabase(projects: List[Dict[str, Any]], mode: str = "upsert"):
    """
    Sync projects to Supabase
    
    Args:
        projects: List of project dictionaries
        mode: "upsert" (update existing, insert new) or "replace" (delete all and insert)
    """
    try:
        supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
        
        if mode == "replace":
            # Delete all existing projects (use with caution!)
            print("⚠️  Deleting all existing projects...")
            supabase.table("projects").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
            print("✅ Deleted existing projects")
        
        # Map and filter projects
        mapped_projects = []
        skipped = 0
        
        for project in projects:
            mapped = map_fields(project)
            if mapped is not None:
                mapped_projects.append(mapped)
            else:
                skipped += 1
        
        if skipped > 0:
            print(f"⚠️  Skipped {skipped} projects (missing required fields)")
        
        if not mapped_projects:
            print("⚠️  No valid projects to sync")
            return
        
        # Process projects in batches
        batch_size = 100
        total = len(mapped_projects)
        updated_count = 0
        inserted_count = 0
        
        for i in range(0, total, batch_size):
            batch = mapped_projects[i:i + batch_size]
            
            if mode == "upsert":
                # Upsert: Update if exists (based on project_name), insert if new
                for project in batch:
                    project_name = project.get("project_name", "")
                    if not project_name:
                        continue
                    
                    try:
                        # Try to find existing project by project_name
                        existing = supabase.table("projects").select("id").eq("project_name", project_name).execute()
                        
                        if existing.data and len(existing.data) > 0:
                            # Update existing
                            project_id = existing.data[0]["id"]
                            # Remove project_name from update to avoid conflicts
                            update_data = {k: v for k, v in project.items() if k != "project_name"}
                            supabase.table("projects").update(update_data).eq("id", project_id).execute()
                            updated_count += 1
                            if (updated_count + inserted_count) % 10 == 0:
                                print(f"  Processed {updated_count + inserted_count}/{total}...")
                        else:
                            # Insert new
                            supabase.table("projects").insert(project).execute()
                            inserted_count += 1
                            if (updated_count + inserted_count) % 10 == 0:
                                print(f"  Processed {updated_count + inserted_count}/{total}...")
                    except Exception as e:
                        print(f"  ❌ Error processing '{project_name}': {e}")
            else:
                # Insert all (for replace mode)
                try:
                    supabase.table("projects").insert(batch).execute()
                    inserted_count += len(batch)
                except Exception as e:
                    print(f"  ❌ Error inserting batch: {e}")
            
            print(f"✅ Processed batch {i//batch_size + 1}/{(total + batch_size - 1)//batch_size}")
        
        print(f"✅ Successfully synced {total} projects to Supabase")
        if mode == "upsert":
            print(f"   - Updated: {updated_count}")
            print(f"   - Inserted: {inserted_count}")
        
    except Exception as e:
        print(f"❌ Error syncing to Supabase: {e}")
        import traceback
        traceback.print_exc()
        raise


def main():
    """Main sync function"""
    try:
        print("=" * 70)
        print("🔄 Starting project sync from Access to Supabase...")
        print("=" * 70)
        print(f"📁 Access DB: {ACCESS_DB_PATH}")
        print(f"🌐 Supabase: {SUPABASE_URL}")
        
        # Get current year table name
        table_name = get_current_year_table_name()
        print(f"📅 Using table: {table_name}")
        print()
        
        # Read from Access
        try:
            projects = read_access_projects(table_name)
        except Exception as e:
            print()
            print("=" * 70)
            print("❌ ERROR: Failed to read from Access database")
            print("=" * 70)
            print(f"Error details: {e}")
            print()
            print("Full error traceback:")
            import traceback
            traceback.print_exc()
            print()
            print("💡 Troubleshooting:")
            print("   1. Check that the Access database file exists at: {ACCESS_DB_PATH}")
            print("   2. Ensure the table for the current year exists (e.g., '2026')")
            print("   3. Verify Microsoft Access Database Engine is installed")
            print("      Download: https://www.microsoft.com/en-us/download/details.aspx?id=54920")
            print("   4. Check that the database is not locked (close Access if open)")
            print("   5. Verify you have read permissions for the database file")
            print()
            input("Press Enter to exit...")  # Keep window open
            return
        
        if not projects:
            print("⚠️  No active projects found in Access database")
            print("   (Only projects with Enabled = True are synced)")
            print()
            input("Press Enter to exit...")
            return
        
        # Sync to Supabase
        # Use "upsert" to update existing and insert new
        # Use "replace" to delete all and replace (use with caution!)
        try:
            sync_to_supabase(projects, mode="upsert")
        except Exception as e:
            print()
            print("=" * 70)
            print("❌ ERROR: Failed to sync to Supabase")
            print("=" * 70)
            print(f"Error details: {e}")
            print()
            print("Full error traceback:")
            import traceback
            traceback.print_exc()
            print()
            print("💡 Troubleshooting:")
            print("   1. ⚠️  MOST COMMON ISSUE: Using anon key instead of service_role key")
            print("      → The service_role key is REQUIRED for bulk syncs (bypasses RLS)")
            print("      → Find it in: Supabase Dashboard → Settings → API → service_role key (secret)")
            print("   2. Verify SUPABASE_URL and SUPABASE_KEY are correct")
            print(f"      Current URL: {SUPABASE_URL}")
            key_preview = SUPABASE_KEY[:20] + "..." if SUPABASE_KEY and len(SUPABASE_KEY) > 20 else "(not set)"
            print(f"      Current Key: {key_preview}")
            if SUPABASE_KEY and "eyJ" in SUPABASE_KEY:
                # Check if it starts with anon key pattern vs service_role
                print("      ⚠️  If your key starts with 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'")
                print("         and you see RLS errors, you're using the anon key!")
                print("         You MUST use the service_role key for bulk operations.")
            print("   3. Check that the 'projects' table exists in Supabase")
            print("   4. If you must use anon key, update RLS policies to allow inserts/updates")
            print("   5. Check Supabase dashboard for error logs")
            print("   6. Verify your internet connection")
            print()
            input("Press Enter to exit...")  # Keep window open
            return
        
        print()
        print("=" * 70)
        print("✅ Sync completed successfully!")
        print("=" * 70)
        print()
        input("Press Enter to exit...")  # Keep window open
        
    except Exception as e:
        print()
        print("=" * 70)
        print("❌ UNEXPECTED ERROR")
        print("=" * 70)
        print(f"Error: {e}")
        print()
        print("Full error traceback:")
        import traceback
        traceback.print_exc()
        print()
        input("Press Enter to exit...")  # Keep window open


if __name__ == "__main__":
    main()
