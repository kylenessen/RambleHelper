//
//  NotificationManager.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/10/25.
//

import UserNotifications
import Foundation

class NotificationManager: NSObject {
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func showDeviceDetected() {
        sendNotification(
            title: "Voice Recorder Detected",
            body: "Checking for files...",
            identifier: "device-detected"
        )
    }
    
    func showTransferStarted(fileCount: Int) {
        let message = fileCount == 1 ? "Found 1 file. Transfer started..." : "Found \(fileCount) files. Transfer started..."
        sendNotification(
            title: "Transfer Started",
            body: message,
            identifier: "transfer-started"
        )
    }
    
    func showTransferSuccess(fileCount: Int) {
        let message = fileCount == 1 ? "1 file transferred successfully. Device ejected." : "\(fileCount) files transferred successfully. Device ejected."
        sendNotification(
            title: "Transfer Complete",
            body: message,
            identifier: "transfer-success"
        )
    }
    
    func showProcessingStarted(fileCount: Int) {
        let message = fileCount == 1 ? "Processing 1 audio file..." : "Processing \(fileCount) audio files..."
        sendNotification(
            title: "Audio Processing Started",
            body: message,
            identifier: "processing-started"
        )
    }
    
    func showProcessingComplete(result: TransferResult) {
        var messages: [String] = []
        
        if result.processedCount > 0 {
            messages.append("\(result.processedCount) files processed")
        }
        
        if result.mergedCount > 0 {
            messages.append("\(result.mergedCount) files merged")
        }
        
        if result.deletedSmallCount > 0 {
            messages.append("\(result.deletedSmallCount) small files deleted")
        }
        
        let message = messages.isEmpty ? "Processing complete. Device ejected." : "\(messages.joined(separator: ", ")). Device ejected."
        
        sendNotification(
            title: "Processing Complete",
            body: message,
            identifier: "processing-complete"
        )
    }
    
    func showMergeComplete(mergedFiles: Int, totalDuration: TimeInterval) {
        let durationString = String(format: "%.1f", totalDuration / 60.0) // minutes
        let message = "Merged \(mergedFiles) recordings into 1 file (\(durationString) min total)"
        sendNotification(
            title: "Audio Merge Complete",
            body: message,
            identifier: "merge-complete"
        )
    }
    
    func showTransferError(_ message: String) {
        sendNotification(
            title: "Transfer Failed",
            body: message,
            identifier: "transfer-error"
        )
    }
    
    func showConfigurationNeeded() {
        sendNotification(
            title: "Configuration Required",
            body: "Please set destination folder",
            identifier: "config-needed"
        )
    }
    
    func showDeviceDisconnected() {
        sendNotification(
            title: "Transfer Interrupted",
            body: "Device was disconnected during transfer. Please reconnect device.",
            identifier: "device-disconnected"
        )
    }
    
    func showInsufficientSpace() {
        sendNotification(
            title: "Transfer Failed",
            body: "Insufficient disk space for transfer.",
            identifier: "insufficient-space"
        )
    }
    
    func showDeviceBusy() {
        sendNotification(
            title: "Device Busy",
            body: "Device is busy. Please try again.",
            identifier: "device-busy"
        )
    }
    
    private func sendNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}