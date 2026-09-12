import Foundation
import AppKit
import CoreServices

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
        // KHÔNG dùng `.skipsPackageDescendants`: app nào cũng nhét helper dạng `.app` vào
        // bên trong mình (Chrome, Xcode…), bỏ qua ruột chúng là báo thiếu phần lớn dung lượng.
        guard let e = fm.enumerator(at: url,
                                    includingPropertiesForKeys: Array(sizeKeys),
                                    options: [],
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

    /// macOS chặn đọc một số thư mục (Thùng rác, dữ liệu Safari, Mail…) khi app chưa được cấp
    /// Toàn quyền truy cập đĩa. Khi đó `contentsOfDirectory` ném lỗi chứ không trả mảng rỗng —
    /// phân biệt được hai trường hợp này mới báo đúng cho người dùng.
    enum DirectoryState { case missing, blocked, empty, hasItems }

    static func directoryState(_ url: URL) -> DirectoryState {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return .missing
        }
        do {
            let items = try fm.contentsOfDirectory(atPath: url.path)
            return items.contains { !$0.hasPrefix(".") } ? .hasItems : .empty
        } catch {
            let ns = error as NSError
            let underlying = ns.underlyingErrors.first as NSError?
            let denied = ns.code == NSFileReadNoPermissionError
                || underlying?.code == Int(EPERM)
                || underlying?.code == Int(EACCES)
            return denied ? .blocked : .empty
        }
    }

    static func children(of url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url,
                                     includingPropertiesForKeys: Array(sizeKeys),
                                     options: [])) ?? []
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Lần cuối người dùng thật sự mở thứ này.
    ///
    /// Không dùng `contentAccessDate` (atime): với một bundle `.app` nó đổi khi Spotlight hay
    /// bản sao lưu quét qua, chứ không phải khi người dùng chạy app — đo trên máy thật thì
    /// AppCleaner báo năm 2023 trong khi thực tế vừa mở tuần trước. Thứ đúng là
    /// `kMDItemLastUsedDate` của Spotlight, chính là con số Finder hiển thị ở cột "Lần mở cuối".
    static func lastUsedDate(of url: URL) -> Date? {
        if let item = MDItemCreate(nil, url.path as CFString),
           let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return used
        }
        // Spotlight bị tắt cho ổ đĩa này thì đành quay về ngày sửa đổi.
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey,
                                                  .contentAccessDateKey])
        return v?.contentModificationDate ?? v?.contentAccessDate
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
