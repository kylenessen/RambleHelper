# Voice Memo to Tokens: Automated Ingest Utility
## Technical Specification Document

**Version:** 1.0  
**Date:** June 9, 2025  
**Platform:** macOS  

---

## 1. Project Overview

A lightweight macOS background application that automatically transfers WAV files from connected voice recorders (e.g., DJI Mic) to a user-configured destination folder, then safely ejects the device.

## 2. Core Functionality

### 2.1 Device Detection
- Monitor for USB mass storage devices using IOKit
- Identify target devices by hardware identifier or volume name
- Support one device at a time (queue multiple if needed)

### 2.2 File Transfer Process
1. **Detection**: Identify connected voice recorder
2. **Copy**: Transfer all WAV files from device to destination folder
3. **Duplicate Resolution**: Append numbers to filenames if duplicates exist (e.g., `recording.wav`, `recording_1.wav`)
4. **Cleanup**: Delete original files from device after successful transfer
5. **Eject**: Safely unmount and eject the device

### 2.3 Error Handling
- **Interrupted Transfers**: Delete partial files, retry operation, or alert user to manual intervention
- **Device Busy**: Wait with timeout, then error notification
- **Transfer Failures**: System notification with error details
- **No Destination**: Prompt user to configure destination folder

## 3. User Interface & Experience

### 3.1 Menu Bar Presence
- **Idle State**: Subtle icon indicating app is running and waiting
- **Working State**: Visual indication during file transfer (e.g., animated icon)
- **Error State**: Warning icon for errors requiring attention

### 3.2 Menu Bar Options
- Current status display
- Open destination folder
- Configure destination folder
- View logs
- Quit application

### 3.3 System Notifications
- **Start**: "Voice recorder detected. Transferring files..."
- **Success**: "X files transferred successfully. Device ejected."
- **Error**: "Transfer failed: [specific error message]"
- **Configuration**: "Please set destination folder" (first run)

## 4. Technical Architecture

### 4.1 Language & Frameworks
- **Primary Language**: Swift
- **Key Frameworks**:
  - IOKit (USB device detection)
  - NSStatusItem (menu bar integration)
  - UserNotifications (system notifications)
  - FileManager (file operations)
  - NSWorkspace (device ejection)

### 4.2 Application Structure
```
VoiceMemoIngest/
├── App/
│   ├── AppDelegate.swift
│   ├── MenuBarController.swift
│   └── NotificationManager.swift
├── Core/
│   ├── USBDeviceMonitor.swift
│   ├── FileTransferManager.swift
│   └── ConfigurationManager.swift
├── Models/
│   ├── Device.swift
│   └── TransferJob.swift
└── Resources/
    ├── Info.plist
    └── Assets.xcassets
```

### 4.3 Performance Targets
- **Memory Usage**: < 50MB when idle
- **CPU Usage**: < 1% when idle, reasonable during transfers
- **Startup Time**: < 2 seconds to menu bar ready
- **Transfer Speed**: Limited only by USB/storage hardware

## 5. Configuration & Settings

### 5.1 User Preferences
- **Destination Folder**: User-selectable path (default: `~/Dropbox/Inbox`)
- **Auto-Launch**: Enable/disable startup at login (default: enabled)
- **Device Identification**: Configurable device name or hardware ID

### 5.2 Storage Locations
- **Preferences**: `~/Library/Preferences/com.yourname.voicememoingest.plist`
- **Logs**: `~/Library/Logs/VoiceMemoIngest/`

## 6. File Operations Specification

### 6.1 Supported Files
- **Primary**: WAV files only
- **Transfer Method**: Copy then delete (not move, for safety)
- **Naming**: Preserve original filenames

### 6.2 Duplicate Resolution Algorithm
```
Original: recording.wav
If exists: recording_1.wav
If exists: recording_2.wav
Continue until unique filename found
```

### 6.3 Transfer Verification
- Compare file sizes after copy
- Verify file accessibility before deletion
- Maintain transfer log for debugging

## 7. Security & Permissions

### 7.1 Required Permissions
- **Full Disk Access**: For reading/writing files
- **USB Device Access**: For device detection and ejection
- **Notifications**: For user alerts
- **Login Items**: For auto-start capability

### 7.2 Code Signing
- Developer ID signed for distribution outside Mac App Store
- Notarized for Gatekeeper compatibility

## 8. Error Scenarios & Handling

| Scenario | Behavior | User Notification |
|----------|----------|-------------------|
| Device disconnected during transfer | Delete partial files, log error | "Transfer interrupted. Please reconnect device." |
| Insufficient disk space | Abort transfer | "Insufficient disk space for transfer." |
| No destination folder set | Prompt for configuration | "Please configure destination folder." |
| Device busy/locked | Wait 30s, then error | "Device is busy. Please try again." |
| File permission errors | Skip file, continue | "Some files could not be transferred. Check permissions." |

## 9. Logging & Debugging

### 9.1 Log Categories
- **Device Events**: Connection, disconnection, identification
- **Transfer Operations**: Start, progress, completion, errors
- **Configuration Changes**: User preference updates
- **System Events**: App launch, shutdown, errors

### 9.2 Log Access
- Menu bar → "View Logs" opens log directory in Finder
- Logs rotated daily, keep 30 days
- Structured format for easy parsing by LLMs

## 10. Development Phases

### Phase 1: Core Functionality
- USB device detection
- Basic file transfer
- Menu bar presence
- System notifications

### Phase 2: Polish & Configuration
- User preferences
- Error handling refinement
- Auto-launch setup
- Code signing

### Phase 3: Testing & Distribution
- Edge case testing
- Performance optimization
- Distribution preparation

## 11. Success Criteria

- **Reliability**: 99%+ successful transfers under normal conditions
- **Transparency**: Clear user feedback for all operations
- **Performance**: Negligible impact on system resources when idle
- **Usability**: Zero-configuration operation after initial setup