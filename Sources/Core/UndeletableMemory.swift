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

    /// Mục đã biến mất (người dùng tự xoá tay, hoặc macOS dọn hộ) thì quên nó đi, để lần sau
    /// một mục mới trùng tên không bị bỏ sót oan.
    func forgetMissing() {
        lock.lock()
        let snapshot = paths
        lock.unlock()
        let alive = snapshot.filter { FileManager.default.fileExists(atPath: $0) }
        guard alive.count != snapshot.count else { return }
        lock.lock(); paths = alive; lock.unlock()
        UserDefaults.standard.set(Array(alive), forKey: defaultsKey)
    }

    func forgetAll() {
        lock.lock(); paths.removeAll(); lock.unlock()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
