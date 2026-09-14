import Foundation

/// Những đường dẫn đã tự chứng minh là xCleaner không đụng tới được.
///
/// Có những thứ nằm trong vùng macOS khoá cứng: đã chạy bằng quyền quản trị mà `rm` vẫn
/// không xoá nổi, lần sau chạy lại cũng vậy. Đưa chúng vào danh sách dọn chỉ tạo ra một
/// con số "còn N mục không xoá được" mà người dùng chẳng làm gì được với nó — nên lần quét
/// sau bỏ qua luôn.
///
/// Chỉ ghi khi **đã thử thật và thất bại dù có quyền**. Huỷ hộp mật khẩu hay bấm dừng giữa
/// chừng thì không tính: những mục đó xoá được, chỉ là lần này người dùng không cho xoá.
final class UndeletableMemory {

    static let shared = UndeletableMemory()

    private let defaultsKey = "undeletablePaths.v1"
    /// Danh sách này chỉ đúng với mức quyền lúc ghi nó.
    private let accessKey = "undeletableRecordedWithFullDisk"
    private let lock = NSLock()
    private var paths: Set<String>

    private init() {
        paths = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return paths.count
    }

    private func key(for url: URL) -> String { SafetyGuard.standardized(url).path }

    /// Mục này vừa thất bại dù đã có quyền quản trị — đừng mời người dùng dọn nó nữa.
    func record(_ url: URL) {
        let k = key(for: url)
        lock.lock()
        let inserted = paths.insert(k).inserted
        let snapshot = paths
        lock.unlock()
        guard inserted else { return }
        UserDefaults.standard.set(Array(snapshot), forKey: defaultsKey)
    }

    func contains(_ url: URL) -> Bool {
        let k = key(for: url)
        lock.lock(); defer { lock.unlock() }
        return paths.contains(k)
    }

    /// Dọn lại danh sách trước mỗi lần quét.
    ///
    /// Hai lý do phải quên: mục không còn trên đĩa nữa, và **mức quyền của app đã đổi**. Phần
    /// lớn thứ "không xoá nổi" là do chưa có Toàn quyền truy cập đĩa; người dùng cấp quyền
    /// xong mà danh sách đen vẫn giữ thì những mục ấy biến mất khỏi mọi lần quét sau, dù giờ
    /// đã dọn được.
    func refresh() {
        forgetIfAccessChanged()
        forgetMissing()
    }

    private func forgetIfAccessChanged() {
        let now = FileUtils.hasFullDiskAccess
        let defaults = UserDefaults.standard
        let before = defaults.object(forKey: accessKey) as? Bool
        guard before != now else { return }
        defaults.set(now, forKey: accessKey)
        guard before != nil else { return }   // lần đầu thì chưa có gì để quên
        forgetAll()
    }

    /// Mục đã biến mất (người dùng tự xoá tay, hoặc macOS dọn hộ) thì quên nó đi, để lần sau
    /// một mục mới trùng tên không bị bỏ sót oan.
    func forgetMissing() {
        lock.lock()
        let snapshot = paths
        lock.unlock()
        // Chỉ quên thứ chắc chắn đã mất; không được nhìn thì chưa chắc.
        let alive = snapshot.filter { !FileUtils.isGone(URL(fileURLWithPath: $0)) }
        guard alive.count != snapshot.count else { return }
        lock.lock(); paths = alive; lock.unlock()
        UserDefaults.standard.set(Array(alive), forKey: defaultsKey)
    }

    func forgetAll() {
        lock.lock(); paths.removeAll(); lock.unlock()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
