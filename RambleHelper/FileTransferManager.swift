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
    case processing
    case error
}

struct TransferResult {
    let transferredCount: Int
    let processedCount: Int
    let mergedCount: Int
    let deletedSmallCount: Int
    let skippedCount: Int
    let errorCount: Int
}

enum TransferError: Error, LocalizedError {
    case noDestinationFolder
    case destinationNotAccessible
    case insufficientSpace(required: Int64, available: Int64)
    case fileNotFound(String)
    case permissionDenied(String)
    case copyFailed(String)
    case verificationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noDestinationFolder:
            return "No destination folder configured"
        case .destinationNotAccessible:
            return "Destination folder is not accessible or writable"
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
    private let audioProcessor: AudioFileProcessor
    private var backgroundActivity: NSObjectProtocol?
    
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
        self.audioProcessor = AudioFileProcessor()
        
        // Set up progress callback for audio processing
        self.audioProcessor.onProgress = { [weak self] message, progress in
            self?.logger.log("Audio processing: \(message) (\(Int(progress * 100))%)")
        }
    }
    
    /// Begins background activity to prevent app suspension during processing
    private func beginBackgroundActivity(reason: String) {
        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: [.background, .latencyCritical],
            reason: reason
        )
        logger.log("Background activity started: \(reason)")
    }
    
    /// Ends background activity when processing is complete
    private func endBackgroundActivity() {
        if let activity = backgroundActivity {
            ProcessInfo.processInfo.endActivity(activity)
            backgroundActivity = nil
            logger.log("Background activity ended")
        }
    }
    
    func transferFiles(from sourceURL: URL) async throws -> TransferResult {
        currentState = .transferring
        logger.log("Starting file transfer from: \(sourceURL.path)")
        
        // Begin background activity to prevent suspension during processing
        beginBackgroundActivity(reason: "Audio file transfer and processing")
        
        defer {
            currentState = .idle
            endBackgroundActivity()
        }
        
        guard let destinationURL = configurationManager.destinationFolderURL else {
            logger.log("No destination folder configured", level: .error)
            throw TransferError.noDestinationFolder
        }
        
        guard configurationManager.isDestinationFolderAccessible else {
            logger.log("Destination folder is not accessible: \(destinationURL.path)", level: .error)
            throw TransferError.destinationNotAccessible
        }
        
        let wavFiles = try findWAVFiles(in: sourceURL)
        logger.log("Found \(wavFiles.count) WAV files")
        
        if wavFiles.isEmpty {
            return TransferResult(
                transferredCount: 0,
                processedCount: 0,
                mergedCount: 0,
                deletedSmallCount: 0,
                skippedCount: 0,
                errorCount: 0
            )
        }
        
        try checkAvailableSpace(for: wavFiles, destination: destinationURL)
        
        // Step 1: Transfer files to a temporary processing directory (use system temp to avoid Dropbox permissions)
        let systemTempDir = FileManager.default.temporaryDirectory
        let tempProcessingDir = systemTempDir.appendingPathComponent("ramble_processing_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempProcessingDir, withIntermediateDirectories: true)
        
        var transferredFiles: [URL] = []
        var transferredCount = 0
        var errorCount = 0
        
        defer {
            // Clean up temp directory
            try? FileManager.default.removeItem(at: tempProcessingDir)
        }
        
        // Transfer files to temp directory
        for sourceFile in wavFiles {
            do {
                let tempDestination = tempProcessingDir.appendingPathComponent(sourceFile.lastPathComponent)
                try FileManager.default.copyItem(at: sourceFile, to: tempDestination)
                transferredFiles.append(tempDestination)
                transferredCount += 1
            } catch {
                logger.log("Failed to transfer \(sourceFile.lastPathComponent): \(error)", level: .error)
                errorCount += 1
            }
        }
        
        // Step 2: Process audio files (merge, convert, filter)
        currentState = .processing
        
        var processedCount = 0
        var mergedCount = 0
        var deletedSmallCount = 0
        var skippedCount = 0
        
        if !transferredFiles.isEmpty {
            do {
                let processingOptions = AudioProcessingOptions(
                    enableMerging: configurationManager.enableAudioMerging,
                    enableSmallFileDeletion: configurationManager.enableSmallFileDeletion,
                    smallFileThreshold: configurationManager.smallFileThreshold,
                    outputFormat: configurationManager.outputFormat == "wav" ? .wav : .m4a,
                    preserveOriginals: false
                )
                
                logger.log("Sending files to audio processor with destination: \(destinationURL.path)")
                let processingResult = try await audioProcessor.processAudioFiles(
                    files: transferredFiles,
                    destinationFolder: destinationURL,
                    options: processingOptions
                )
                
                processedCount = processingResult.processedFiles.count
                mergedCount = processingResult.mergedFiles.count
                deletedSmallCount = processingResult.deletedSmallFiles.count
                skippedCount = processingResult.skippedFiles.count
                
                logger.log("Audio processing complete: \(processedCount) processed, \(mergedCount) merged, \(deletedSmallCount) small files deleted")
                
            } catch {
                logger.log("Audio processing failed: \(error)", level: .error)
                // Fall back to simple file copy for unprocessed files
                for file in transferredFiles {
                    let destination = getUniqueDestinationURL(for: file.lastPathComponent, in: destinationURL)
                    try? FileManager.default.moveItem(at: file, to: destination)
                }
                errorCount += 1
            }
        }
        
        // Step 3: Clean up original files from device
        for sourceFile in wavFiles {
            try? FileManager.default.removeItem(at: sourceFile)
        }
        
        logger.log("Transfer and processing complete: \(transferredCount) transferred, \(processedCount) processed, \(mergedCount) merged, \(deletedSmallCount) small files deleted, \(skippedCount) skipped, \(errorCount) errors")
        
        return TransferResult(
            transferredCount: transferredCount,
            processedCount: processedCount,
            mergedCount: mergedCount,
            deletedSmallCount: deletedSmallCount,
            skippedCount: skippedCount,
            errorCount: errorCount
        )
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