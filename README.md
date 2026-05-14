# Mileage Tracker

A simple Flutter mileage tracker for iPhone. It uses live GPS updates while the app is open to measure trip distance, show current speed, and save recent drives locally on the device.

## What it does

- Starts and stops a drive session with one button.
- Tracks mileage in miles using location updates.
- Shows a live speed estimate in mph.
- Saves trip history locally with date, duration, and miles.

## Flutter setup in this workspace

Flutter was installed locally at `C:\Users\Padra\flutter` for this project.

To verify the toolchain from PowerShell:

```powershell
C:\Users\Padra\flutter\bin\flutter.bat --version
```

## Run the app

From the repository root:

```powershell
C:\Users\Padra\flutter\bin\flutter.bat pub get
C:\Users\Padra\flutter\bin\flutter.bat run -d windows
```

## Run on iPhone

You cannot build or launch an iOS app from Windows. Flutter can generate the iOS project here, but the actual iPhone run step requires:

- macOS
- Xcode
- an Apple developer signing setup

On a Mac, open this same repo and run:

```bash
flutter pub get
flutter run -d ios
```

## Notes

- This version tracks mileage while the app stays in the foreground.
- For accurate testing on iPhone, allow location access when prompted.