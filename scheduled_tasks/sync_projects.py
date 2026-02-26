"""
Sync Projects from Microsoft Access to Supabase (Production Version)

This script automatically syncs projects from the current year's table in Access
(e.g., "2026", "2027") to Supabase's projects table.

Features:
- File-based logging for scheduled runs
- Environment variable support for credentials
- Proper exit codes for task schedulers
- No interactive prompts (suitable for scheduling)
- Comprehensive error handling and reporting

Requirements:
    pip install pyodbc supabase pandas

Setup:
    1. Install Microsoft Access Database Engine (if not already installed)
       Download from: https://www.microsoft.com/en-us/download/details.aspx?id=54920
    2. Set environment variables OR update the hardcoded values below:
       - SUPABASE_URL (or set in script)
       - SUPABASE_SERVICE_ROLE_KEY (or set in script - REQUIRED, not anon key)
       - ACCESS_DB_PATH (or set in script)
    3. Schedule via Windows Task Scheduler or cron
"""

import pyodbc
from supabase import create_client, Client
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime
import re
import os
import sys
import logging
import argparse
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
SUPABASE_KEY = os.environ.get(
    "SUPABASE_SERVICE_ROLE_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlmdmJham1tamtrdXZoaWdjZ2FkIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDQzNzU1NiwiZXhwIjoyMDgwMDEzNTU2fQ.9n7QrMbp__ZlIHxVv99Dzs4jjkmPwNSayzyNUTZe1C8"
)

# Access Database Configuration
# Can be set via environment variable ACCESS_DB_PATH or hardcoded below
ACCESS_DB_PATH = os.environ.get("ACCESS_DB_PATH", r"W:\Master Files\Master Job List.accdb")

# Access Database Connection String
ACCESS_CONN_STRING = (
    r"Driver={{Microsoft Access Driver (*.mdb, *.accdb)}};"
    r"DBQ={};"
).format(ACCESS_DB_PATH)

# Logging Configuration
# Log file will be created in a 'logs' directory next to the script
SCRIPT_DIR = Path(__file__).parent.absolute()
LOG_DIR = SCRIPT_DIR / "logs"
LOG_DIR.mkdir(exist_ok=True)  # Create logs directory if it doesn't exist
LOG_FILE = LOG_DIR / f"sync_projects_{datetime.now().strftime('%Y%m%d')}.log"

# ============================================================================
# LOGGING SETUP
# ============================================================================

def setup_logging() -> logging.Logger:
    """Configure logging to both file and console"""
    # Create logs directory if it doesn't exist
    LOG_DIR.mkdir(exist_ok=True)
    
    # Configure logging format
    log_format = '%(asctime)s - %(levelname)s - %(message)s'
    date_format = '%Y-%m-%d %H:%M:%S'
    
    # File handler - logs everything (DEBUG and above)
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
    root_logger.handlers.clear()  # Clear any existing handlers
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
    "Job_Number": "project_number",
    "Description_of_Work": "description_of_work",
    "Folder_Description": "project_name",
    
    # Location fields
    "Address": "address",
    "Townland": "townland",
    "Town": "town",
    "County": "county",
  
    # Client information
    "Client_Name": "client_name",
    
    # Status fields
    "Enabled": "is_active",
    
    # Dates
    "Completion_Date": "completion_date",
    
    # Coordinates (will be converted)
    "Latitude_North": "latitude",
    "Longitude_West": "longitude",
}

# ============================================================================
# SYNC FUNCTIONS
# ============================================================================

def get_current_year_table_name() -> str:
    """Get the current year's table name (e.g., '2026', '2027')"""
    current_year = datetime.now().year
    return str(current_year)


def read_access_projects(table_name: Optional[str] = None, project_number: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Read projects from Access database
    
    Args:
        table_name: Table name to read from (defaults to current year)
        project_number: Optional project number (Job_Number) to filter by. If specified, only that project is returned.
    
    Returns:
        List of project dictionaries (single item if project_number specified, all active projects otherwise)
    """
    if table_name is None:
        table_name = get_current_year_table_name()
    
    try:
        conn = pyodbc.connect(ACCESS_CONN_STRING)
        cursor = conn.cursor()
        
        # Query the year-based table (e.g., "2026")
        if project_number:
            # Filter by specific Job_Number (project_number)
            query = f"SELECT * FROM [{table_name}] WHERE [Enabled] = True AND [Job_Number] = ?"
            logger.info(f"📊 Reading specific project from table: {table_name}")
            logger.info(f"🔍 Project number: {project_number}")
            cursor.execute(query, (project_number,))
        else:
            # Get all active projects
            query = f"SELECT * FROM [{table_name}] WHERE [Enabled] = True"
            logger.info(f"📊 Reading all active projects from table: {table_name}")
            cursor.execute(query)
        
        columns = [column[0] for column in cursor.description]
        rows = cursor.fetchall()
        
        projects = []
        for row in rows:
            project = dict(zip(columns, row))
            projects.append(project)
        
        cursor.close()
        conn.close()
        
        # Verify calculated fields are present
        if projects and "Folder_Description" not in projects[0]:
            logger.warning("⚠️  Folder_Description (calculated field) not found - will use Job_Number as fallback")
        
        if project_number:
            if projects:
                logger.info(f"✅ Found project '{project_number}' in Access table '{table_name}'")
            else:
                logger.warning(f"⚠️  Project '{project_number}' not found in Access table '{table_name}'")
                logger.warning(f"   (Make sure Enabled = True and Job_Number matches exactly)")
        else:
            logger.info(f"✅ Read {len(projects)} active projects from Access table '{table_name}'")
            if projects:
                logger.debug(f"   Sample columns: {list(projects[0].keys())[:5]}...")
        
        return projects
        
    except Exception as e:
        logger.error(f"❌ Error reading from Access table '{table_name}': {e}")
        logger.error(f"💡 Make sure the table '{table_name}' exists in the database")
        raise


def convert_coordinate(coord_str: Optional[str], is_longitude: bool = False) -> Optional[float]:
    """Convert coordinate string to numeric value"""
    if not coord_str:
        return None
    
    try:
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
        logger.warning(f"⚠️  Could not convert coordinate: {coord_str}")
        return None


def map_fields(access_project: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Map Access fields to Supabase fields with data type conversions"""
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
    
    # Ensure project_number is set (REQUIRED for matching - stable identifier)
    # project_number is the primary key for matching projects and won't change
    if "project_number" not in supabase_project or not supabase_project["project_number"]:
        # project_number is critical - if missing, we can't match projects
        record_id = str(access_project.get("ID", "Unknown")).strip()
        logger.warning(f"⚠️  No project_number found for record ID {record_id} - skipping")
        logger.debug(f"   Available fields: {list(access_project.keys())[:10]}...")
        return None  # Skip this record - project_number is required for matching
    
    # Ensure project_name is set (REQUIRED field for Supabase and the app)
    if "project_name" not in supabase_project or not supabase_project["project_name"]:
        # Try Folder_Description first (calculated field)
        if "Folder_Description" in access_project and access_project["Folder_Description"]:
            folder_desc = str(access_project["Folder_Description"]).strip()
            if folder_desc:
                supabase_project["project_name"] = folder_desc
        
        # Fallback: construct from project_number and Address if Folder_Description is empty
        if "project_name" not in supabase_project or not supabase_project["project_name"]:
            # Use project_number (Job_Number) as base - it's already validated above
            project_number = supabase_project.get("project_number", "")
            if "Address" in access_project and access_project["Address"]:
                address = str(access_project["Address"]).strip()
                if address:
                    supabase_project["project_name"] = f"{project_number} - {address}"
                else:
                    supabase_project["project_name"] = project_number
            else:
                supabase_project["project_name"] = project_number
    
    # Ensure is_active is set (default to True if not mapped)
    if "is_active" not in supabase_project:
        supabase_project["is_active"] = True
    
    return supabase_project


def sync_to_supabase(projects: List[Dict[str, Any]], mode: str = "upsert") -> Tuple[int, int, int]:
    """
    Sync projects to Supabase
    
    Args:
        projects: List of project dictionaries
        mode: "upsert" (update existing, insert new) or "replace" (delete all and insert)
    
    Returns:
        Tuple of (updated_count, inserted_count, error_count)
    """
    try:
        supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
        
        if mode == "replace":
            logger.warning("⚠️  Deleting all existing projects...")
            supabase.table("projects").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
            logger.info("✅ Deleted existing projects")
        
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
            logger.warning(f"⚠️  Skipped {skipped} projects (missing required fields)")
        
        if not mapped_projects:
            logger.warning("⚠️  No valid projects to sync")
            return (0, 0, 0)
        
        # Process projects in batches
        batch_size = 100
        total = len(mapped_projects)
        updated_count = 0
        inserted_count = 0
        error_count = 0
        
        for i in range(0, total, batch_size):
            batch = mapped_projects[i:i + batch_size]
            
            if mode == "upsert":
                # Upsert: Update if exists (based on project_number), insert if new
                # project_number is used as the primary reference since it's stable and won't change
                for project in batch:
                    project_number = project.get("project_number", "")
                    project_name = project.get("project_name", "")
                    
                    # Skip if project_number is missing (required for matching)
                    if not project_number:
                        logger.warning(f"⚠️  Skipping project '{project_name}' - missing project_number")
                        error_count += 1
                        continue
                    
                    try:
                        # Try to find existing project by project_number (stable identifier)
                        existing = supabase.table("projects").select("id").eq("project_number", project_number).execute()
                        
                        if existing.data and len(existing.data) > 0:
                            # Update existing project (project_number matched)
                            # This will update project_name if it changed (e.g., typo correction)
                            project_id = existing.data[0]["id"]
                            # Update all fields including project_name (since it can change)
                            update_data = {k: v for k, v in project.items() if k != "project_number"}  # Don't update project_number itself
                            supabase.table("projects").update(update_data).eq("id", project_id).execute()
                            updated_count += 1
                            if (updated_count + inserted_count) % 50 == 0:
                                logger.info(f"  Processed {updated_count + inserted_count}/{total}...")
                        else:
                            # Insert new project (project_number doesn't exist yet)
                            supabase.table("projects").insert(project).execute()
                            inserted_count += 1
                            if (updated_count + inserted_count) % 50 == 0:
                                logger.info(f"  Processed {updated_count + inserted_count}/{total}...")
                    except Exception as e:
                        error_count += 1
                        logger.error(f"  ❌ Error processing project_number '{project_number}' (name: '{project_name}'): {e}")
            else:
                # Insert all (for replace mode)
                try:
                    supabase.table("projects").insert(batch).execute()
                    inserted_count += len(batch)
                except Exception as e:
                    error_count += len(batch)
                    logger.error(f"  ❌ Error inserting batch: {e}")
            
            logger.info(f"✅ Processed batch {i//batch_size + 1}/{(total + batch_size - 1)//batch_size}")
        
        logger.info(f"✅ Successfully synced {total} projects to Supabase")
        if mode == "upsert":
            logger.info(f"   - Updated: {updated_count}")
            logger.info(f"   - Inserted: {inserted_count}")
        if error_count > 0:
            logger.warning(f"   - Errors: {error_count}")
        
        return (updated_count, inserted_count, error_count)
        
    except Exception as e:
        logger.error(f"❌ Error syncing to Supabase: {e}")
        import traceback
        logger.debug("Full traceback:", exc_info=True)
        raise


def main(project_number: Optional[str] = None) -> int:
    """
    Main sync function
    
    Args:
        project_number: Optional project number to sync. If None, syncs all active projects.
    
    Returns:
        Exit code: 0 for success, 1 for failure
    """
    start_time = datetime.now()
    
    try:
        logger.info("=" * 70)
        if project_number:
            logger.info(f"🔄 Starting single project sync: {project_number}")
        else:
            logger.info("🔄 Starting full project sync from Access to Supabase...")
        logger.info("=" * 70)
        logger.info(f"📁 Access DB: {ACCESS_DB_PATH}")
        logger.info(f"🌐 Supabase: {SUPABASE_URL}")
        logger.info(f"📝 Log file: {LOG_FILE}")
        
        # Get current year table name
        table_name = get_current_year_table_name()
        logger.info(f"📅 Using table: {table_name}")
        
        # Read from Access
        try:
            projects = read_access_projects(table_name, project_number)
        except Exception as e:
            logger.error("=" * 70)
            logger.error("❌ ERROR: Failed to read from Access database")
            logger.error("=" * 70)
            logger.error(f"Error details: {e}")
            import traceback
            logger.debug("Full traceback:", exc_info=True)
            logger.error("💡 Troubleshooting:")
            logger.error(f"   1. Check that the Access database file exists at: {ACCESS_DB_PATH}")
            logger.error(f"   2. Ensure the table for the current year exists (e.g., '2026')")
            logger.error("   3. Verify Microsoft Access Database Engine is installed")
            logger.error("      Download: https://www.microsoft.com/en-us/download/details.aspx?id=54920")
            logger.error("   4. Check that the database is not locked (close Access if open)")
            logger.error("   5. Verify you have read permissions for the database file")
            return 1  # Exit with error code
        
        if not projects:
            if project_number:
                logger.error(f"❌ Project '{project_number}' not found in Access database")
                logger.error("   (Check that Enabled = True and Job_Number matches exactly)")
                return 1  # Error - project not found
            else:
                logger.warning("⚠️  No active projects found in Access database")
                logger.warning("   (Only projects with Enabled = True are synced)")
                return 0  # Not an error - just no data to sync
        
        # Sync to Supabase
        try:
            updated, inserted, errors = sync_to_supabase(projects, mode="upsert")
            
            # Calculate duration
            duration = datetime.now() - start_time
            duration_str = str(duration).split('.')[0]  # Remove microseconds
            
            # Final summary
            logger.info("")
            logger.info("=" * 70)
            logger.info("✅ SYNC COMPLETED SUCCESSFULLY")
            logger.info("=" * 70)
            logger.info(f"📊 Summary:")
            if project_number:
                logger.info(f"   - Project number: {project_number}")
            logger.info(f"   - Total projects read from Access: {len(projects)}")
            logger.info(f"   - Updated in Supabase: {updated}")
            logger.info(f"   - Inserted in Supabase: {inserted}")
            logger.info(f"   - Errors: {errors}")
            logger.info(f"⏱️  Duration: {duration_str}")
            logger.info(f"📝 Log saved to: {LOG_FILE}")
            logger.info("=" * 70)
            
            # Return error code if there were errors
            return 0 if errors == 0 else 1
            
        except Exception as e:
            logger.error("=" * 70)
            logger.error("❌ ERROR: Failed to sync to Supabase")
            logger.error("=" * 70)
            logger.error(f"Error details: {e}")
            import traceback
            logger.debug("Full traceback:", exc_info=True)
            logger.error("💡 Troubleshooting:")
            logger.error("   1. ⚠️  MOST COMMON ISSUE: Using anon key instead of service_role key")
            logger.error("      → The service_role key is REQUIRED for bulk syncs (bypasses RLS)")
            logger.error("      → Find it in: Supabase Dashboard → Settings → API → service_role key (secret)")
            logger.error("   2. Verify SUPABASE_URL and SUPABASE_KEY are correct")
            logger.error("   3. Check that the 'projects' table exists in Supabase")
            logger.error("   4. Verify RLS policies allow inserts/updates (or use service_role key)")
            logger.error("   5. Check Supabase dashboard for error logs")
            logger.error("   6. Verify your internet connection")
            return 1  # Exit with error code
        
    except Exception as e:
        logger.error("=" * 70)
        logger.error("❌ UNEXPECTED ERROR")
        logger.error("=" * 70)
        logger.error(f"Error: {e}")
        import traceback
        logger.debug("Full traceback:", exc_info=True)
        return 1  # Exit with error code


if __name__ == "__main__":
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description="Sync projects from Microsoft Access to Supabase",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Full sync (all active projects)
  python sync_projects_production.py
  
  # Update single project
  python sync_projects_production.py --project A6-0001
  python sync_projects_production.py -p B6-0174
        """
    )
    parser.add_argument(
        "-p", "--project",
        dest="project_number",
        help="Project number (Job_Number) to sync. If not specified, syncs all active projects.",
        metavar="PROJECT_NUMBER"
    )
    
    args = parser.parse_args()
    exit_code = main(project_number=args.project_number)
    sys.exit(exit_code)
