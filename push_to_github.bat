@echo off
REM Push current project changes to GitHub.
REM Usage: push_to_github.bat [commit message]
REM   If no message is given, uses "Update project".

setlocal
cd /d "%~dp0"

set "msg=%~1"
if "%msg%"=="" set "msg=Update project"

echo Adding changes...
git add .
if errorlevel 1 (
  echo Failed to add. Check git status.
  exit /b 1
)

echo Committing: %msg%
git commit -m "%msg%"
if errorlevel 1 (
  echo Nothing to commit, or commit failed. Try: git status
  exit /b 1
)

echo Pushing to origin...
git push
if errorlevel 1 (
  echo Push failed. Check remote and credentials.
  exit /b 1
)

echo Done. Changes pushed to GitHub.
exit /b 0
