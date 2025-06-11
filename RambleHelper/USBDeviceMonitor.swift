//
//  USBDeviceMonitor.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/10/25.
//

import Foundation
import IOKit
import IOKit.usb
import DiskArbitration
import AppKit

class USBDeviceMonitor {
    private let fileTransferManager: FileTransferManager
    private let notificationManager: NotificationManager
    private let configurationManager: ConfigurationManager
    private var session: DASession?
    private var isMonitoring = false
    
    init(fileTransferManager: FileTransferManager, notificationManager: NotificationManager, configurationManager: ConfigurationManager) {
        self.fileTransferManager = fileTransferManager
        self.notificationManager = notificationManager
        self.configurationManager = configurationManager
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        session = DASessionCreate(kCFAllocatorDefault)
        guard let session = session else {
            print("Failed to create DA session")
            return
        }
        
        DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        
        let callback: DADiskAppearedCallback = { disk, context in
            guard let context = context else { return }
            let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handleDiskAppeared(disk)
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, callback, selfPtr)
        
        isMonitoring = true
        print("USB device monitoring started")
    }
    
    func stopMonitoring() {
        guard isMonitoring, let session = session else { return }
        
        DASessionUnscheduleFromRunLoop(session, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        self.session = nil
        isMonitoring = false
        print("USB device monitoring stopped")
    }
    
    private func handleDiskAppeared(_ disk: DADisk) {
        guard let diskDescription = DADiskCopyDescription(disk) as? [String: Any] else {
            return
        }
        
        let volumeName = diskDescription[kDADiskDescriptionVolumeNameKey as String] as? String ?? ""
        let devicePath = diskDescription[kDADiskDescriptionDevicePathKey as String] as? String ?? ""
        let mountPath = diskDescription[kDADiskDescriptionVolumePathKey as String] as? URL
        
        print("Disk mounted: \(volumeName) at \(mountPath?.path ?? "unknown")")
        
        if isTargetDevice(volumeName: volumeName, devicePath: devicePath) {
            guard let mountURL = mountPath else {
                print("No mount path available for device")
                return
            }
            
            print("Target device detected: \(volumeName)")
            DispatchQueue.main.async {
                self.notificationManager.showDeviceDetected()
                self.processDevice(at: mountURL, volumeName: volumeName)
            }
        }
    }
    
    private func isTargetDevice(volumeName: String, devicePath: String) -> Bool {
        let targetNames = configurationManager.deviceNames
        
        let nameMatch = targetNames.contains { target in
            volumeName.uppercased().contains(target.uppercased())
        }
        
        let pathMatch = targetNames.contains { target in
            devicePath.uppercased().contains(target.uppercased())
        }
        
        return nameMatch || pathMatch
    }
    
    private func processDevice(at mountURL: URL, volumeName: String) {
        Task {
            do {
                let result = try await fileTransferManager.transferFiles(from: mountURL)
                
                DispatchQueue.main.async {
                    self.notificationManager.showTransferSuccess(fileCount: result.transferredCount)
                    self.ejectDevice(at: mountURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.notificationManager.showTransferError(error.localizedDescription)
                }
                print("Transfer failed: \(error)")
            }
        }
    }
    
    private func ejectDevice(at mountURL: URL) {
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: mountURL)
                print("Device ejected successfully")
            } catch {
                print("Failed to eject device: \(error)")
                
                let task = Process()
                task.launchPath = "/usr/bin/diskutil"
                task.arguments = ["eject", mountURL.path]
                task.launch()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    print("Device ejected via diskutil")
                } else {
                    print("Failed to eject via diskutil")
                }
            }
        }
    }
}