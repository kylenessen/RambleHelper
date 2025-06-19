//
//  Logger.swift
//  RambleHelper
//
//  Created by Kyle Nessen on 6/10/25.
//

import Foundation
import os.log

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    
    var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .error
        case .error:
            return .fault
        }
    }
}

class Logger {
    static let shared = Logger()
    
    private let osLog = OSLog(subsystem: "com.Baywood-Labs.RambleHelper", category: "general")
    private let logQueue = DispatchQueue(label: "com.ramblehelper.logging", qos: .utility)
    private let dateFormatter: DateFormatter
    private var logFileURL: URL?
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        setupLogFile()
    }
    
    private func setupLogFile() {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }
        
        let logsDirectory = libraryURL.appendingPathComponent("Logs/RambleHelper")
        
        do {
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            
            let logFileName = "ramblehelper-\(DateFormatter.logFileName.string(from: Date())).log"
            logFileURL = logsDirectory.appendingPathComponent(logFileName)
            
            cleanupOldLogs(in: logsDirectory)
        } catch {
            print("Failed to setup log file: \(error)")
        }
    }
    
    private func cleanupOldLogs(in directory: URL) {
        let fileManager = FileManager.default
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        
        do {
            let logFiles = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            
            for fileURL in logFiles where fileURL.pathExtension == "log" {
                let attributes = try fileURL.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = attributes.creationDate, creationDate < thirtyDaysAgo {
                    try fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            print("Failed to cleanup old logs: \(error)")
        }
    }
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        let logEntry = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)"
        
        // Safely log to os_log with proper string handling
        let safeMessage = String(message.prefix(1000)) // Limit message length to prevent decode errors
        os_log("%{public}@", log: osLog, type: level.osLogType, "[\(level.rawValue)] [\(fileName):\(line)] \(function) - \(safeMessage)")
        
        logQueue.async { [weak self] in
            self?.writeToFile(logEntry)
        }
    }
    
    private func writeToFile(_ entry: String) {
        guard let logFileURL = logFileURL else { return }
        
        let logLine = entry + "\n"
        
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            do {
                let fileHandle = try FileHandle(forWritingTo: logFileURL)
                fileHandle.seekToEndOfFile()
                fileHandle.write(logLine.data(using: .utf8) ?? Data())
                fileHandle.closeFile()
            } catch {
                print("Failed to append to log file: \(error)")
            }
        } else {
            do {
                try logLine.write(to: logFileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to create log file: \(error)")
            }
        }
    }
    
    func logDeviceEvent(_ event: String, deviceName: String) {
        log("Device Event - \(event): \(deviceName)", level: .info)
    }
    
    func logTransferOperation(_ operation: String, details: String = "") {
        let message = details.isEmpty ? "Transfer - \(operation)" : "Transfer - \(operation): \(details)"
        log(message, level: .info)
    }
    
    func logConfigurationChange(_ change: String) {
        log("Configuration - \(change)", level: .info)
    }
    
    func logSystemEvent(_ event: String) {
        log("System - \(event)", level: .info)
    }
}

extension DateFormatter {
    static let logFileName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}