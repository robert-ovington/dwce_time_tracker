@echo off
REM ============================================================================
REM Build Script for DWCE Time Tracker - iOS
REM ============================================================================
REM
REM Builds the Flutter iOS app (release).
REM
REM IMPORTANT: iOS builds require macOS and Xcode.
REM - On Windows: This script will fail; use a Mac or a macOS CI runner instead.
REM - On macOS: Run this script (or the same commands in Terminal) to build.
REM
REM Usage:
REM   build_ios.bat              - Build iOS release (macOS only)
REM
REM Output: build/ios/ (Xcode project and built app)
REM ============================================================================

cd /d "%~dp0"

echo.
echo ========================================
echo DWCE Time Tracker - iOS Build Script
echo ========================================
echo.

REM Check if Flutter is installed
where flutter >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Flutter is not installed or not in PATH
    echo Please install Flutter from https://flutter.dev
    pause
    exit /b 1
)

echo NOTE: iOS builds require macOS and Xcode.
echo If you are on Windows, this build will not succeed.
echo.
echo Cleaning previous build...
call flutter clean
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Flutter clean failed
    pause
    exit /b 1
)

echo.
echo Getting dependencies...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Flutter pub get failed
    pause
    exit /b 1
)

echo.
echo Building iOS app (release)...
call flutter build ios --release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: iOS build failed
    echo Remember: iOS builds require macOS and Xcode.
    pause
    exit /b 1
)

echo.
echo ========================================
echo iOS build completed successfully!
echo ========================================
echo.
echo Output: build\ios\
echo.
echo Next steps on macOS:
echo   1. Open ios/Runner.xcworkspace in Xcode
echo   2. Select signing team and device/simulator
echo   3. Archive and distribute via Xcode or App Store Connect
echo.
pause
