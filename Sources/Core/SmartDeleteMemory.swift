import Foundation

/// Nhớ những ứng dụng KHÔNG được hỏi lại "có dọn tàn dư không".
///
/// Khoá theo **bundle id** chứ không theo đường dẫn: app bị gỡ từ `/Applications` nhưng lúc
/// watcher nhìn thấy nó thì nó đã nằm ở `~/.Trash/Tên.app` — đường dẫn không còn khớp nữa.
///
/// Hai chỗ ghi vào: mục "Gỡ ứng dụng" của chính xCleaner (gỡ xong mà lại bị chính mình hỏi là
/// vô duyên), và lúc người dùng đóng cửa sổ nổi (họ đã trả lời một lần rồi).
final class SmartDeleteMemory {

    static let shared = SmartDeleteMemory(storageKey: "smartDeleteSuppressed")

    /// Hết hạn sau một ngày. Xoá nhầm rồi bỏ lại vào máy, hôm sau xoá lần nữa thì vẫn nên được hỏi.
    static let ttl: TimeInterval = 24 * 60 * 60

    private let storageKey: String
    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    init(storageKey: String) { self.storageKey = storageKey }

    private var table: [String: Double] {
        get { defaults.dictionary(forKey: storageKey) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: storageKey) }
    }

    func suppress(bundleID: String) { stamp(bundleID: bundleID, at: Date()) }

    func stamp(bundleID: String, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        var t = table
        t[bundleID.lowercased()] = date.timeIntervalSince1970
        // Dọn luôn mục quá hạn để bảng không phình ra mãi.
        let cutoff = Date().addingTimeInterval(-Self.ttl).timeIntervalSince1970
        t = t.filter { $0.value >= cutoff }
        table = t
    }

    func isSuppressed(bundleID: String) -> Bool {
        // Người dùng xoá chính xCleaner thì không có gì để mời chào.
        if let own = Bundle.main.bundleIdentifier,
           own.compare(bundleID, options: .caseInsensitive) == .orderedSame { return true }
        lock.lock(); defer { lock.unlock() }
        guard let at = table[bundleID.lowercased()] else { return false }
        return Date().timeIntervalSince1970 - at < Self.ttl
    }

    func forget(bundleID: String) {
        lock.lock(); defer { lock.unlock() }
        var t = table
        t.removeValue(forKey: bundleID.lowercased())
        table = t
    }

    func forgetAll() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: storageKey)
    }
}
