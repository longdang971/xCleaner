import Foundation

/// Tìm những tệp đang chiếm nhiều chỗ nhất và những tệp lâu rồi không đụng tới.
struct LargeOldScanner {

    struct Options {
        var roots: [URL] = [FileUtils.home]
        var minimumSize: Int64 = 50 * 1024 * 1024      // 50 MB
        var oldAfterDays: Int = 180
        var maxResults: Int = 500
    }

    struct Found: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let size: Int64
        let modified: Date?
        let accessed: Date?
        let kind: String

        var isOld: Bool {
            guard let d = accessed ?? modified else { return false }
            return Date().timeIntervalSince(d) > 180 * 86_400
        }

        static func == (l: Found, r: Found) -> Bool { l.url == r.url }
        func hash(into h: inout Hasher) { h.combine(url) }
    }

    /// Không đi vào những nhánh vừa vô nghĩa vừa làm chậm quá trình quét.
    private static let skipNames: Set<String> = [
        "Library", ".Trash", "node_modules", ".git", "Photos Library.photoslibrary",
        ".build", "DerivedData", ".venv", "venv", "__pycache__", ".npm", ".cache",
        "Applications", ".docker", ".cocoapods", ".gradle", ".rustup", ".cargo"
    ]

    func scan(options: Options, cancel: CancelToken,
              progress: @escaping (ScanProgress) -> Void) -> [Found] {
        var results: [Found] = []
        var scanned = 0
        var totalBytes: Int64 = 0

        for root in options.roots {
            if cancel.isCancelled { break }
            guard let e = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
                                             .totalFileAllocatedSizeKey, .fileSizeKey,
                                             .contentModificationDateKey, .contentAccessDateKey,
                                             .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }) else { continue }

            for case let url as URL in e {
                if cancel.isCancelled { break }
                scanned += 1

                let name = url.lastPathComponent
                if Self.skipNames.contains(name) {
                    e.skipDescendants()
                    continue
                }

                if scanned % 400 == 0 {
                    progress(ScanProgress(fraction: min(0.95, Double(scanned) / 120_000),
                                          message: FileUtils.prettyPath(url.deletingLastPathComponent()),
                                          bytesFound: totalBytes))
                }

                guard let v = try? url.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
                    .totalFileAllocatedSizeKey, .fileSizeKey,
                    .contentModificationDateKey, .contentAccessDateKey]) else { continue }
                if v.isSymbolicLink == true { continue }

                // Gói (.app, .photoslibrary…) tính như một khối, không đi vào trong.
                let isPackage = v.isPackage == true
                let isFile = v.isRegularFile == true
                guard isFile || isPackage else { continue }

                let size: Int64 = isPackage
                    ? FileUtils.directorySize(url, isCancelled: { cancel.isCancelled })
                    : Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
                guard size >= options.minimumSize else { continue }

                totalBytes += size
                results.append(Found(url: url, size: size,
                                     modified: v.contentModificationDate,
                                     accessed: v.contentAccessDate,
                                     kind: kindName(for: url, isPackage: isPackage)))

                // Giữ danh sách gọn: khi quá dài thì cắt bớt phần nhỏ nhất.
                if results.count > options.maxResults * 2 {
                    results.sort { $0.size > $1.size }
                    results.removeLast(results.count - options.maxResults)
                }
            }
        }

        results.sort { $0.size > $1.size }
        if results.count > options.maxResults { results.removeLast(results.count - options.maxResults) }
        progress(ScanProgress(fraction: 1, message: "Xong", bytesFound: totalBytes))
        return results
    }

    private func kindName(for url: URL, isPackage: Bool) -> String {
        if isPackage { return url.pathExtension == "app" ? "Ứng dụng" : "Gói" }
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm": return "Video"
        case "zip", "dmg", "pkg", "tar", "gz", "7z", "rar", "iso": return "Nén / bộ cài"
        case "psd", "ai", "sketch", "fig", "xcf":       return "Thiết kế"
        case "jpg", "jpeg", "png", "heic", "tiff", "raw", "cr2", "arw": return "Hình ảnh"
        case "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx": return "Tài liệu"
        case "sqlite", "db", "sql":                      return "Cơ sở dữ liệu"
        case "wav", "aiff", "mp3", "m4a", "flac":        return "Âm thanh"
        default:                                         return "Tệp"
        }
    }
}
