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
                case .processing:
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
            iconName = "waveform.circle.fill"
        case .working:
            iconName = "waveform.circle.fill"
        case .error:
            iconName = "exclamationmark.triangle"
        }
        
        let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        image?.size = NSSize(width: 22, height: 22)
        statusItem.button?.image = image
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
        
        menu.addItem(NSMenuItem(
            title: "Audio Processing Settings",
            action: #selector(configureAudioProcessing),
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
        guard let configManager = configurationManager else {
            return "Starting..."
        }
        
        switch currentState {
        case .idle:
            let processingStatus = configManager.isAudioProcessingEnabled ? " (Processing enabled)" : ""
            return "Waiting for voice recorder...\(processingStatus)"
        case .working:
            return "Processing files..."
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
    
    @objc private func configureAudioProcessing() {
        guard let configManager = configurationManager else { return }
        
        let alert = NSAlert()
        alert.messageText = "Audio Processing Settings"
        alert.informativeText = "Configure automatic audio processing options"
        alert.alertStyle = .informational
        
        // Create accessory view with checkboxes and controls
        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = 10
        view.alignment = .leading
        
        // Audio merging checkbox
        let mergingCheckbox = NSButton()
        mergingCheckbox.setButtonType(.switch)
        mergingCheckbox.title = "Enable automatic file merging (DJI Mic 30min+ recordings)"
        mergingCheckbox.state = configManager.enableAudioMerging ? .on : .off
        view.addArrangedSubview(mergingCheckbox)
        
        // Small file deletion checkbox
        let smallFileCheckbox = NSButton()
        smallFileCheckbox.setButtonType(.switch)
        smallFileCheckbox.title = "Automatically delete small files"
        smallFileCheckbox.state = configManager.enableSmallFileDeletion ? .on : .off
        view.addArrangedSubview(smallFileCheckbox)
        
        // Small file threshold
        let thresholdContainer = NSStackView()
        thresholdContainer.orientation = .horizontal
        thresholdContainer.spacing = 5
        
        let thresholdLabel = NSTextField(labelWithString: "Size threshold (MB):")
        let thresholdField = NSTextField()
        thresholdField.stringValue = "\(configManager.getSmallFileThresholdMB())"
        thresholdField.preferredMaxLayoutWidth = 50
        
        thresholdContainer.addArrangedSubview(thresholdLabel)
        thresholdContainer.addArrangedSubview(thresholdField)
        view.addArrangedSubview(thresholdContainer)
        
        // Output format selection
        let formatContainer = NSStackView()
        formatContainer.orientation = .horizontal
        formatContainer.spacing = 5
        
        let formatLabel = NSTextField(labelWithString: "Output format:")
        let formatPopup = NSPopUpButton()
        formatPopup.addItems(withTitles: ["M4A (compressed)", "WAV (uncompressed)"])
        formatPopup.selectItem(at: configManager.outputFormat == "m4a" ? 0 : 1)
        
        formatContainer.addArrangedSubview(formatLabel)
        formatContainer.addArrangedSubview(formatPopup)
        view.addArrangedSubview(formatContainer)
        
        alert.accessoryView = view
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset to Defaults")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn: // Save
            configManager.enableAudioMerging = mergingCheckbox.state == .on
            configManager.enableSmallFileDeletion = smallFileCheckbox.state == .on
            
            if let threshold = Int(thresholdField.stringValue), threshold > 0 {
                configManager.setSmallFileThresholdMB(threshold)
            }
            
            configManager.outputFormat = formatPopup.indexOfSelectedItem == 0 ? "m4a" : "wav"
            
        case .alertThirdButtonReturn: // Reset to Defaults
            configManager.resetAudioProcessingSettings()
            
        default: // Cancel
            break
        }
        
        updateMenu()
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