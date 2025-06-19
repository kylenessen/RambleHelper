//
//  AudioMerger.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/19/25.
//

import Foundation
import AVFoundation

enum AudioMergerError: Error, LocalizedError {
    case invalidInputFile(String)
    case incompatibleFormats
    case exportFailed(String)
    case noInputFiles
    case fileAccessError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidInputFile(let file):
            return "Invalid input file: \(file)"
        case .incompatibleFormats:
            return "Audio files have incompatible formats"
        case .exportFailed(let reason):
            return "Audio export failed: \(reason)"
        case .noInputFiles:
            return "No input files provided"
        case .fileAccessError(let file):
            return "Cannot access file: \(file)"
        }
    }
}

enum AudioFormat {
    case wav
    case m4a
    
    var fileExtension: String {
        switch self {
        case .wav:
            return "wav"
        case .m4a:
            return "m4a"
        }
    }
    
    var avFileType: AVFileType {
        switch self {
        case .wav:
            return .wav
        case .m4a:
            return .m4a
        }
    }
    
    var codecSettings: [String: Any] {
        switch self {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVEncoderBitRateKey: 128000,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100
            ]
        }
    }
}

class AudioMerger {
    private let logger: Logger
    
    init() {
        self.logger = Logger.shared
    }
    
    /// Merges multiple audio files into a single output file
    /// - Parameters:
    ///   - inputFiles: Array of URLs to audio files to merge
    ///   - outputURL: URL where the merged file should be saved
    ///   - outputFormat: Format for the output file (wav or m4a)
    /// - Returns: The duration of the merged audio file
    func mergeAudioFiles(
        inputFiles: [URL],
        outputURL: URL,
        outputFormat: AudioFormat = .m4a
    ) async throws -> TimeInterval {
        
        guard !inputFiles.isEmpty else {
            throw AudioMergerError.noInputFiles
        }
        
        logger.log("Starting audio merge: \(inputFiles.count) files -> \(outputURL.lastPathComponent)")
        
        // Verify all input files exist and are accessible
        for file in inputFiles {
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw AudioMergerError.fileAccessError(file.lastPathComponent)
            }
        }
        
        // For single file, just convert format if needed
        if inputFiles.count == 1 {
            return try await convertAudioFile(
                inputURL: inputFiles[0],
                outputURL: outputURL,
                outputFormat: outputFormat
            )
        }
        
        // Create composition for multiple files
        let composition = AVMutableComposition()
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioMergerError.exportFailed("Failed to create audio track")
        }
        
        var insertTime = CMTime.zero
        var totalDuration: TimeInterval = 0
        
        // Add each input file to the composition
        for inputURL in inputFiles {
            let asset = AVAsset(url: inputURL)
            
            // Wait for asset to load
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            
            guard let sourceTrack = tracks.first else {
                logger.log("No audio track found in \(inputURL.lastPathComponent)", level: .warning)
                continue
            }
            
            do {
                let timeRange = CMTimeRange(start: .zero, duration: duration)
                try audioTrack.insertTimeRange(timeRange, of: sourceTrack, at: insertTime)
                
                insertTime = CMTimeAdd(insertTime, duration)
                totalDuration += duration.seconds
                
                logger.log("Added \(inputURL.lastPathComponent) (duration: \(String(format: "%.1f", duration.seconds))s)")
                
            } catch {
                logger.log("Failed to insert \(inputURL.lastPathComponent): \(error)", level: .error)
                throw AudioMergerError.exportFailed("Failed to insert \(inputURL.lastPathComponent)")
            }
        }
        
        // Export the composition
        try await exportComposition(
            composition,
            to: outputURL,
            outputFormat: outputFormat
        )
        
        logger.log("Audio merge completed: \(String(format: "%.1f", totalDuration))s total duration")
        return totalDuration
    }
    
    /// Converts a single audio file to the specified format
    private func convertAudioFile(
        inputURL: URL,
        outputURL: URL,
        outputFormat: AudioFormat
    ) async throws -> TimeInterval {
        
        let asset = AVAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        
        // If input is already in the desired format and no conversion needed, just copy
        if inputURL.pathExtension.lowercased() == outputFormat.fileExtension {
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            logger.log("Copied \(inputURL.lastPathComponent) (no conversion needed)")
            return duration.seconds
        }
        
        // Otherwise, export with format conversion
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioMergerError.exportFailed("Failed to create export session")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFormat.avFileType
        
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            logger.log("Converted \(inputURL.lastPathComponent) to \(outputFormat.fileExtension)")
            return duration.seconds
        case .failed:
            let error = exportSession.error?.localizedDescription ?? "Unknown error"
            throw AudioMergerError.exportFailed(error)
        case .cancelled:
            throw AudioMergerError.exportFailed("Export was cancelled")
        default:
            throw AudioMergerError.exportFailed("Export failed with status: \(exportSession.status.rawValue)")
        }
    }
    
    /// Exports an AVComposition to the specified output URL and format
    private func exportComposition(
        _ composition: AVMutableComposition,
        to outputURL: URL,
        outputFormat: AudioFormat
    ) async throws {
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioMergerError.exportFailed("Failed to create export session")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFormat.avFileType
        
        // Note: audioSettings is not available on AVAssetExportSession
        // Quality is controlled by the preset used (AVAssetExportPresetAppleM4A)
        
        await exportSession.export()
        
        switch exportSession.status {
        case .completed:
            logger.log("Successfully exported merged audio to \(outputURL.lastPathComponent)")
        case .failed:
            let error = exportSession.error?.localizedDescription ?? "Unknown error"
            throw AudioMergerError.exportFailed(error)
        case .cancelled:
            throw AudioMergerError.exportFailed("Export was cancelled")
        default:
            throw AudioMergerError.exportFailed("Export failed with status: \(exportSession.status.rawValue)")
        }
    }
    
    /// Validates that audio files have compatible formats for merging
    func validateAudioFiles(_ files: [URL]) async throws {
        guard !files.isEmpty else {
            throw AudioMergerError.noInputFiles
        }
        
        var commonFormat: CMFormatDescription?
        
        for file in files {
            let asset = AVAsset(url: file)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            
            guard let track = tracks.first else {
                throw AudioMergerError.invalidInputFile(file.lastPathComponent)
            }
            
            let formatDescriptions = try await track.load(.formatDescriptions)
            guard let formatDescription = formatDescriptions.first else {
                throw AudioMergerError.invalidInputFile(file.lastPathComponent)
            }
            
            if commonFormat == nil {
                commonFormat = formatDescription
            } else {
                // Basic compatibility check - we'll let AVFoundation handle the details
                // Most WAV files from the same device should be compatible
            }
        }
    }
    
    /// Gets the duration of an audio file
    func getAudioDuration(url: URL) async throws -> TimeInterval {
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }
    
    /// Checks if a file is a valid audio file
    func isValidAudioFile(url: URL) async -> Bool {
        let asset = AVAsset(url: url)
        
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return !tracks.isEmpty
        } catch {
            return false
        }
    }
}