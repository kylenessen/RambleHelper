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
    
    init() {
        loadConfiguration()
    }
    
    private func loadConfiguration() {
        loadDestinationFolder()
        autoLaunch = userDefaults.bool(forKey: Keys.autoLaunch)
        deviceIdentifier = userDefaults.string(forKey: Keys.deviceIdentifier) ?? "DJI"
        deviceNames = userDefaults.stringArray(forKey: Keys.deviceNames) ?? ["DJI", "RODE", "ZOOM", "MIC", "RECORDER"]
        
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
        guard let bookmarkData = userDefaults.data(forKey: Keys.destinationFolderBookmark) else {
            return
        }
        
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if !isStale && FileManager.default.fileExists(atPath: url.path) {
                destinationFolderURL = url
                _ = url.startAccessingSecurityScopedResource()
            }
        } catch {
            print("Failed to resolve bookmark: \(error)")
        }
    }
    
    private func saveDestinationFolder() {
        guard let url = destinationFolderURL else {
            userDefaults.removeObject(forKey: Keys.destinationFolderBookmark)
            return
        }
        
        do {
            let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            userDefaults.set(bookmarkData, forKey: Keys.destinationFolderBookmark)
        } catch {
            print("Failed to create bookmark: \(error)")
        }
    }
    
    func setDestinationFolder(url: URL) {
        destinationFolderURL = url
    }
    
    var isConfigured: Bool {
        return destinationFolderURL != nil
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