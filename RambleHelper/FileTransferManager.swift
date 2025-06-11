//
//  FileTransferManager.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/10/25.
//

import Foundation

enum TransferState {
    case idle
    case transferring
    case error
}

struct TransferResult {
    let transferredCount: Int
    let skippedCount: Int
    let errorCount: Int
}

enum TransferError: Error, LocalizedError {
    case noDestinationFolder
    case insufficientSpace(required: Int64, available: Int64)
    case fileNotFound(String)
    case permissionDenied(String)
    case copyFailed(String)
    case verificationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noDestinationFolder:
            return "No destination folder configured"
        case .insufficientSpace(let required, let available):
            return "Insufficient space: need \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), have \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .copyFailed(let reason):
            return "Copy failed: \(reason)"
        case .verificationFailed(let file):
            return "Verification failed for: \(file)"
        }
    }
}

class FileTransferManager {
    private let configurationManager: ConfigurationManager
    private let notificationManager: NotificationManager
    private let logger: Logger
    
    private(set) var currentState: TransferState = .idle {
        didSet {
            onStateChange?(currentState)
        }
    }
    
    var onStateChange: ((TransferState) -> Void)?
    
    init(configurationManager: ConfigurationManager, notificationManager: NotificationManager) {
        self.configurationManager = configurationManager
        self.notificationManager = notificationManager
        self.logger = Logger.shared
    }
    
    func transferFiles(from sourceURL: URL) async throws -> TransferResult {
        currentState = .transferring
        logger.log("Starting file transfer from: \(sourceURL.path)")
        
        defer {
            currentState = .idle
        }
        
        guard let destinationURL = configurationManager.destinationFolderURL else {
            logger.log("No destination folder configured", level: .error)
            throw TransferError.noDestinationFolder
        }
        
        let wavFiles = try findWAVFiles(in: sourceURL)
        logger.log("Found \(wavFiles.count) WAV files")
        
        if wavFiles.isEmpty {
            return TransferResult(transferredCount: 0, skippedCount: 0, errorCount: 0)
        }
        
        try checkAvailableSpace(for: wavFiles, destination: destinationURL)
        
        var transferredCount = 0
        var skippedCount = 0
        var errorCount = 0
        
        for sourceFile in wavFiles {
            do {
                let success = try await transferFile(from: sourceFile, to: destinationURL)
                if success {
                    transferredCount += 1
                } else {
                    skippedCount += 1
                }
            } catch {
                logger.log("Failed to transfer \(sourceFile.lastPathComponent): \(error)", level: .error)
                errorCount += 1
            }
        }
        
        logger.log("Transfer complete: \(transferredCount) transferred, \(skippedCount) skipped, \(errorCount) errors")
        return TransferResult(transferredCount: transferredCount, skippedCount: skippedCount, errorCount: errorCount)
    }
    
    private func findWAVFiles(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                print("Error accessing \(url): \(error)")
                return true
            }
        ) else {
            throw TransferError.fileNotFound(directory.path)
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
    
    private func checkAvailableSpace(for files: [URL], destination: URL) throws {
        let totalSize = files.compactMap { fileURL -> Int64? in
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                return attributes[.size] as? Int64
            } catch {
                return nil
            }
        }.reduce(0, +)
        
        do {
            let resourceValues = try destination.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let availableCapacity = resourceValues.volumeAvailableCapacity,
               totalSize > availableCapacity {
                throw TransferError.insufficientSpace(required: totalSize, available: Int64(availableCapacity))
            }
        } catch let error as TransferError {
            throw error
        } catch {
            logger.log("Could not check available space: \(error)", level: .warning)
        }
    }
    
    private func transferFile(from sourceURL: URL, to destinationFolder: URL) async throws -> Bool {
        let fileName = sourceURL.lastPathComponent
        let destinationURL = getUniqueDestinationURL(for: fileName, in: destinationFolder)
        
        logger.log("Transferring: \(fileName) -> \(destinationURL.lastPathComponent)")
        
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            
            try await verifyTransfer(source: sourceURL, destination: destinationURL)
            
            try FileManager.default.removeItem(at: sourceURL)
            
            logger.log("Successfully transferred: \(fileName)")
            return true
            
        } catch CocoaError.fileWriteFileExists {
            logger.log("File already exists (skipped): \(fileName)", level: .warning)
            return false
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw TransferError.copyFailed(error.localizedDescription)
        }
    }
    
    private func getUniqueDestinationURL(for fileName: String, in folder: URL) -> URL {
        let fileManager = FileManager.default
        let fileExtension = (fileName as NSString).pathExtension
        let baseName = (fileName as NSString).deletingPathExtension
        
        var destinationURL = folder.appendingPathComponent(fileName)
        var counter = 1
        
        while fileManager.fileExists(atPath: destinationURL.path) {
            let newFileName = "\(baseName)_\(counter).\(fileExtension)"
            destinationURL = folder.appendingPathComponent(newFileName)
            counter += 1
        }
        
        return destinationURL
    }
    
    private func verifyTransfer(source: URL, destination: URL) async throws {
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
        
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw TransferError.verificationFailed(destination.lastPathComponent)
        }
        
        do {
            let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
            let destAttributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            
            let sourceSize = sourceAttributes[.size] as? Int64 ?? 0
            let destSize = destAttributes[.size] as? Int64 ?? 0
            
            if sourceSize != destSize {
                throw TransferError.verificationFailed("Size mismatch: \(sourceSize) vs \(destSize)")
            }
        } catch {
            throw TransferError.verificationFailed(error.localizedDescription)
        }
    }
}