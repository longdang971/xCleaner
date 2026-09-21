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
        // Bundle của chính mình không còn: người dùng đã xoá xCleaner trong lúc nó không chạy.
        // Gỡ agent rồi thoát, không thì lần đăng nhập sau launchd còn cố dựng một binary đã mất.
        if !FileUtils.exists(Bundle.main.bundleURL) {
            LaunchAgentInstaller.uninstall()
            NSApp.terminate(nil)
            return
        }
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
        // Người dùng vừa tắt công tắc, mà luồng sự kiện còn một nhịp đang bay tới. Không chặn ở
        // đây thì tắt xong vẫn ăn thêm một bảng.
        guard Self.isOn else { return }

        // Người dùng vừa kéo CHÍNH xCleaner vào Thùng rác.
        //
        // Đây là lỗi đã thấy tận mắt ở AppCleaner: xoá app rồi mà cái helper SmartDelete của nó
        // vẫn nằm trong RAM và vẫn bật hộp thoại lên mỗi lần xoá app khác, vì xoá tệp không giết
        // tiến trình đang chạy. Nên tự dọn: gỡ agent rồi thoát ngay, đừng để lại một cái bóng.
        //
        // Nhưng phải chắc đó là BẢN ĐANG CHẠY. Cùng bundle id thì một bản sao để ở Tải về hay ổ
        // ngoài cũng khớp, mà xoá bản sao ấy thì bản đang chạy chẳng việc gì phải thoát.
        if apps.contains(where: Self.isSelf),
           Self.shouldQuitAfterSelfTrashed(runningBundleExists: FileUtils.exists(Bundle.main.bundleURL)) {
            LaunchAgentInstaller.uninstall()
            NSApp.terminate(nil)
            return
        }
        for a in apps where !SmartDeleteMemory.shared.isSuppressed(bundleID: a.bundleID) {
            queue.append(a)
        }
        pump()
    }

    /// Bản xCleaner đang chạy có thật sự vừa bị xoá không — hay chỉ là một bản sao cùng bundle id.
    nonisolated static func shouldQuitAfterSelfTrashed(runningBundleExists: Bool) -> Bool {
        !runningBundleExists
    }

    /// App vừa vào Thùng rác có phải chính xCleaner không.
    static func isSelf(_ app: TrashedApp) -> Bool {
        guard let own = Bundle.main.bundleIdentifier else { return false }
        return own.compare(app.bundleID, options: .caseInsensitive) == .orderedSame
    }

    /// Mỗi lúc một cửa sổ. Kéo ba app vào Thùng rác một lượt thì hỏi lần lượt ba lần.
    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        // Lọc lại lúc LẤY RA, không chỉ lúc xếp vào: cùng một app có thể vào hàng đợi hai lần
        // (bỏ ra khỏi Thùng rác rồi xoá lại) trước khi người dùng kịp trả lời lần đầu. Chỉ lọc
        // lúc xếp vào thì họ đóng bảng xong lại bị hỏi y hệt một lần nữa.
        guard !SmartDeleteMemory.shared.isSuppressed(bundleID: next.bundleID) else {
            pump()
            return
        }
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
        DispatchQueue.global(qos: .userInitiated).async {
            let all = UninstallScanner().leftovers(for: installed, cancel: CancelToken())
            let items = Self.leftoversToShow(all, bundle: app.url)
            DispatchQueue.main.async { done(items) }
        }
    }

    // MARK: - Phần thuần

    nonisolated static func installedApp(from t: TrashedApp) -> UninstallScanner.InstalledApp {
        UninstallScanner.InstalledApp(id: t.bundleID, name: t.name, url: t.url,
                                      version: t.version, appSize: 0, leftoverSize: 0,
                                      lastUsed: nil, isSystemApp: false, needsAdmin: false)
    }

    /// Bỏ chính bundle ra khỏi danh sách: nó đã nằm trong Thùng rác rồi, dọn nữa là thừa — và
    /// đưa nó lên danh sách tick được thì con số "đã dọn" sẽ cộng cả dung lượng app vào.
    nonisolated static func leftoversToShow(_ items: [CleanItem], bundle: URL) -> [CleanItem] {
        items.filter { $0.url.standardizedFileURL != bundle.standardizedFileURL }
    }
}
