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
    /// Examples: "DJI_30_20250607_110648.WAV" -> "DJI_20250607_110648", "MIC_Recording_01.wav" -> "MIC_Recording"
    private static func extractBaseFileName(from fileName: String) -> String {
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension
        
        // Special handling for DJI files: DJI_XX_YYYYMMDD_HHMMSS -> DJI_YYYYMMDD_HHMMSS
        let djiPattern = "^DJI_(\\d+)_(\\d{8}_\\d{6})$"
        if let regex = try? NSRegularExpression(pattern: djiPattern, options: []),
           let match = regex.firstMatch(in: nameWithoutExtension, options: [], range: NSRange(location: 0, length: nameWithoutExtension.count)) {
            let timestampRange = match.range(at: 2)
            if timestampRange.location != NSNotFound {
                let timestamp = (nameWithoutExtension as NSString).substring(with: timestampRange)
                return "DJI_\(timestamp)"
            }
        }
        
        // Common patterns for sequence numbering (fallback for non-DJI files)
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
        
        // First, try to group DJI files specifically
        let djiGroups = groupDJIRecordings(from: wavFiles)
        let djiGroupedFiles = Set(djiGroups.flatMap { $0.files })
        let remainingFiles = wavFiles.filter { !djiGroupedFiles.contains($0) }
        
        // Group remaining files by their base names using the original logic
        var groups: [String: [URL]] = [:]
        
        for file in remainingFiles {
            let baseName = extractBaseFileName(from: file.lastPathComponent)
            if groups[baseName] == nil {
                groups[baseName] = []
            }
            groups[baseName]?.append(file)
        }
        
        // Create recording groups for remaining files
        var recordingGroups: [DJIRecordingGroup] = djiGroups
        
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
    
    /// Groups DJI recordings specifically based on sequence numbers, file size, and creation time
    private static func groupDJIRecordings(from files: [URL]) -> [DJIRecordingGroup] {
        // Filter to DJI files using the pattern: DJI_XX_YYYYMMDD_HHMMSS.WAV
        let djiPattern = "^DJI_\\d+_\\d{8}_\\d{6}\\.wav$"
        guard let regex = try? NSRegularExpression(pattern: djiPattern, options: .caseInsensitive) else {
            return []
        }
        
        let djiFiles = files.filter { file in
            let fileName = file.lastPathComponent
            let range = NSRange(location: 0, length: fileName.count)
            return regex.firstMatch(in: fileName, options: [], range: range) != nil
        }
        
        guard !djiFiles.isEmpty else { return [] }
        
        // Parse DJI files into structured data
        struct DJIFileInfo {
            let url: URL
            let sequenceNumber: Int
            let timestamp: String  // YYYYMMDD_HHMMSS
            let fileSize: Int64
            let creationDate: Date?
        }
        
        let djiFileInfos: [DJIFileInfo] = djiFiles.compactMap { file in
            let fileName = file.lastPathComponent
            
            // Extract sequence number and timestamp from DJI_XX_YYYYMMDD_HHMMSS.WAV
            let components = fileName.dropLast(4).components(separatedBy: "_") // Remove .WAV
            guard components.count >= 3,
                  components[0] == "DJI",
                  let sequenceNumber = Int(components[1]),
                  components.count >= 4 else { return nil }
            
            let timestamp = "\(components[2])_\(components[3])"
            
            // Get file size
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            
            // Get creation date
            let creationDate = (try? FileManager.default.attributesOfItem(atPath: file.path)[.creationDate] as? Date)
            
            return DJIFileInfo(
                url: file,
                sequenceNumber: sequenceNumber,
                timestamp: timestamp,
                fileSize: fileSize,
                creationDate: creationDate
            )
        }
        
        // Group files by timestamp base and consecutive sequence numbers
        var groups: [String: [DJIFileInfo]] = [:]
        
        // Sort by sequence number first
        let sortedInfos = djiFileInfos.sorted { $0.sequenceNumber < $1.sequenceNumber }
        
        for info in sortedInfos {
            var foundGroup = false
            
            // Try to add to existing group if it's consecutive
            for (groupKey, existingGroup) in groups {
                guard let lastInGroup = existingGroup.last else { continue }
                
                // Check if this file could be part of this group
                let isConsecutiveSequence = info.sequenceNumber == lastInGroup.sequenceNumber + 1
                let isLargeFile = lastInGroup.fileSize >= 268_000_000 // ~268MB indicates file was split
                
                // Check creation time proximity (within 5 minutes)
                var isTimeProximate = false
                if let lastDate = lastInGroup.creationDate,
                   let currentDate = info.creationDate {
                    let timeDiff = abs(currentDate.timeIntervalSince(lastDate))
                    isTimeProximate = timeDiff <= 300 // 5 minutes
                }
                
                if isConsecutiveSequence && (isLargeFile || isTimeProximate) {
                    groups[groupKey]?.append(info)
                    foundGroup = true
                    break
                }
            }
            
            // If not added to existing group, create new group
            if !foundGroup {
                let groupKey = "\(info.timestamp)_\(info.sequenceNumber)"
                groups[groupKey] = [info]
            }
        }
        
        // Convert groups to DJIRecordingGroup, only keeping groups with 2+ files or large single files
        return groups.compactMap { (_, fileInfos) in
            let urls = fileInfos.map { $0.url }
            
            // Group if: multiple files OR single large file (which might have more parts coming)
            if fileInfos.count > 1 {
                return DJIRecordingGroup(files: urls)
            } else if fileInfos.count == 1 && fileInfos[0].fileSize >= 268_000_000 {
                // Large single file - check if there might be more parts by looking for consecutive files
                let currentSeq = fileInfos[0].sequenceNumber
                let hasNextSequence = sortedInfos.contains { $0.sequenceNumber == currentSeq + 1 }
                
                if hasNextSequence {
                    // Will be picked up in a later iteration
                    return nil
                } else {
                    // Single large file with no continuation - process individually
                    return DJIRecordingGroup(files: urls)
                }
            }
            
            return nil
        }
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