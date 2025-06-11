//
//  AppDelegate.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/10/25.
//

import Cocoa
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var menuBarController: MenuBarController?
    private var usbDeviceMonitor: USBDeviceMonitor?
    private var fileTransferManager: FileTransferManager?
    private var configurationManager: ConfigurationManager?
    private var notificationManager: NotificationManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupManagers()
        requestNotificationPermissions()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuBarController = MenuBarController(statusItem: statusItem!)
    }
    
    private func setupManagers() {
        configurationManager = ConfigurationManager()
        notificationManager = NotificationManager()
        fileTransferManager = FileTransferManager(
            configurationManager: configurationManager!,
            notificationManager: notificationManager!
        )
        usbDeviceMonitor = USBDeviceMonitor(
            fileTransferManager: fileTransferManager!,
            notificationManager: notificationManager!,
            configurationManager: configurationManager!
        )
        
        menuBarController?.configure(
            configurationManager: configurationManager!,
            usbDeviceMonitor: usbDeviceMonitor!,
            fileTransferManager: fileTransferManager!
        )
        
        usbDeviceMonitor?.startMonitoring()
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        usbDeviceMonitor?.stopMonitoring()
    }
}