#!/bin/sh
# ============================================================================
# Build Script for DWCE Time Tracker - iOS (macOS)
# ============================================================================
#
# Builds the Flutter iOS app (release). Run this on a Mac with Xcode installed.
#
# Usage:
#   chmod +x build_ios.sh
#   ./build_ios.sh
#
# Output: build/ios/
# ============================================================================

set -e
cd "$(dirname "$0")"

echo ""
echo "========================================"
echo "DWCE Time Tracker - iOS Build Script"
echo "========================================"
echo ""

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter is not installed or not in PATH"
  echo "Please install Flutter from https://flutter.dev"
  exit 1
fi

echo "Cleaning previous build..."
flutter clean

echo ""
echo "Getting dependencies..."
flutter pub get

echo ""
echo "Building iOS app (release)..."
flutter build ios --release

echo ""
echo "========================================"
echo "iOS build completed successfully!"
echo "========================================"
echo ""
echo "Output: build/ios/"
echo ""
echo "Next steps:"
echo "  1. Open ios/Runner.xcworkspace in Xcode"
echo "  2. Select signing team and device/simulator"
echo "  3. Archive and distribute via Xcode or App Store Connect"
echo ""
