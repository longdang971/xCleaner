import AppKit
import SwiftUI

/// Nối tai nghe Thùng rác với bộ quét tàn dư và cửa sổ nổi.
///
/// Đây là toàn bộ phần "thông minh" của chức năng: lọc những app không được hỏi lại, dựng dữ liệu
/// app từ bundle đang nằm trong Thùng rác, gọi lại đúng bộ quét của mục "Gỡ ứng dụng" (không viết
/// lại), rồi xếp hàng để mỗi lúc chỉ có một cửa sổ.
@MainActor
final class SmartDeleteController {

    static let shared = SmartDeleteController()

    private var watcher: TrashWatcher?
    private var queue: [TrashedApp] = []
    private var busy = false

    private init() {}

    /// Đọc công tắc trong Cài đặt rồi bật/tắt cho khớp. Gọi lúc khởi động và mỗi lần người dùng
    /// gạt công tắc.
    func applySetting() {
        if Self.isOn {
            LaunchAgentInstaller.install()
            guard watcher == nil else { return }
            let w = TrashWatcher { [weak self] apps in self?.enqueue(apps) }
            w.start()
            watcher = w
        } else {
            LaunchAgentInstaller.uninstall()
            watcher?.stop()
            watcher = nil
            queue.removeAll()
        }
    }

    /// Mặc định BẬT, nên phải hỏi `object(forKey:)` chứ không phải `bool(forKey:)` —
    /// `bool(forKey:)` trả `false` khi khoá chưa tồn tại, tức là máy nào chưa từng vào Cài đặt
    /// thì chức năng không bao giờ chạy.
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: "smartDelete") as? Bool ?? true
    }

    private func enqueue(_ apps: [TrashedApp]) {
        for a in apps where !SmartDeleteMemory.shared.isSuppressed(bundleID: a.bundleID) {
            queue.append(a)
        }
        pump()
    }

    /// Mỗi lúc một cửa sổ. Kéo ba app vào Thùng rác một lượt thì hỏi lần lượt ba lần.
    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        busy = true
        scan(next) { [weak self] items in
            guard let self else { return }
            guard !items.isEmpty, FileUtils.exists(next.url) else {
                // Không còn gì để dọn, hoặc người dùng đã bấm "Put Back" / đổ Thùng rác trong lúc
                // quét. Im lặng: họ không yêu cầu gì cả, đừng bật cửa sổ lên để khoe.
                self.finish()
                return
            }
            LeftoverPanel.show(app: next, items: items) { [weak self] in
                SmartDeleteMemory.shared.suppress(bundleID: next.bundleID)
                self?.finish()
            }
        }
    }

    private func finish() {
        busy = false
        pump()
    }

    private func scan(_ app: TrashedApp, done: @escaping ([CleanItem]) -> Void) {
        let installed = Self.installedApp(from: app)
        let token = CancelToken()
        DispatchQueue.global(qos: .userInitiated).async {
            let all = UninstallScanner().leftovers(for: installed, cancel: token)
            let items = Self.leftoversToShow(all, bundle: app.url)
            DispatchQueue.main.async { done(items) }
        }
    }

    // MARK: - Phần thuần

    static func installedApp(from t: TrashedApp) -> UninstallScanner.InstalledApp {
        UninstallScanner.InstalledApp(id: t.bundleID, name: t.name, url: t.url,
                                      version: t.version, appSize: 0, leftoverSize: 0,
                                      lastUsed: nil, isSystemApp: false, needsAdmin: false)
    }

    /// Bỏ chính bundle ra khỏi danh sách: nó đã nằm trong Thùng rác rồi, dọn nữa là thừa — và
    /// đưa nó lên danh sách tick được thì con số "đã dọn" sẽ cộng cả dung lượng app vào.
    static func leftoversToShow(_ items: [CleanItem], bundle: URL) -> [CleanItem] {
        items.filter { $0.url.standardizedFileURL != bundle.standardizedFileURL }
    }
}
