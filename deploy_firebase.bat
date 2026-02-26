@echo off
REM ============================================================================
REM Firebase Deployment Script for DWCE Time Tracker
REM ============================================================================
REM 
REM This script builds and deploys the web app to Firebase Hosting.
REM
REM Prerequisites:
REM   1. Firebase CLI installed: npm install -g firebase-tools
REM   2. Firebase project initialized: firebase init hosting
REM   3. Logged in to Firebase: firebase login
REM ============================================================================

echo.
echo ========================================
echo DWCE Time Tracker - Firebase Deployment
echo ========================================
echo.

REM Check if Firebase CLI is installed
where firebase >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Firebase CLI is not installed
    echo Please install it with: npm install -g firebase-tools
    pause
    exit /b 1
)

REM Check if firebase.json exists
if not exist firebase.json (
    echo ERROR: firebase.json not found
    echo Please run: firebase init hosting
    pause
    exit /b 1
)

REM Build the web app first
echo Building web app...
call build_web.bat
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Build failed, deployment cancelled
    pause
    exit /b 1
)

REM Deploy to Firebase
echo.
echo Deploying to Firebase Hosting...
firebase deploy --only hosting
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Deployment failed
    pause
    exit /b 1
)

echo.
echo ========================================
echo Deployment completed successfully!
echo ========================================
echo.
echo Your app should be live at your Firebase Hosting URL
echo.
pause
