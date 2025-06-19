//
//  ConfigurationManager.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/10/25.
//

import Foundation
import ServiceManagement

class ConfigurationManager: ObservableObject {
    private let userDefaults = UserDefaults.standard
    
    private struct Keys {
        static let destinationFolderBookmark = "destinationFolderBookmark"
        static let autoLaunch = "autoLaunch"
        static let deviceIdentifier = "deviceIdentifier"
        static let deviceNames = "deviceNames"
        static let enableAudioMerging = "enableAudioMerging"
        static let enableSmallFileDeletion = "enableSmallFileDeletion"
        static let smallFileThreshold = "smallFileThreshold"
        static let outputFormat = "outputFormat"
    }
    
    @Published var destinationFolderURL: URL? {
        didSet {
            saveDestinationFolder()
        }
    }
    
    @Published var autoLaunch: Bool = true {
        didSet {
            userDefaults.set(autoLaunch, forKey: Keys.autoLaunch)
            updateLoginItem()
        }
    }
    
    @Published var deviceIdentifier: String = "DJI" {
        didSet {
            userDefaults.set(deviceIdentifier, forKey: Keys.deviceIdentifier)
        }
    }
    
    @Published var deviceNames: [String] = ["DJI", "RODE", "ZOOM", "MIC", "RECORDER"] {
        didSet {
            userDefaults.set(deviceNames, forKey: Keys.deviceNames)
        }
    }
    
    @Published var enableAudioMerging: Bool = true {
        didSet {
            userDefaults.set(enableAudioMerging, forKey: Keys.enableAudioMerging)
        }
    }
    
    @Published var enableSmallFileDeletion: Bool = true {
        didSet {
            userDefaults.set(enableSmallFileDeletion, forKey: Keys.enableSmallFileDeletion)
        }
    }
    
    @Published var smallFileThreshold: Int64 = 5 * 1024 * 1024 { // 5MB default
        didSet {
            userDefaults.set(smallFileThreshold, forKey: Keys.smallFileThreshold)
        }
    }
    
    @Published var outputFormat: String = "m4a" { // "wav" or "m4a"
        didSet {
            userDefaults.set(outputFormat, forKey: Keys.outputFormat)
        }
    }
    
    init() {
        loadConfiguration()
    }
    
    private func loadConfiguration() {
        loadDestinationFolder()
        autoLaunch = userDefaults.bool(forKey: Keys.autoLaunch)
        deviceIdentifier = userDefaults.string(forKey: Keys.deviceIdentifier) ?? "DJI"
        deviceNames = userDefaults.stringArray(forKey: Keys.deviceNames) ?? ["DJI", "RODE", "ZOOM", "MIC", "RECORDER"]
        
        // Load audio processing settings
        enableAudioMerging = userDefaults.object(forKey: Keys.enableAudioMerging) as? Bool ?? true
        enableSmallFileDeletion = userDefaults.object(forKey: Keys.enableSmallFileDeletion) as? Bool ?? true
        smallFileThreshold = userDefaults.object(forKey: Keys.smallFileThreshold) as? Int64 ?? (5 * 1024 * 1024)
        outputFormat = userDefaults.string(forKey: Keys.outputFormat) ?? "m4a"
        
        if destinationFolderURL == nil {
            setDefaultDestinationFolder()
        }
    }
    
    private func setDefaultDestinationFolder() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let dropboxInbox = homeURL.appendingPathComponent("Dropbox/Inbox")
        let documentsFolder = homeURL.appendingPathComponent("Documents/RambleHelper")
        
        if FileManager.default.fileExists(atPath: dropboxInbox.path) {
            destinationFolderURL = dropboxInbox
        } else {
            try? FileManager.default.createDirectory(at: documentsFolder, withIntermediateDirectories: true)
            destinationFolderURL = documentsFolder
        }
    }
    
    private func loadDestinationFolder() {
        // Simply load the stored path - no need for bookmarks without sandboxing
        if let storedPath = userDefaults.string(forKey: Keys.destinationFolderBookmark) {
            let url = URL(fileURLWithPath: storedPath)
            if FileManager.default.fileExists(atPath: url.path) {
                destinationFolderURL = url
            }
        }
    }
    
    private func saveDestinationFolder() {
        guard let url = destinationFolderURL else {
            userDefaults.removeObject(forKey: Keys.destinationFolderBookmark)
            return
        }
        
        // Simply store the path - no need for bookmarks without sandboxing
        userDefaults.set(url.path, forKey: Keys.destinationFolderBookmark)
    }
    
    func setDestinationFolder(url: URL) {
        destinationFolderURL = url
    }
    
    var isConfigured: Bool {
        return destinationFolderURL != nil
    }
    
    var isDestinationFolderAccessible: Bool {
        guard let url = destinationFolderURL else { return false }
        
        // Simple check - just verify folder exists and is a directory
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        return exists && isDirectory.boolValue
    }
    
    func addDeviceName(_ name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty && !deviceNames.contains(trimmedName.uppercased()) else { return }
        deviceNames.append(trimmedName.uppercased())
    }
    
    func removeDeviceName(_ name: String) {
        deviceNames.removeAll { $0.uppercased() == name.uppercased() }
    }
    
    func resetDeviceNames() {
        deviceNames = ["DJI", "RODE", "ZOOM", "MIC", "RECORDER"]
    }
    
    // MARK: - Audio Processing Settings
    
    func setSmallFileThresholdMB(_ megabytes: Int) {
        smallFileThreshold = Int64(megabytes) * 1024 * 1024
    }
    
    func getSmallFileThresholdMB() -> Int {
        return Int(smallFileThreshold / (1024 * 1024))
    }
    
    func resetAudioProcessingSettings() {
        enableAudioMerging = true
        enableSmallFileDeletion = true
        smallFileThreshold = 5 * 1024 * 1024 // 5MB
        outputFormat = "m4a"
    }
    
    var isAudioProcessingEnabled: Bool {
        return enableAudioMerging || enableSmallFileDeletion
    }
    
    // MARK: - Login Item Management
    
    private func updateLoginItem() {
        if autoLaunch {
            enableLoginItem()
        } else {
            disableLoginItem()
        }
    }
    
    private func enableLoginItem() {
        do {
            if #available(macOS 13.0, *) {
                try SMAppService.mainApp.register()
            } else {
                // Fallback for older macOS versions
                let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.Baywood-Labs.RambleHelper"
                SMLoginItemSetEnabled(bundleIdentifier as CFString, true)
            }
        } catch {
            print("Failed to enable login item: \(error)")
        }
    }
    
    private func disableLoginItem() {
        do {
            if #available(macOS 13.0, *) {
                try SMAppService.mainApp.unregister()
            } else {
                // Fallback for older macOS versions
                let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.Baywood-Labs.RambleHelper"
                SMLoginItemSetEnabled(bundleIdentifier as CFString, false)
            }
        } catch {
            print("Failed to disable login item: \(error)")
        }
    }
    
    func initializeLoginItem() {
        // Set up login item on first launch if autoLaunch is enabled
        if autoLaunch {
            updateLoginItem()
        }
    }
}