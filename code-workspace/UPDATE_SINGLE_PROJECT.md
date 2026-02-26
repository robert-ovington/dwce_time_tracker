# Update Single Project from Access

The sync script now supports updating a specific project instead of running a full sync. This is much faster and more efficient when you only need to update one project.

## Usage

### Full Sync (All Projects)
Update all active projects from Access to Supabase (default behavior):

```bash
python sync_projects_production.py
```

### Update Single Project
Update only a specific project by its project number (Job_Number):

```bash
# Using --project flag
python sync_projects_production.py --project A6-0001

# Using short -p flag
python sync_projects_production.py -p B6-0174

# Examples
python sync_projects_production.py -p Q6-0001
python sync_projects_production.py --project C5-0001-10
```

## How It Works

1. **Finds the project in Access** by matching `Job_Number` to the specified project number
2. **Reads only that one project** from the Access database (much faster)
3. **Updates or inserts** that project in Supabase using `project_number` as the matching key
4. **Logs the result** to the log file

## Benefits

✅ **Much faster** - Only processes one project instead of hundreds  
✅ **Lower database load** - Only queries one record from Access  
✅ **Targeted updates** - Perfect for quick fixes or corrections  
✅ **Same matching logic** - Uses `project_number` to match, prevents duplicates  

## Examples

### Scenario 1: Fix a typo in project name
You corrected a typo in Access for project "A6-0001":

```bash
python sync_projects_production.py -p A6-0001
```

Result: Only project A6-0001 is read from Access and updated in Supabase. All other projects are untouched.

### Scenario 2: Update project details
You changed the address or description for project "B6-0174":

```bash
python sync_projects_production.py -p B6-0174
```

Result: Project B6-0174 is updated with new details from Access.

### Scenario 3: Add new project
You added a new project "A6-9999" in Access and want to sync it:

```bash
python sync_projects_production.py -p A6-9999
```

Result: If the project doesn't exist in Supabase, it's inserted. If it exists, it's updated.

## Error Handling

If the project number is not found in Access:

```
⚠️  Project 'A6-9999' not found in Access table '2026'
   (Make sure Enabled = True and Job_Number matches exactly)
❌ Project 'A6-9999' not found in Access database
   (Check that Enabled = True and Job_Number matches exactly)
```

**Troubleshooting:**
- Make sure the project exists in the Access table for the current year
- Verify `Enabled = True` in Access
- Check that the `Job_Number` matches exactly (case-sensitive)
- Ensure the table name matches the current year (e.g., "2026")

## Integration with Other Systems

### PowerShell Script
Create a PowerShell script to update a project:

```powershell
# update_project.ps1
param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectNumber
)

python sync_projects_production.py -p $ProjectNumber
```

Usage:
```powershell
.\update_project.ps1 -ProjectNumber "A6-0001"
```

### Batch File
Create a batch file `update_single.bat`:

```batch
@echo off
if "%1"=="" (
    echo Usage: update_single.bat PROJECT_NUMBER
    echo Example: update_single.bat A6-0001
    exit /b 1
)
python sync_projects_production.py -p %1
```

Usage:
```bash
update_single.bat A6-0001
```

### Windows Task Scheduler (Scheduled Single Updates)
You could set up multiple scheduled tasks for different projects, but typically you'd:
- Use full sync for scheduled runs (daily/hourly)
- Use single project updates manually when needed

### From Access/VBA
If you want to trigger updates from Access, you could create a VBA macro:

```vba
Sub SyncProjectToSupabase(ProjectNumber As String)
    Dim shell As Object
    Set shell = CreateObject("WScript.Shell")
    Dim scriptPath As String
    scriptPath = "C:\Users\robie\dwce_time_tracker\sync_projects_production.py"
    shell.Run "python " & scriptPath & " -p " & ProjectNumber, 0, False
End Sub

' Usage in Access:
Call SyncProjectToSupabase("A6-0001")
```

## Performance Comparison

**Full Sync:**
- Time: ~35 seconds for 482 projects
- Database queries: 482+ (one per project plus lookups)
- Network requests: ~500+

**Single Project Update:**
- Time: ~1-2 seconds for 1 project
- Database queries: 1 from Access, 1 lookup in Supabase, 1 update/insert
- Network requests: ~3

**Result:** Single project updates are **~20x faster** than full syncs!

## Logging

Single project updates are logged to the same log file:
```
logs/sync_projects_YYYYMMDD.log
```

The log will show:
```
🔄 Starting single project sync: A6-0001
📊 Reading specific project from table: 2026
🔍 Project number: A6-0001
✅ Found project 'A6-0001' in Access table '2026'
✅ Successfully synced 1 projects to Supabase
   - Updated: 1
   - Inserted: 0
📊 Summary:
   - Project number: A6-0001
   - Total projects read from Access: 1
   - Updated in Supabase: 1
   - Inserted in Supabase: 0
   - Errors: 0
```

## Best Practices

1. **Use full sync for scheduled runs** - Ensures all projects stay in sync
2. **Use single project updates for immediate fixes** - When you make a change and need it reflected immediately
3. **Check logs after single updates** - Verify the update was successful
4. **Keep project numbers consistent** - The script matches by `project_number`, so ensure it matches `Job_Number` in Access
