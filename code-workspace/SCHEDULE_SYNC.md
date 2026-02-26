# Scheduling the Project Sync Script

## Production-Ready Script

The `sync_projects_production.py` script is ready for scheduling. It includes:

✅ **File-based logging** - All output saved to `logs/sync_projects_YYYYMMDD.log`  
✅ **Proper exit codes** - Returns 0 for success, 1 for failure (for schedulers)  
✅ **No interactive prompts** - Runs silently for scheduled tasks  
✅ **Environment variable support** - Secure credential management  
✅ **Comprehensive error handling** - Detailed logging for troubleshooting  
✅ **Performance statistics** - Summary of updates, inserts, and errors  

## Setting Up Scheduled Runs

### Option 1: Windows Task Scheduler (Recommended for Windows)

1. **Open Task Scheduler**
   - Press `Win + R`, type `taskschd.msc`, press Enter

2. **Create Basic Task**
   - Click "Create Basic Task" in the right panel
   - Name: "Sync Projects from Access to Supabase"
   - Description: "Daily sync of projects from Access database to Supabase"

3. **Set Trigger**
   - Choose "Daily" (or your preferred frequency)
   - Set time (e.g., 2:00 AM)

4. **Set Action**
   - Action: "Start a program"
   - Program: `python` (or full path: `C:\Python311\python.exe`)
   - Arguments: `sync_projects_production.py`
   - Start in: `C:\Users\robie\dwce_time_tracker` (your script directory)

5. **Configure Settings** (optional but recommended)
   - Check "Run whether user is logged on or not"
   - Check "Run with highest privileges"
   - Uncheck "Stop the task if it runs longer than" (or set a reasonable timeout)

6. **Finish**: Click through the remaining steps

### Option 2: Using Environment Variables (More Secure)

Instead of hardcoding credentials, set them as environment variables:

**Windows (PowerShell):**
```powershell
# Set environment variables (session only)
$env:SUPABASE_URL = "https://ifvbajmmjkkuvhigcgad.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = "your-service-role-key-here"
$env:ACCESS_DB_PATH = "W:\Master Files\Master Job List.accdb"
```

**Windows (Permanent - System Properties):**
1. Right-click "This PC" → Properties
2. Click "Advanced system settings"
3. Click "Environment Variables"
4. Under "System variables", click "New"
5. Add each variable:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY` (keep this secret!)
   - `ACCESS_DB_PATH`

**Windows Task Scheduler with Environment Variables:**
- In Task Scheduler, when creating the task, you can add environment variables in the "General" tab
- Or set them in a batch file wrapper (see below)

### Option 3: Batch File Wrapper

Create a batch file `run_sync.bat`:

```batch
@echo off
REM Set environment variables (optional if already set in system)
set SUPABASE_URL=https://ifvbajmmjkkuvhigcgad.supabase.co
set SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-here
set ACCESS_DB_PATH=W:\Master Files\Master Job List.accdb

REM Change to script directory
cd /d "C:\Users\robie\dwce_time_tracker"

REM Run the script
python sync_projects_production.py

REM Exit with the same code as the Python script
exit /b %ERRORLEVEL%
```

Then in Task Scheduler:
- Program: `C:\Users\robie\dwce_time_tracker\run_sync.bat`
- Arguments: (leave empty)

## Checking Logs

After each scheduled run, check the log file:

```
C:\Users\robie\dwce_time_tracker\logs\sync_projects_YYYYMMDD.log
```

The log file contains:
- Timestamp for each operation
- Success/failure messages
- Error details (if any)
- Summary statistics (updated, inserted, errors)
- Duration of the sync

## Monitoring Scheduled Tasks

### View Task History in Windows Task Scheduler:
1. Open Task Scheduler
2. Find your task
3. Click on "History" tab
4. Look for:
   - Task started events (success)
   - Task completed events (check exit code)
   - Error events (if task failed)

### Check Last Run Status:
- Green checkmark = Success (exit code 0)
- Red X = Failure (exit code 1)

### Verify Sync Results:
1. Check the log file for the run date
2. Look for the summary at the end:
   ```
   ✅ SYNC COMPLETED SUCCESSFULLY
   📊 Summary:
      - Total projects read from Access: 482
      - Updated in Supabase: 450
      - Inserted in Supabase: 32
      - Errors: 0
   ```

## Troubleshooting Scheduled Runs

### Task Not Running:
- Check Task Scheduler history for errors
- Verify Python is in PATH (or use full path)
- Verify script path is correct
- Check "Run whether user is logged on or not" is checked
- Check user account has permissions to run tasks

### Access Denied Errors:
- Ensure the user account running the task has:
  - Read access to the Access database file
  - Write access to the logs directory
  - Network access to Supabase

### Script Runs but Fails:
- Check the log file for detailed error messages
- Verify service_role key is correct (not anon key)
- Verify Access database is not locked (close Access if open)
- Verify network connectivity to Supabase

### Task Runs but No Output:
- Check the logs directory for log files
- Verify the task has write permissions to the logs directory
- Check if Python script is actually executing (add logging to verify)

## Best Practices

1. **Run during off-peak hours** - Schedule for times when the database isn't in heavy use
2. **Monitor first few runs** - Check logs after the first few scheduled runs to ensure everything works
3. **Set up email notifications** - Configure Task Scheduler to email you on task failure
4. **Rotate logs** - Delete old log files periodically (logs are created daily)
5. **Test after database changes** - If the Access table structure changes, test the script manually first
6. **Keep service_role key secure** - Never commit it to version control, use environment variables

## Security Notes

⚠️ **IMPORTANT**: The service_role key has FULL database access

- **Never** commit it to Git or public repositories
- **Always** use environment variables in production
- **Never** use it in client-side code (Flutter app, web app, etc.)
- **Only** use it in secure server-side scripts like this sync script
- **Rotate** the key periodically if it's ever exposed
