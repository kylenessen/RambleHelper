//
//  ConfigurationManager.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/10/25.
//

import Foundation

class ConfigurationManager: ObservableObject {
    private let userDefaults = UserDefaults.standard
    
    private struct Keys {
        static let destinationFolderBookmark = "destinationFolderBookmark"
        static let autoLaunch = "autoLaunch"
        static let deviceIdentifier = "deviceIdentifier"
    }
    
    @Published var destinationFolderURL: URL? {
        didSet {
            saveDestinationFolder()
        }
    }
    
    @Published var autoLaunch: Bool = true {
        didSet {
            userDefaults.set(autoLaunch, forKey: Keys.autoLaunch)
        }
    }
    
    @Published var deviceIdentifier: String = "DJI" {
        didSet {
            userDefaults.set(deviceIdentifier, forKey: Keys.deviceIdentifier)
        }
    }
    
    init() {
        loadConfiguration()
    }
    
    private func loadConfiguration() {
        loadDestinationFolder()
        autoLaunch = userDefaults.bool(forKey: Keys.autoLaunch)
        deviceIdentifier = userDefaults.string(forKey: Keys.deviceIdentifier) ?? "DJI"
        
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
}