import Foundation

final class AppLogger {
    static let shared = AppLogger()
    private let maxSize: Int = 1_048_576 // 1 MB
    private let maxFiles = 3
    private let logURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("com.ibm.office-attendance", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("attendance.log")
    }()

    private init() {}

    func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        rotate()
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try? FileHandle(forWritingTo: logURL)
                handle?.seekToEndOfFile()
                handle?.write(data)
                handle?.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    private func rotate() {
        guard let size = try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > maxSize else { return }
        let dir = logURL.deletingLastPathComponent()
        // Shift old logs
        for i in stride(from: maxFiles - 1, through: 1, by: -1) {
            let old = dir.appendingPathComponent("attendance.\(i).log")
            let new = dir.appendingPathComponent("attendance.\(i + 1).log")
            try? FileManager.default.removeItem(at: new)
            try? FileManager.default.moveItem(at: old, to: new)
        }
        let first = dir.appendingPathComponent("attendance.1.log")
        try? FileManager.default.moveItem(at: logURL, to: first)
    }
}
