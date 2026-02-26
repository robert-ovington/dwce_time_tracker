# Sync Projects from Access to Supabase

This guide explains how to automatically sync your projects table from Microsoft Access to Supabase.

## Overview

The script automatically:
- Detects the current year's table (e.g., "2026", "2027")
- Reads only active projects (where `Enabled = True`)
- Maps Access fields to Supabase fields
- Converts coordinates (West longitude becomes negative)
- Updates existing projects or inserts new ones

## Prerequisites

1. **Microsoft Access Database Engine**
   - Download and install: https://www.microsoft.com/en-us/download/details.aspx?id=54920
   - Choose the 64-bit version if you have 64-bit Python, or 32-bit if you have 32-bit Python

2. **Python 3.8+**
   - Download from: https://www.python.org/downloads/

## Setup

1. **Install Python dependencies:**
   ```bash
   pip install -r requirements_sync.txt
   ```

2. **Configure the script:**
   - Open `sync_projects_access_to_supabase.py`
   - Update `SUPABASE_URL` with your Supabase project URL
   - Update `SUPABASE_KEY` with your Supabase anon key (or service role key for full access)
   - The `ACCESS_DB_PATH` is already set to `W:\Master Files\Master Job List.accdb`
   - The script automatically uses the current year's table (e.g., "2026")

3. **Run the sync:**
   ```bash
   python sync_projects_access_to_supabase.py
   ```

## Field Mapping

The script includes a comprehensive field mapping based on your Access table structure:

- **Job_Number** → `project_name` (required)
- **Description_of_Work** → `description`
- **Address, Town, County, Eircode** → `job_address`, `job_town`, `job_county`, `job_eircode`
- **Latitude_North, Longitude_West** → `latitude`, `longitude` (with coordinate conversion)
- **Enabled** → `is_active` (boolean conversion)
- **Client_Name, Contract_Code** → `client_name`, `contract_code`
- And many more fields...

The mapping is already configured in the script. If you need to add or modify fields, edit the `FIELD_MAPPING` dictionary in the script.

## Sync Modes

- **Upsert Mode** (default): Updates existing projects (matched by `project_name`) and inserts new ones
- **Replace Mode**: Deletes all existing projects and inserts fresh data (use with caution!)

## Automation

### Windows Task Scheduler

1. Open Task Scheduler
2. Create Basic Task
3. Set trigger (e.g., daily at 2 AM)
4. Action: Start a program
5. Program: `python`
6. Arguments: `C:\path\to\sync_projects_access_to_supabase.py`
7. Start in: `C:\path\to\script\directory`

### PowerShell Script (Alternative)

Create a PowerShell script that runs the Python script:

```powershell
# sync_projects.ps1
cd C:\path\to\script
python sync_projects_access_to_supabase.py
```

Then schedule it with Task Scheduler.

## Troubleshooting

### "Microsoft Access Driver not found"
- Install Microsoft Access Database Engine (see Prerequisites)
- Make sure you install the correct bit version (32-bit vs 64-bit)

### "Connection string error"
- Check that `ACCESS_DB_PATH` is correct
- Ensure the database file is not locked (close Access if open)
- Try using the full absolute path

### "Supabase authentication error"
- Verify your `SUPABASE_URL` and `SUPABASE_KEY` are correct
- Check that your Supabase project has RLS policies that allow inserts/updates
- Consider using service role key instead of anon key for sync operations

## Alternative: Direct CSV Export/Import

If you prefer a simpler, manual approach:

1. **Export from Access:**
   - Right-click projects table → Export → Text File
   - Choose CSV format
   - Save the file

2. **Import to Supabase:**
   - Go to Supabase Dashboard → Table Editor → Projects
   - Click "Import data from CSV"
   - Select your CSV file
   - Map columns if needed
   - Import

This method is manual but requires no code.
