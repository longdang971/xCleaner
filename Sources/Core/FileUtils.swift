import Foundation
import AppKit

enum FileUtils {
    static let fm = FileManager.default

    static let sizeKeys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey
    ]

    /// Dung lượng thực chiếm trên đĩa của một tệp.
    static func allocatedSize(of url: URL) -> Int64 {
        guard let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey,
                                                        .fileAllocatedSizeKey, .fileSizeKey]) else { return 0 }
        if let s = v.totalFileAllocatedSize { return Int64(s) }
        if let s = v.fileAllocatedSize { return Int64(s) }
        if let s = v.fileSize { return Int64(s) }
        return 0
    }

    /// Tổng dung lượng của một thư mục (đệ quy, không đi theo symlink).
    /// `isCancelled` được hỏi định kỳ để dừng sớm khi người dùng huỷ quét.
    static func directorySize(_ url: URL, isCancelled: () -> Bool = { false }) -> Int64 {
        var total: Int64 = 0
        var counter = 0
        guard let e = fm.enumerator(at: url,
                                    includingPropertiesForKeys: Array(sizeKeys),
                                    options: [.skipsPackageDescendants],
                                    errorHandler: { _, _ in true }) else { return 0 }
        for case let child as URL in e {
            counter += 1
            if counter & 0x3FF == 0 && isCancelled() { return total }
            let v = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey,
                                                        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                                        .fileSizeKey])
            if v?.isSymbolicLink == true { continue }
            guard v?.isRegularFile == true else { continue }
            if let s = v?.totalFileAllocatedSize { total += Int64(s) }
            else if let s = v?.fileAllocatedSize { total += Int64(s) }
            else if let s = v?.fileSize { total += Int64(s) }
        }
        return total
    }

    /// Dung lượng của một mục bất kỳ (tệp hay thư mục).
    static func size(of url: URL, isCancelled: () -> Bool = { false }) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if v?.isSymbolicLink == true { return 0 }
        if v?.isDirectory == true { return directorySize(url, isCancelled: isCancelled) }
        return allocatedSize(of: url)
    }

    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }

    static func children(of url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url,
                                     includingPropertiesForKeys: Array(sizeKeys),
                                     options: [])) ?? []
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func lastUsedDate(of url: URL) -> Date? {
        let v = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
        return v?.contentAccessDate ?? v?.contentModificationDate
    }

    static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    static func homePath(_ components: String) -> URL {
        home.appendingPathComponent(components)
    }

    /// Rút gọn `/Users/ten/Library/...` thành `~/Library/...` cho gọn khi hiển thị.
    static func prettyPath(_ url: URL) -> String {
        let h = NSHomeDirectory()
        if url.path.hasPrefix(h) { return "~" + url.path.dropFirst(h.count) }
        return url.path
    }

    /// Ổ đĩa đang gắn (dùng để tìm Thùng rác trên ổ ngoài).
    static func mountedVolumes() -> [URL] {
        fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey, .volumeIsBrowsableKey],
                             options: [.skipHiddenVolumes]) ?? []
    }

    /// Tên ứng dụng đang chạy sở hữu bundle id (để cảnh báo "hãy đóng app trước").
    static func isRunning(bundleID: String) -> Bool {
        !NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }.isEmpty
    }
}
