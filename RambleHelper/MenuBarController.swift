//
//  MenuBarController.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/10/25.
//

import Cocoa
import SwiftUI

enum AppState {
    case idle
    case working
    case error
}

class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private var configurationManager: ConfigurationManager?
    private var usbDeviceMonitor: USBDeviceMonitor?
    private var fileTransferManager: FileTransferManager?
    private var deviceNamesWindow: NSWindow?
    
    private var currentState: AppState = .idle {
        didSet {
            updateIcon()
        }
    }
    
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
        setupStatusItem()
    }
    
    func configure(
        configurationManager: ConfigurationManager,
        usbDeviceMonitor: USBDeviceMonitor,
        fileTransferManager: FileTransferManager
    ) {
        self.configurationManager = configurationManager
        self.usbDeviceMonitor = usbDeviceMonitor
        self.fileTransferManager = fileTransferManager
        
        fileTransferManager.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .idle:
                    self?.currentState = .idle
                case .transferring:
                    self?.currentState = .working
                case .error:
                    self?.currentState = .error
                }
            }
        }
    }
    
    private func setupStatusItem() {
        updateIcon()
        statusItem.menu = createMenu()
    }
    
    private func updateIcon() {
        let iconName: String
        switch currentState {
        case .idle:
            iconName = "mic.circle"
        case .working:
            iconName = "mic.circle.fill"
        case .error:
            iconName = "exclamationmark.triangle"
        }
        
        statusItem.button?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        
        let statusItem = NSMenuItem(title: getStatusText(), action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(
            title: "Open Destination Folder",
            action: #selector(openDestinationFolder),
            keyEquivalent: ""
        ))
        
        menu.addItem(NSMenuItem(
            title: "Configure Destination Folder",
            action: #selector(configureDestinationFolder),
            keyEquivalent: ""
        ))
        
        menu.addItem(NSMenuItem(
            title: "Configure Device Names",
            action: #selector(configureDeviceNames),
            keyEquivalent: ""
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(
            title: "View Logs",
            action: #selector(viewLogs),
            keyEquivalent: ""
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(
            title: "Quit RambleHelper",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        
        for item in menu.items {
            item.target = self
        }
        
        return menu
    }
    
    private func getStatusText() -> String {
        switch currentState {
        case .idle:
            return "Waiting for voice recorder..."
        case .working:
            return "Transferring files..."
        case .error:
            return "Error - Check logs"
        }
    }
    
    @objc private func openDestinationFolder() {
        guard let configManager = configurationManager,
              let destinationURL = configManager.destinationFolderURL else {
            configureDestinationFolder()
            return
        }
        
        NSWorkspace.shared.open(destinationURL)
    }
    
    @objc private func configureDestinationFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Select Destination Folder"
        
        if openPanel.runModal() == .OK,
           let selectedURL = openPanel.url {
            configurationManager?.setDestinationFolder(url: selectedURL)
        }
    }
    
    @objc private func configureDeviceNames() {
        // Only allow one window at a time
        if deviceNamesWindow != nil {
            deviceNamesWindow?.makeKeyAndOrderFront(nil)
            return
        }
        
        let deviceNamesViewController = DeviceNamesViewController(configurationManager: configurationManager!)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configure Device Names"
        window.contentViewController = deviceNamesViewController
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        
        // Keep strong reference to window
        deviceNamesWindow = window
    }
    
    @objc private func viewLogs() {
        let logsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/RambleHelper")
        
        if let logsURL = logsURL {
            NSWorkspace.shared.open(logsURL)
        }
    }
    
    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func updateMenu() {
        statusItem.menu = createMenu()
    }
}

extension MenuBarController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == deviceNamesWindow {
            deviceNamesWindow = nil
        }
    }
}