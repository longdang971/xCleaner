import Foundation
import CryptoKit

/// Tìm tệp trùng lặp theo nội dung thật, không dựa vào tên.
///
/// Ba vòng lọc để không phải băm cả ổ đĩa:
/// 1. Gom theo kích thước — tệp khác cỡ thì chắc chắn khác nhau.
/// 2. Băm 8 KB đầu + 8 KB cuối.
/// 3. Băm toàn bộ bằng SHA-256 đọc theo khối 1 MB.
struct DuplicateScanner {

    struct Options {
        var roots: [URL] = [FileUtils.homePath("Documents"),
                            FileUtils.homePath("Downloads"),
                            FileUtils.homePath("Desktop"),
                            FileUtils.homePath("Pictures"),
                            FileUtils.homePath("Movies")]
        var minimumSize: Int64 = 1024 * 1024   // 1 MB
    }

    struct DuplicateSet: Identifiable {
        let id = UUID()
        var files: [URL]
        var size: Int64          // dung lượng mỗi tệp
        var kind: String

        /// Chỗ lấy lại được nếu chỉ giữ một bản.
        var reclaimable: Int64 { size * Int64(max(0, files.count - 1)) }
    }

    private static let skipNames: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", "Library",
        "__pycache__", ".venv", "venv", ".Trash"
    ]

    func scan(options: Options, cancel: CancelToken,
              progress: @escaping (ScanProgress) -> Void) -> [DuplicateSet] {

        // --- Vòng 1: gom theo kích thước ---
        progress(ScanProgress(fraction: 0.05, message: "Đang lập danh sách tệp…"))
        var bySize: [Int64: [URL]] = [:]
        var counted = 0

        for root in options.roots {
            if cancel.isCancelled { return [] }
            guard let e = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey,
                                             .fileSizeKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }) else { continue }

            for case let url as URL in e {
                if cancel.isCancelled { return [] }
                if Self.skipNames.contains(url.lastPathComponent) { e.skipDescendants(); continue }
                guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey,
                                                                .fileSizeKey]),
                      v.isSymbolicLink != true, v.isRegularFile == true,
                      let s = v.fileSize, Int64(s) >= options.minimumSize else { continue }
                bySize[Int64(s), default: []].append(url)
                counted += 1
                if counted % 500 == 0 {
                    progress(ScanProgress(fraction: min(0.4, 0.05 + Double(counted) / 60_000),
                                          message: "Đã xem \(counted) tệp"))
                }
            }
        }

        let candidates = bySize.filter { $0.value.count > 1 }
        guard !candidates.isEmpty else {
            progress(ScanProgress(fraction: 1, message: "Không có tệp trùng"))
            return []
        }

        // --- Vòng 2: băm đầu + cuối ---
        progress(ScanProgress(fraction: 0.45, message: "Đang so khớp nhanh…"))
        var byPrefix: [String: [URL]] = [:]
        var processed = 0
        let totalCandidates = candidates.reduce(0) { $0 + $1.value.count }

        for (size, urls) in candidates {
            if cancel.isCancelled { return [] }
            for u in urls {
                processed += 1
                if processed % 40 == 0 {
                    progress(ScanProgress(fraction: 0.45 + 0.25 * Double(processed) / Double(totalCandidates),
                                          message: u.lastPathComponent))
                }
                guard let h = edgeHash(u, size: size) else { continue }
                byPrefix["\(size)-\(h)", default: []].append(u)
            }
        }

        // --- Vòng 3: băm toàn bộ ---
        progress(ScanProgress(fraction: 0.72, message: "Đang xác nhận từng byte…"))
        var byFull: [String: [URL]] = [:]
        let groups = byPrefix.filter { $0.value.count > 1 }
        var step = 0
        let totalStep = max(1, groups.reduce(0) { $0 + $1.value.count })

        for (_, urls) in groups {
            if cancel.isCancelled { return [] }
            for u in urls {
                step += 1
                if step % 10 == 0 {
                    progress(ScanProgress(fraction: 0.72 + 0.26 * Double(step) / Double(totalStep),
                                          message: u.lastPathComponent))
                }
                guard let h = fullHash(u, cancel: cancel) else { continue }
                byFull[h, default: []].append(u)
            }
        }

        var sets: [DuplicateSet] = []
        for (_, urls) in byFull where urls.count > 1 {
            let size = Int64((try? urls[0].resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            sets.append(DuplicateSet(files: urls.sorted { $0.path < $1.path },
                                     size: size,
                                     kind: urls[0].pathExtension.uppercased()))
        }
        sets.sort { $0.reclaimable > $1.reclaimable }
        progress(ScanProgress(fraction: 1, message: "Xong",
                              bytesFound: sets.reduce(0) { $0 + $1.reclaimable }))
        return sets
    }

    // MARK: - Băm

    private func edgeHash(_ url: URL, size: Int64) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let chunk = 8 * 1024
        var hasher = SHA256()
        if let head = try? fh.read(upToCount: chunk) { hasher.update(data: head) }
        if size > Int64(chunk * 2) {
            try? fh.seek(toOffset: UInt64(size - Int64(chunk)))
            if let tail = try? fh.readToEnd() { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func fullHash(_ url: URL, cancel: CancelToken) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        while true {
            if cancel.isCancelled { return nil }
            guard let data = try? fh.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
