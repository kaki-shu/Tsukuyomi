import Foundation
import Observation

struct LogEntry: Identifiable, Codable {
    enum Category: String, Codable, CaseIterable {
        case app
        case lifecycle
        case ui
        case rss
        case ai
        case media
        case storage
        case network
        case warning
    }

    var id: UUID = UUID()
    var timestamp: Date
    var category: Category
    var message: String
}

@Observable
final class AppLogger {
    private(set) var entries: [LogEntry] = []
    private(set) var currentSessionID: String = ""
    private(set) var currentLogURL: URL?

    private let fileManager = FileManager.default

    func bootstrapExistingLogs() {
        do {
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create logs directory: \(error)")
        }
    }

    func refreshCaptureSession() {
        bootstrapExistingLogs()
        entries.removeAll()
        currentSessionID = Self.timestampFormatter.string(from: .now)
        currentLogURL = logsDirectory.appending(path: "log-\(currentSessionID).txt")
        let header = """
        Tsukuyomi Session Log
        version: \(AppBuild.version)
        build: \(AppBuild.build)
        bundle: \(AppBuild.bundleIdentifier)
        openedAt: \(ISO8601DateFormatter().string(from: .now))

        """
        do {
            try header.write(to: currentLogURL!, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to initialize log file: \(error)")
        }
        log("Refreshed log capture session \(currentSessionID)", category: .app)
    }

    func log(_ message: String, category: LogEntry.Category) {
        let entry = LogEntry(timestamp: .now, category: category, message: message)
        entries.insert(entry, at: 0)
        append(entry)
    }

    func logUI(_ message: String) {
        log(message, category: .ui)
    }

    func logLifecycle(_ message: String) {
        log(message, category: .lifecycle)
    }

    func logWarning(_ message: String) {
        log(message, category: .warning)
    }

    @discardableResult
    func logRequestStart(method: String, url: URL, context: String, bodyBytes: Int? = nil) -> Date {
        let bodyFragment = bodyBytes.map { ", body=\($0)b" } ?? ""
        log("Request started [\(context)] \(method) \(url.absoluteString)\(bodyFragment)", category: .network)
        return .now
    }

    func logResponse(
        method: String,
        url: URL,
        context: String,
        startedAt: Date,
        response: URLResponse?,
        dataSize: Int? = nil,
        error: Error? = nil
    ) {
        let elapsed = Date.now.timeIntervalSince(startedAt)
        if let error {
            log("Request failed [\(context)] \(method) \(url.absoluteString), elapsed=\(Self.durationString(from: elapsed)), error=\(error.localizedDescription)", category: .network)
            return
        }
        let status = (response as? HTTPURLResponse).map { String($0.statusCode) } ?? "-"
        let bytes = dataSize.map { "\($0)b" } ?? "-"
        log("Response received [\(context)] \(method) \(url.absoluteString), status=\(status), bytes=\(bytes), elapsed=\(Self.durationString(from: elapsed))", category: .network)
    }

    func exportCurrentLog() -> URL? {
        currentLogURL
    }

    func clearAllLogs() {
        do {
            let urls = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
            for url in urls where url.lastPathComponent.hasPrefix("log-") {
                try? fileManager.removeItem(at: url)
            }
            refreshCaptureSession()
            log("Cleared previous logs from disk", category: .storage)
        } catch {
            log("Failed to clear logs: \(error.localizedDescription)", category: .storage)
        }
    }

    private func append(_ entry: LogEntry) {
        guard let currentLogURL else { return }
        let line = "[\(Self.fileLineFormatter.string(from: entry.timestamp))] [\(entry.category.rawValue.uppercased())] \(entry.message)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: currentLogURL) {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    print("Failed writing log: \(error)")
                }
            } else {
                try? data.write(to: currentLogURL)
            }
        }
    }

    private var logsDirectory: URL {
        let root = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return root.appending(path: "Logs", directoryHint: .isDirectory)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()

    private static let fileLineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static func durationString(from interval: TimeInterval) -> String {
        let milliseconds = Int((interval * 1000).rounded())
        return "\(milliseconds)ms"
    }
}
