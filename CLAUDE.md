# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RambleHelper is a macOS application designed to automatically transfer WAV files from connected voice recorders (like DJI Mic) to a configured destination folder. The project is built using Swift and SwiftUI, targeting macOS 15.5+.

## Architecture

This is a standard Xcode project with the following structure:
- **Main App**: `RambleHelper/` - Contains the main application code using SwiftUI
- **Tests**: `RambleHelperTests/` - Unit tests using the Swift Testing framework
- **UI Tests**: `RambleHelperUITests/` - UI automation tests

The application is designed as a background utility that:
1. Monitors for USB mass storage devices using IOKit
2. Transfers WAV files from connected devices to a destination folder  
3. Provides menu bar integration for status and configuration
4. Uses system notifications to communicate with users

Key frameworks that will be used:
- IOKit for USB device detection
- NSStatusItem for menu bar integration
- UserNotifications for system notifications
- FileManager for file operations
- NSWorkspace for device ejection

## Development Commands

### Building
```bash
# Build the project
xcodebuild -project RambleHelper.xcodeproj -scheme RambleHelper -configuration Debug build

# Build for release
xcodebuild -project RambleHelper.xcodeproj -scheme RambleHelper -configuration Release build
```

### Testing
```bash
# Run unit tests
xcodebuild test -project RambleHelper.xcodeproj -scheme RambleHelper -destination 'platform=macOS'

# Run UI tests
xcodebuild test -project RambleHelper.xcodeproj -scheme RambleHelper -destination 'platform=macOS' -only-testing:RambleHelperUITests
```

### Running
The app can be run directly from Xcode or built and launched from the command line. As a menu bar app, it will appear in the system menu bar when running.

## Key Configuration

- **Bundle Identifier**: `com.Baywood-Labs.RambleHelper`
- **Development Team**: R9LUBQAD88
- **Deployment Target**: macOS 15.5
- **Swift Version**: 5.0
- **SandBoxed**: Yes (with file access entitlements)

## Required Entitlements

The app uses sandboxing with these entitlements:
- `com.apple.security.app-sandbox` - Required for App Store distribution
- `com.apple.security.files.user-selected.read-only` - For accessing user-selected files/folders

Additional entitlements will likely be needed for:
- USB device access
- Full disk access for file operations
- Login items for auto-start capability