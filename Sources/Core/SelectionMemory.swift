import Foundation

/// Nhớ những chỗ người dùng đã tự tay đổi ý, để lần quét sau không phải chọn lại từ đầu.
///
/// Chỉ ghi lại **phần khác với mặc định**, không ghi toàn bộ danh sách. Nhờ vậy khi xCleaner
/// đổi đề xuất mặc định ở một bản sau (ví dụ thấy một thư mục hoá ra không an toàn),
/// những mục người dùng chưa từng đụng tới sẽ đi theo đề xuất mới chứ không mắc kẹt ở lựa chọn cũ.
///
/// Khoá là đường dẫn đã rút gọn `~`, nên đổi tên hiển thị hay quét lại đều không làm mất trí nhớ.
final class SelectionMemory {

    static let shared = SelectionMemory()

    private let defaultsKey = "selectionOverrides"
    private let lock = NSLock()
    private var overrides: [String: Bool]

    private init() {
        overrides = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Bool]) ?? [:]
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "rememberChoices") as? Bool ?? true
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return overrides.count
    }

    private func key(for item: CleanItem) -> String { FileUtils.prettyPath(item.url) }

    // MARK: - Ghi

    /// Gọi sau mỗi lần người dùng bật/tắt một mục.
    func record(_ item: CleanItem) {
        guard isEnabled else { return }
        let k = key(for: item)
        lock.lock()
        if item.isSelected == item.defaultSelected {
            // Quay về đúng đề xuất thì không còn gì để nhớ nữa.
            overrides.removeValue(forKey: k)
        } else {
            overrides[k] = item.isSelected
        }
        let snapshot = overrides
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }

    func record(_ items: [CleanItem]) {
        guard isEnabled else { return }
        lock.lock()
        for item in items {
            let k = key(for: item)
            if item.isSelected == item.defaultSelected {
                overrides.removeValue(forKey: k)
            } else {
                overrides[k] = item.isSelected
            }
        }
        let snapshot = overrides
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }

    // MARK: - Đọc

    /// Áp lại lựa chọn đã nhớ lên kết quả vừa quét.
    /// - Returns: số mục được khôi phục, để màn hình nói cho người dùng biết.
    @discardableResult
    func apply(to groups: inout [CleanGroup]) -> Int {
        guard isEnabled else { return 0 }
        lock.lock()
        let snapshot = overrides
        lock.unlock()
        guard !snapshot.isEmpty else { return 0 }

        var restored = 0
        for gi in groups.indices {
            for ii in groups[gi].items.indices {
                let k = key(for: groups[gi].items[ii])
                guard let want = snapshot[k],
                      want != groups[gi].items[ii].isSelected else { continue }
                groups[gi].items[ii].isSelected = want
                restored += 1
            }
        }
        return restored
    }

    func forgetAll() {
        lock.lock(); overrides.removeAll(); lock.unlock()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
