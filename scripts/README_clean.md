# Fixing "Failed to remove build" (flutter clean)

If `flutter clean` fails with **"Failed to remove build. A program may still be using a file..."**, try these in order.

## 1. Use the clean script (no reboot)

From the project root:

```bash
scripts\clean.bat
```

Or manually:

```bash
android\gradlew.bat -p android --stop
flutter clean
```

Stopping the Gradle daemon first usually releases locks on the `build` folder.

## 2. If it still fails

- **Close Cursor/VS Code** (or at least close this project), then run `scripts\clean.bat` from a **new** Command Prompt or PowerShell.
- **Kill Java/Gradle**: Open Task Manager → end any **"Java(TM) Platform"** or **"Gradle"** processes, then run `flutter clean`.
- **Exclude the project folder** from Windows Defender real-time scanning (Settings → Virus & threat protection → Manage settings → Exclusions). This often fixes recurring locks after Windows/Flutter updates.
- **OneDrive/cloud sync**: If the project is under OneDrive or similar, pause sync or exclude the `build` folder from sync.

## 3. Last resort

Reboot, then run `scripts\clean.bat` or `flutter clean` before opening the IDE.
