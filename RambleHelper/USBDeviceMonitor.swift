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
        
        let volumeName = diskDescription["DAVolumeName"] as? String ?? ""
        let devicePath = diskDescription["DADevicePath"] as? String ?? ""
        let bsdName = diskDescription["DAMediaBSDName"] as? String ?? ""
        let volumeMountable = diskDescription["DAVolumeMountable"] as? Bool ?? false
        
        print("Disk appeared: \(volumeName) (BSD: \(bsdName), Mountable: \(volumeMountable))")
        
        // Only process mountable volumes that match our target devices
        guard volumeMountable && isTargetDevice(volumeName: volumeName, devicePath: devicePath) else {
            return
        }
        
        print("Target device detected: \(volumeName), waiting for mount...")
        
        // Wait a moment and then try to find the mount point
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.findAndProcessMountedDevice(bsdName: bsdName, volumeName: volumeName)
        }
    }
    
    private func findAndProcessMountedDevice(bsdName: String, volumeName: String) {
        // Try to find the mount point using the BSD name
        let volumesURL = URL(fileURLWithPath: "/Volumes")
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: [.volumeNameKey], options: [])
            
            for volumeURL in contents {
                // Check if this volume matches our device
                if let resourceValues = try? volumeURL.resourceValues(forKeys: [.volumeNameKey]),
                   let mountedVolumeName = resourceValues.volumeName,
                   mountedVolumeName == volumeName {
                    
                    print("Found mounted device at: \(volumeURL.path)")
                    self.notificationManager.showDeviceDetected()
                    self.processDevice(at: volumeURL, volumeName: volumeName)
                    return
                }
            }
            
            print("Could not find mount point for device: \(volumeName)")
        } catch {
            print("Error finding mounted volumes: \(error)")
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
                // First, check how many WAV files we have
                let wavFiles = try findWAVFiles(in: mountURL)
                
                if wavFiles.isEmpty {
                    print("No WAV files found on device")
                    DispatchQueue.main.async {
                        self.ejectDevice(at: mountURL)
                    }
                    return
                }
                
                // Show transfer started notification
                DispatchQueue.main.async {
                    self.notificationManager.showTransferStarted(fileCount: wavFiles.count)
                }
                
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
    
    private func findWAVFiles(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                print("Error accessing \(url): \(error)")
                return true
            }
        ) else {
            return []
        }
        
        var wavFiles: [URL] = []
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                
                if resourceValues.isRegularFile == true &&
                   fileURL.pathExtension.lowercased() == "wav" {
                    wavFiles.append(fileURL)
                }
            } catch {
                print("Error reading file attributes for \(fileURL): \(error)")
            }
        }
        
        return wavFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
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