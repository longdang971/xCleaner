#if DEBUG
import AppKit

/// Chụp chính cửa sổ của app ra tệp PNG — dùng khi phát triển để xem lại bố cục
/// mà không cần cấp quyền Ghi màn hình cho Terminal.
///
///   XCLEANER_SHOT=/tmp/a.png XCLEANER_SHOT_DELAY=3 XCLEANER_SHOT_QUIT=1 open -a xCleaner
///
/// `XCLEANER_SHOT_ACTION=scan` sẽ bấm hộ nút quét trước khi chụp.
enum DebugCapture {

    static func installIfRequested() {
        let env = ProcessInfo.processInfo.environment

        // Thử đường xin quyền root mà không xoá gì cả: chỉ chạy `id -u` rồi in kết quả.
        if env["XCLEANER_TEST_AUTH"] == "1" {
            DispatchQueue.global().async {
                do {
                    let out = try AuthorizationRunner.run(
                        command: "/usr/bin/id -u; /usr/bin/stat -f '%Su' /Library/Logs",
                        prompt: "xCleaner cần quyền quản trị để dọn bộ nhớ đệm và nhật ký trong thư mục hệ thống.")
                    NSLog("[xCleaner] TEST_AUTH thành công, kết quả: %@",
                          out.trimmingCharacters(in: .whitespacesAndNewlines))
                } catch {
                    NSLog("[xCleaner] TEST_AUTH lỗi: %@", error.localizedDescription)
                }
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return
        }
        guard let path = env["XCLEANER_SHOT"] else { return }
        let delay = Double(env["XCLEANER_SHOT_DELAY"] ?? "3") ?? 3
        let shouldQuit = env["XCLEANER_SHOT_QUIT"] == "1"
        let action = env["XCLEANER_SHOT_ACTION"]

        if let mode = env["XCLEANER_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        }

        if let module = env["XCLEANER_MODULE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .xcSelectModule, object: module)
            }
        }

        if action == "scan" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NotificationCenter.default.post(name: .xcRescan, object: nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(to: path)
            if shouldQuit { NSApp.terminate(nil) }
        }
    }

    static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView else {
            NSLog("[xCleaner] DebugCapture: không tìm thấy cửa sổ")
            return
        }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            NSLog("[xCleaner] DebugCapture: đã ghi %@", path)
        } catch {
            NSLog("[xCleaner] DebugCapture lỗi: %@", error.localizedDescription)
        }
    }
}
#endif
