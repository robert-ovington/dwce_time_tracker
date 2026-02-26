# How to Run the Project Sync Script

## Step-by-Step Instructions

### Step 1: Install Prerequisites

#### 1.1 Install Python (if not already installed)
1. Download Python from: https://www.python.org/downloads/
2. During installation, check "Add Python to PATH"
3. Verify installation by opening Command Prompt and typing:
   ```bash
   python --version
   ```
   You should see something like `Python 3.11.x`

#### 1.2 Install Microsoft Access Database Engine
1. Download from: https://www.microsoft.com/en-us/download/details.aspx?id=54920
2. **Important**: Choose the correct version:
   - If you have 64-bit Python → Install 64-bit Access Engine
   - If you have 32-bit Python → Install 32-bit Access Engine
3. To check your Python version:
   ```bash
   python -c "import platform; print(platform.architecture()[0])"
   ```

#### 1.3 Install Python Dependencies
Open Command Prompt or PowerShell and run:
```bash
pip install pyodbc supabase pandas
```

If you get permission errors, try:
```bash
pip install --user pyodbc supabase pandas
```

### Step 2: Configure the Script

1. **Open the script file**: `sync_projects_access_to_supabase.py`

2. **Find these lines near the top** (around lines 25-26):
   ```python
   SUPABASE_URL = "your-supabase-url"
   SUPABASE_KEY = "your-supabase-anon-key"
   ```

3. **Replace with your actual Supabase credentials**:
   ```python
   SUPABASE_URL = "https://your-project-id.supabase.co"
   SUPABASE_KEY = "your-service-role-key-here"  # MUST use service_role key, not anon key
   ```

   **Where to find these:**
   - Go to your Supabase Dashboard: https://app.supabase.com
   - Select your project
   - Go to **Settings** → **API**
   - Copy the **Project URL** → This is your `SUPABASE_URL`
   - **IMPORTANT**: Copy the **service_role** key (secret) → This is your `SUPABASE_KEY`
     - ⚠️ **DO NOT use the anon key** - it will fail with RLS policy errors
     - The service_role key bypasses RLS policies and is required for bulk syncs
     - Keep this key secret - never commit it to public repositories

4. **Verify the database path** (should already be set):
   ```python
   ACCESS_DB_PATH = r"W:\Master Files\Master Job List.accdb"
   ```

### Step 3: Run the Script

#### Option A: Using Command Prompt (Windows)

1. **Open Command Prompt**:
   - Press `Win + R`
   - Type `cmd` and press Enter

2. **Navigate to the script directory**:
   ```bash
   cd C:\Users\robie\dwce_time_tracker
   ```
   (Or wherever you saved the script)

3. **Run the script**:
   ```bash
   python sync_projects_access_to_supabase.py
   ```

#### Option B: Using PowerShell (Windows)

1. **Open PowerShell**:
   - Press `Win + X`
   - Select "Windows PowerShell" or "Terminal"

2. **Navigate to the script directory**:
   ```powershell
   cd C:\Users\robie\dwce_time_tracker
   ```

3. **Run the script**:
   ```powershell
   python sync_projects_access_to_supabase.py
   ```

#### Option C: Double-Click (if Python is associated with .py files)

1. Navigate to the script file in Windows Explorer
2. Double-click `sync_projects_access_to_supabase.py`
3. A window will open showing the output

### Step 4: Check the Output

You should see output like:
```
======================================================================
🔄 Starting project sync from Access to Supabase...
======================================================================
📁 Access DB: W:\Master Files\Master Job List.accdb
🌐 Supabase: https://your-project.supabase.co
📅 Using table: 2026

📊 Reading from table: 2026
✅ Read 490 active projects from Access table '2026'
  Processed 10/490...
  Processed 20/490...
✅ Processed batch 1/5
✅ Processed batch 2/5
...
✅ Successfully synced 490 projects to Supabase
   - Updated: 450
   - Inserted: 40

======================================================================
✅ Sync completed successfully!
======================================================================
```

## Troubleshooting

### Error: "python is not recognized"
**Solution**: Python is not in your PATH
- Reinstall Python and check "Add Python to PATH"
- Or use the full path: `C:\Python311\python.exe sync_projects_access_to_supabase.py`

### Error: "Microsoft Access Driver not found"
**Solution**: 
- Install Microsoft Access Database Engine (see Step 1.2)
- Make sure you install the correct bit version (32-bit vs 64-bit)

### Error: "No module named 'pyodbc'" or "No module named 'supabase'"
**Solution**: Install dependencies
```bash
pip install pyodbc supabase pandas
```

### Error: "Could not open database" or "Database is locked"
**Solution**:
- Close Microsoft Access if it's open
- Make sure no one else has the database open
- Check that the file path is correct and accessible

### Error: "Table '2026' not found"
**Solution**:
- Verify the table exists in Access
- Check the table name matches the current year
- The script automatically uses the current year (2026, 2027, etc.)

### Error: "Supabase authentication error"
**Solution**:
- Verify `SUPABASE_URL` and `SUPABASE_KEY` are correct
- Check for extra spaces or quotes
- Try using the service_role key instead of anon key

### Error: "RLS policy violation"
**Solution**:
- Use the service_role key instead of anon key
- Or update RLS policies in Supabase to allow inserts/updates

## Running on a Schedule (Automation)

### Windows Task Scheduler

1. **Open Task Scheduler**:
   - Press `Win + R`
   - Type `taskschd.msc` and press Enter

2. **Create Basic Task**:
   - Click "Create Basic Task" in the right panel
   - Name: "Sync Projects from Access"
   - Description: "Daily sync of projects from Access to Supabase"

3. **Set Trigger**:
   - Choose "Daily" (or your preferred frequency)
   - Set time (e.g., 2:00 AM)

4. **Set Action**:
   - Action: "Start a program"
   - Program: `python` (or full path: `C:\Python311\python.exe`)
   - Arguments: `sync_projects_access_to_supabase.py`
   - Start in: `C:\Users\robie\dwce_time_tracker` (your script directory)

5. **Finish**: Click through the remaining steps

The script will now run automatically at the scheduled time!

## Quick Test Run

To test if everything is set up correctly, run:
```bash
python sync_projects_access_to_supabase.py
```

If you see the success message, you're all set! 🎉

## Viewing Error Messages

### Method 1: Run in Command Prompt/PowerShell (Recommended)

**This is the best way to see errors:**

1. Open **Command Prompt** or **PowerShell**
2. Navigate to your script directory:
   ```bash
   cd C:\Users\robie\dwce_time_tracker
   ```
3. Run the script:
   ```bash
   python sync_projects_access_to_supabase.py
   ```
4. **The window will stay open** and show all error details

### Method 2: Use the Batch File

1. **Double-click** `RUN_SYNC.bat`
2. A window will open and stay open even if there are errors
3. You'll see the full error output

### Method 3: Run and Save Output to File

If you want to save the output (including errors) to a file:

```bash
python sync_projects_access_to_supabase.py > sync_output.txt 2>&1
```

Then open `sync_output.txt` to see all output and errors.

### Method 4: If Window Closes Too Fast

If you're double-clicking the `.py` file and the window closes immediately, create a batch file:

1. Create a file called `run_sync.bat` (or use the provided `RUN_SYNC.bat`)
2. Add this content:
   ```batch
   @echo off
   python sync_projects_access_to_supabase.py
   pause
   ```
3. Double-click the `.bat` file instead

## Understanding Error Messages

The script now shows detailed error information:

- **Full error message**: What went wrong
- **Traceback**: Where in the code the error occurred
- **Troubleshooting tips**: Suggestions to fix the issue

### Common Error Patterns

**"No module named 'X'"**
- Solution: Install missing module: `pip install X`

**"Microsoft Access Driver not found"**
- Solution: Install Access Database Engine

**"Table '2026' not found"**
- Solution: Verify table exists, check year is correct

**"Authentication failed" or "Invalid API key"**
- Solution: Check SUPABASE_URL and SUPABASE_KEY are correct

**"Database is locked"**
- Solution: Close Microsoft Access

**"RLS policy violation"**
- Solution: Use service_role key or update RLS policies

## Getting Help

When reporting errors, include:
1. The full error message
2. The traceback (the detailed error output)
3. What step you were on when it failed
4. Your Python version: `python --version`
