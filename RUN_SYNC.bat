@echo off
REM Batch file to run the sync script and keep window open on error

echo Starting project sync script...
echo.

REM Run the Python script
python sync_projects_access_to_supabase.py

REM If there was an error, Python script will pause, but this ensures we see any exit codes
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Script exited with error code: %ERRORLEVEL%
    echo.
    pause
)
