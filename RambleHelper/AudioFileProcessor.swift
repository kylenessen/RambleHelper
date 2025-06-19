//
//  AudioFileProcessor.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/19/25.
//

import Foundation

enum AudioProcessingError: Error, LocalizedError {
    case noFilesToProcess
    case smallFileThresholdExceeded(fileName: String, size: Int64, threshold: Int64)
    case processingFailed(String)
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .noFilesToProcess:
            return "No audio files found to process"
        case .smallFileThresholdExceeded(let fileName, let size, let threshold):
            let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            let thresholdStr = ByteCountFormatter.string(fromByteCount: threshold, countStyle: .file)
            return "File \(fileName) (\(sizeStr)) is below threshold (\(thresholdStr))"
        case .processingFailed(let reason):
            return "Audio processing failed: \(reason)"
        case .configurationError(let reason):
            return "Configuration error: \(reason)"
        }
    }
}

struct AudioProcessingResult {
    let processedFiles: [URL]
    let mergedFiles: [URL]
    let deletedSmallFiles: [URL]
    let skippedFiles: [URL]
    let totalProcessingTime: TimeInterval
}

struct AudioProcessingOptions {
    let enableMerging: Bool
    let enableSmallFileDeletion: Bool
    let smallFileThreshold: Int64 // in bytes
    let outputFormat: AudioFormat
    let preserveOriginals: Bool
    
    static let `default` = AudioProcessingOptions(
        enableMerging: true,
        enableSmallFileDeletion: true,
        smallFileThreshold: 5 * 1024 * 1024, // 5MB
        outputFormat: .m4a,
        preserveOriginals: false
    )
}

class AudioFileProcessor {
    private let audioMerger: AudioMerger
    private let logger: Logger
    
    var onProgress: ((String, Double) -> Void)?
    
    init() {
        self.audioMerger = AudioMerger()
        self.logger = Logger.shared
    }
    
    /// Main entry point for processing audio files
    /// - Parameters:
    ///   - files: Array of audio file URLs to process
    ///   - destinationFolder: Folder where processed files should be saved
    ///   - options: Processing options and settings
    /// - Returns: Results of the processing operation
    func processAudioFiles(
        files: [URL],
        destinationFolder: URL,
        options: AudioProcessingOptions = .default
    ) async throws -> AudioProcessingResult {
        
        let startTime = Date()
        logger.log("Starting audio processing: \(files.count) files")
        
        guard !files.isEmpty else {
            throw AudioProcessingError.noFilesToProcess
        }
        
        // Filter out small files if enabled
        let (filteredFiles, deletedSmallFiles) = try filterSmallFiles(
            files: files,
            threshold: options.smallFileThreshold,
            deleteSmallFiles: options.enableSmallFileDeletion
        )
        
        guard !filteredFiles.isEmpty else {
            logger.log("No files remaining after small file filtering")
            return AudioProcessingResult(
                processedFiles: [],
                mergedFiles: [],
                deletedSmallFiles: deletedSmallFiles,
                skippedFiles: [],
                totalProcessingTime: Date().timeIntervalSince(startTime)
            )
        }
        
        // Group files for potential merging
        let recordingGroups = DJIRecordingGroup.groupRecordings(from: filteredFiles)
        logger.log("Created \(recordingGroups.count) recording groups")
        
        var processedFiles: [URL] = []
        var mergedFiles: [URL] = []
        var skippedFiles: [URL] = []
        
        // Process each group
        for (index, group) in recordingGroups.enumerated() {
            let progress = Double(index) / Double(recordingGroups.count)
            onProgress?("Processing \(group.description)", progress)
            
            do {
                let result = try await processRecordingGroup(
                    group: group,
                    destinationFolder: destinationFolder,
                    options: options
                )
                
                processedFiles.append(contentsOf: result)
                
                if group.shouldMerge && options.enableMerging {
                    mergedFiles.append(contentsOf: result)
                }
                
            } catch {
                logger.log("Failed to process group \(group.description): \(error)", level: .error)
                skippedFiles.append(contentsOf: group.files)
            }
        }
        
        onProgress?("Processing complete", 1.0)
        
        let result = AudioProcessingResult(
            processedFiles: processedFiles,
            mergedFiles: mergedFiles,
            deletedSmallFiles: deletedSmallFiles,
            skippedFiles: skippedFiles,
            totalProcessingTime: Date().timeIntervalSince(startTime)
        )
        
        logger.log("Audio processing completed: \(processedFiles.count) processed, \(mergedFiles.count) merged, \(deletedSmallFiles.count) deleted")
        
        return result
    }
    
    /// Filters out small files based on the threshold
    private func filterSmallFiles(
        files: [URL],
        threshold: Int64,
        deleteSmallFiles: Bool
    ) throws -> (filtered: [URL], deleted: [URL]) {
        
        var filteredFiles: [URL] = []
        var deletedFiles: [URL] = []
        
        for file in files {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                
                if fileSize < threshold {
                    logger.log("Small file detected: \(file.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))")
                    
                    if deleteSmallFiles {
                        try FileManager.default.removeItem(at: file)
                        deletedFiles.append(file)
                        logger.log("Deleted small file: \(file.lastPathComponent)")
                    } else {
                        filteredFiles.append(file) // Keep it if not deleting
                    }
                } else {
                    filteredFiles.append(file)
                }
            } catch {
                logger.log("Failed to check file size for \(file.lastPathComponent): \(error)", level: .error)
                filteredFiles.append(file) // Include file if we can't check its size
            }
        }
        
        return (filteredFiles, deletedFiles)
    }
    
    /// Processes a single recording group (merge if needed, convert format)
    private func processRecordingGroup(
        group: DJIRecordingGroup,
        destinationFolder: URL,
        options: AudioProcessingOptions
    ) async throws -> [URL] {
        
        let outputFileName = group.generateOutputFileName(withExtension: options.outputFormat.fileExtension)
        let outputURL = destinationFolder.appendingPathComponent(outputFileName)
        
        if group.shouldMerge && options.enableMerging {
            // Merge multiple files
            logger.log("Merging \(group.files.count) files into \(outputFileName)")
            
            // Validate files can be merged
            try await audioMerger.validateAudioFiles(group.files)
            
            // Perform the merge
            let duration = try await audioMerger.mergeAudioFiles(
                inputFiles: group.files,
                outputURL: outputURL,
                outputFormat: options.outputFormat
            )
            
            logger.log("Successfully merged \(group.files.count) files (duration: \(String(format: "%.1f", duration))s)")
            
            // Remove original files if not preserving
            if !options.preserveOriginals {
                for originalFile in group.files {
                    try? FileManager.default.removeItem(at: originalFile)
                }
            }
            
            return [outputURL]
            
        } else {
            // Single file - just convert format if needed
            let inputFile = group.files[0]
            
            if inputFile.pathExtension.lowercased() == options.outputFormat.fileExtension {
                // No conversion needed, just move/copy to destination
                if options.preserveOriginals {
                    try FileManager.default.copyItem(at: inputFile, to: outputURL)
                } else {
                    try FileManager.default.moveItem(at: inputFile, to: outputURL)
                }
                
                logger.log("Moved \(inputFile.lastPathComponent) to destination (no conversion needed)")
            } else {
                // Convert format
                let duration = try await audioMerger.mergeAudioFiles(
                    inputFiles: [inputFile],
                    outputURL: outputURL,
                    outputFormat: options.outputFormat
                )
                
                logger.log("Converted \(inputFile.lastPathComponent) to \(options.outputFormat.fileExtension) (duration: \(String(format: "%.1f", duration))s)")
                
                // Remove original if not preserving
                if !options.preserveOriginals {
                    try? FileManager.default.removeItem(at: inputFile)
                }
            }
            
            return [outputURL]
        }
    }
    
    /// Estimates the total processing time for a set of files
    func estimateProcessingTime(for files: [URL]) async -> TimeInterval {
        var totalSize: Int64 = 0
        
        for file in files {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attributes[.size] as? Int64 {
                totalSize += size
            }
        }
        
        // Rough estimate: ~1 second per 10MB for merging/conversion
        let estimatedSeconds = Double(totalSize) / (10 * 1024 * 1024)
        return max(estimatedSeconds, 1.0) // At least 1 second
    }
    
    /// Validates that destination folder is writable and has enough space
    func validateDestination(_ destinationFolder: URL, requiredSpace: Int64) throws {
        let fileManager = FileManager.default
        
        // Check if destination exists and is writable
        guard fileManager.fileExists(atPath: destinationFolder.path) else {
            throw AudioProcessingError.configurationError("Destination folder does not exist")
        }
        
        guard fileManager.isWritableFile(atPath: destinationFolder.path) else {
            throw AudioProcessingError.configurationError("Destination folder is not writable")
        }
        
        // Check available space
        do {
            let resourceValues = try destinationFolder.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let availableCapacity = resourceValues.volumeAvailableCapacity,
               Int64(availableCapacity) < requiredSpace {
                let availableStr = ByteCountFormatter.string(fromByteCount: Int64(availableCapacity), countStyle: .file)
                let requiredStr = ByteCountFormatter.string(fromByteCount: requiredSpace, countStyle: .file)
                throw AudioProcessingError.configurationError("Insufficient space: need \(requiredStr), have \(availableStr)")
            }
        } catch let error as AudioProcessingError {
            throw error
        } catch {
            logger.log("Could not check available space: \(error)", level: .warning)
        }
    }
}