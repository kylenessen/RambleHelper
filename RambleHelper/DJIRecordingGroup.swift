//
//  DJIRecordingGroup.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/19/25.
//

import Foundation

/// Represents a group of sequential recordings from DJI devices that should be merged together
struct DJIRecordingGroup {
    let files: [URL]
    let baseFileName: String
    let totalSize: Int64
    let totalDuration: TimeInterval?
    
    /// Creates a recording group from a collection of related files
    init(files: [URL]) {
        self.files = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        // Extract base name (e.g., "DJI_001.WAV" -> "DJI")
        if let firstFile = self.files.first {
            self.baseFileName = Self.extractBaseFileName(from: firstFile.lastPathComponent)
        } else {
            self.baseFileName = "Recording"
        }
        
        // Calculate total size
        self.totalSize = files.compactMap { url in
            try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
        }.reduce(0, +)
        
        // Duration will be calculated during audio processing
        self.totalDuration = nil
    }
    
    /// Extracts the base file name without sequence numbers
    /// Examples: "DJI_001.WAV" -> "DJI", "MIC_Recording_01.wav" -> "MIC_Recording"
    private static func extractBaseFileName(from fileName: String) -> String {
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension
        
        // Common patterns for sequence numbering
        let patterns = [
            "_\\d+$",           // _001, _1, etc.
            "_\\d{2,}$",        // _01, _001, etc.
            "\\s\\d+$",         // " 001", " 1", etc.
            "\\(\\d+\\)$"       // (1), (001), etc.
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: nameWithoutExtension.count)
                let result = regex.stringByReplacingMatches(
                    in: nameWithoutExtension,
                    options: [],
                    range: range,
                    withTemplate: ""
                )
                if result != nameWithoutExtension {
                    return result.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        return nameWithoutExtension
    }
    
    /// Groups WAV files by their base names and sequence patterns
    static func groupRecordings(from files: [URL]) -> [DJIRecordingGroup] {
        // Filter to only WAV files
        let wavFiles = files.filter { $0.pathExtension.lowercased() == "wav" }
        
        // Group files by their base names
        var groups: [String: [URL]] = [:]
        
        for file in wavFiles {
            let baseName = extractBaseFileName(from: file.lastPathComponent)
            if groups[baseName] == nil {
                groups[baseName] = []
            }
            groups[baseName]?.append(file)
        }
        
        // Create recording groups, but only for groups with multiple files or DJI-specific patterns
        var recordingGroups: [DJIRecordingGroup] = []
        
        for (baseName, fileGroup) in groups {
            if shouldGroupFiles(baseName: baseName, files: fileGroup) {
                recordingGroups.append(DJIRecordingGroup(files: fileGroup))
            } else {
                // Create individual groups for files that don't need merging
                for file in fileGroup {
                    recordingGroups.append(DJIRecordingGroup(files: [file]))
                }
            }
        }
        
        return recordingGroups.sorted { $0.baseFileName < $1.baseFileName }
    }
    
    /// Determines if files should be grouped together for merging
    private static func shouldGroupFiles(baseName: String, files: [URL]) -> Bool {
        // Only group if we have multiple files
        guard files.count > 1 else { return false }
        
        // Check for DJI-specific naming patterns
        let djiPatterns = ["dji", "mic", "rec"]
        let lowerBaseName = baseName.lowercased()
        
        let isDJILike = djiPatterns.contains { pattern in
            lowerBaseName.contains(pattern)
        }
        
        // Also check if files follow sequential naming
        let sortedFiles = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let hasSequentialNaming = checkSequentialNaming(files: sortedFiles)
        
        return isDJILike || hasSequentialNaming
    }
    
    /// Checks if files follow a sequential naming pattern
    private static func checkSequentialNaming(files: [URL]) -> Bool {
        guard files.count > 1 else { return false }
        
        let fileNames = files.map { ($0.lastPathComponent as NSString).deletingPathExtension }
        
        // Extract numbers from the end of filenames
        var numbers: [Int] = []
        let numberPattern = "\\d+$"
        
        guard let regex = try? NSRegularExpression(pattern: numberPattern, options: []) else {
            return false
        }
        
        for fileName in fileNames {
            let range = NSRange(location: 0, length: fileName.count)
            if let match = regex.firstMatch(in: fileName, options: [], range: range) {
                let numberString = (fileName as NSString).substring(with: match.range)
                if let number = Int(numberString) {
                    numbers.append(number)
                } else {
                    return false
                }
            } else {
                return false
            }
        }
        
        // Check if numbers are sequential (allowing for gaps)
        guard numbers.count == fileNames.count else { return false }
        
        let sortedNumbers = numbers.sorted()
        
        // Check if the difference between consecutive numbers is reasonable (1-10)
        for i in 1..<sortedNumbers.count {
            let diff = sortedNumbers[i] - sortedNumbers[i-1]
            if diff < 1 || diff > 10 {
                return false
            }
        }
        
        return true
    }
    
    /// Generates the output filename for the merged recording
    func generateOutputFileName(withExtension ext: String = "m4a") -> String {
        if files.count == 1 {
            // Single file, just change extension
            let originalName = (files[0].lastPathComponent as NSString).deletingPathExtension
            return "\(originalName).\(ext)"
        } else {
            // Multiple files, use base name with merged indicator
            return "\(baseFileName)_merged.\(ext)"
        }
    }
    
    /// Checks if this group represents multiple files that should be merged
    var shouldMerge: Bool {
        return files.count > 1
    }
    
    /// Returns a human-readable description of the group
    var description: String {
        if files.count == 1 {
            return files[0].lastPathComponent
        } else {
            let sizeString = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            return "\(baseFileName) (\(files.count) files, \(sizeString))"
        }
    }
}