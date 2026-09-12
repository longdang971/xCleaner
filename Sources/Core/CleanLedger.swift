import Foundation
import Combine

/// Cộng dồn dung lượng xCleaner đã dọn được từ trước tới nay.
///
/// Con số này nằm dưới sidebar, cạnh vòng ổ đĩa: ổ đĩa nói tình trạng hiện tại, còn đây nói
/// app đã làm được gì cho người dùng. Nó chỉ là một con số cộng dồn nên không cần cấu trúc gì
/// phức tạp — mỗi lần dọn xong thì cộng thêm đúng phần đã báo ở màn kết quả.
///
/// Mục đi vào Thùng rác cũng được tính, đúng như con số "đã giải phóng" của màn dọn xong:
/// đếm hai kiểu khác nhau ở hai chỗ chỉ làm người dùng tưởng app nói dối.
@MainActor
final class CleanLedger: ObservableObject {

    static let shared = CleanLedger()

    private let key = "lifetimeFreedBytes"

    @Published private(set) var totalFreed: Int64

    private init() {
        totalFreed = Int64(UserDefaults.standard.integer(forKey: key))
    }

    /// Gọi sau mỗi lần dọn, với đúng con số đã báo cho người dùng.
    func record(_ bytes: Int64) {
        guard bytes > 0 else { return }
        totalFreed += bytes
        UserDefaults.standard.set(totalFreed, forKey: key)
    }

    func reset() {
        totalFreed = 0
        UserDefaults.standard.removeObject(forKey: key)
    }
}
