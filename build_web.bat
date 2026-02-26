@echo off
REM ============================================================================
REM Build Script for DWCE Time Tracker Web App
REM ============================================================================
REM 
REM This script builds the Flutter web app for production deployment.
REM
REM Usage:
REM   build_web.bat              - Build with default settings (CanvasKit renderer)
REM
REM Note: Flutter 3.10+ automatically selects the best renderer.
REM The --web-renderer flag has been deprecated.
REM ============================================================================

echo.
echo ========================================
echo DWCE Time Tracker - Web Build Script
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

echo Building web app (Flutter will automatically select the best renderer)...
echo.

REM Check if .env file exists
if not exist .env (
    echo WARNING: .env file not found!
    echo Please create .env file with:
    echo   SUPABASE_URL=your_url
    echo   SUPABASE_ANON_KEY=your_key
    echo.
    set /p CONTINUE="Continue anyway? (y/n): "
    if /i not "%CONTINUE%"=="y" exit /b 1
)

REM Clean previous build
echo Cleaning previous build...
call flutter clean
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Flutter clean failed
    pause
    exit /b 1
)

REM Get dependencies
echo.
echo Getting dependencies...
call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Flutter pub get failed
    pause
    exit /b 1
)

REM Build for web
echo.
echo Building web app (this may take a few minutes)...
REM Note: --web-renderer flag has been deprecated in Flutter 3.10+
REM Flutter now automatically selects the best renderer (CanvasKit by default)
call flutter build web --release
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Build failed
    pause
    exit /b 1
)

REM Copy .env file to build/web directory for runtime access
echo.
echo Copying .env file to build output...
if exist .env (
    copy /Y .env build\web\.env >nul
    if %ERRORLEVEL% EQU 0 (
        echo ✅ .env file copied successfully
    ) else (
        echo ⚠️  Warning: Failed to copy .env file
    )
) else (
    echo ⚠️  Warning: .env file not found - app may not work correctly
)

REM Also create config.json from .env (not ignored by Firebase)
echo.
echo Creating config.json from .env file...
if exist .env (
    powershell -Command "(Get-Content .env) | ForEach-Object { if ($_ -match '^SUPABASE_URL=(.+)$') { $url = $matches[1] } if ($_ -match '^SUPABASE_ANON_KEY=(.+)$') { $key = $matches[1] } }; @{ SUPABASE_URL = $url; SUPABASE_ANON_KEY = $key } | ConvertTo-Json | Out-File -FilePath build\web\config.json -Encoding utf8"
    if %ERRORLEVEL% EQU 0 (
        echo ✅ config.json created successfully
    ) else (
        echo ⚠️  Warning: Failed to create config.json
    )
) else (
    echo ⚠️  Warning: .env file not found - cannot create config.json
)

REM Generate build timestamp file
echo.
echo Generating build timestamp...
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set build_date=%datetime:~0,4%-%datetime:~4,2%-%datetime:~6,2% %datetime:~8,2%:%datetime:~10,2%:%datetime:~12,2%
echo Build Date: %build_date% > build\web\build_info.txt
echo Build Timestamp: %datetime% >> build\web\build_info.txt
if %ERRORLEVEL% EQU 0 (
    echo ✅ Build timestamp generated: %build_date%
) else (
    echo ⚠️  Warning: Failed to generate build timestamp
)

REM Cache-bust main.dart.js so browsers load the new build after deploy
echo.
echo Adding cache-bust to index.html...
powershell -Command "(Get-Content build\web\index.html -Raw) -replace 'main\.dart\.js', 'main.dart.js?v=%datetime%' | Set-Content build\web\index.html -NoNewline"
if %ERRORLEVEL% EQU 0 (
    echo ✅ Cache-bust added: main.dart.js?v=%datetime%
) else (
    echo ⚠️  Warning: Failed to add cache-bust to index.html
)

echo.
echo ========================================
echo Build completed successfully!
echo ========================================
echo.
echo Output directory: build\web
echo.
echo Next steps:
echo   1. Test locally: cd build\web ^&^& python -m http.server 8000
echo   2. Deploy to your hosting provider
echo   3. See WEB_SETUP_GUIDE.md for deployment options
echo.
pause
