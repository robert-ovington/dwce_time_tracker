@echo off
REM Run this instead of "flutter clean" when you get "Failed to remove build".
REM Stopping the Gradle daemon first usually releases locks on the build folder.

echo Stopping Gradle daemon...
cd /d "%~dp0..\android"
call gradlew.bat --stop 2>nul
cd /d "%~dp0.."
if errorlevel 1 (
  echo (Gradle stop skipped or not found - continuing.)
) else (
  echo Gradle daemon stopped.
)

echo.
echo Running flutter clean...
call flutter clean
echo.
echo Done. If clean still fails, close Cursor/VS Code and any terminals, then run this script again.
pause
