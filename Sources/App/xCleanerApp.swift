import SwiftUI
import AppKit

@main
struct xCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("xCleaner", id: "main") {
            RootView()
                .environmentObject(state)
                .environmentObject(state.settings)
                .frame(minWidth: 980, minHeight: 660)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        // Chiều cao phải dư ra: dải trong suốt chừa ở đáy cho nút tròn (100pt) ăn mất chừng ấy
        // chiều cao nội dung, nên thấp hơn 780 là khối minh hoạ ở màn khởi đầu bị nén sát vào nút.
        .defaultSize(width: 1140, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) { }
            // Cảnh `Settings` của SwiftUI mở cửa sổ hệ thống màu sáng, lạc hẳn với app;
            // ⌘, được nối thẳng vào bảng tuỳ chọn tự vẽ bên trong cửa sổ chính.
            CommandGroup(replacing: .appSettings) {
                Button("Cài đặt…") {
                    NotificationCenter.default.post(name: .xcOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Kiểm tra cập nhật…") {
                    NotificationCenter.default.post(name: .xcCheckUpdates, object: nil)
                }
                Button("Quét lại") {
                    NotificationCenter.default.post(name: .xcRescan, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let xcRescan = Notification.Name("xCleaner.rescan")
    static let xcSelectModule = Notification.Name("xCleaner.selectModule")
    static let xcOpenSettings = Notification.Name("xCleaner.openSettings")
    static let xcCheckUpdates = Notification.Name("xCleaner.checkUpdates")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCLEANER_SELFTEST"] == "1" {
            SelfTest.run()
            return
        }
        #endif
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        DebugCapture.installIfRequested()
        #endif
    }
}

/// Chỉnh vài thứ của NSWindow mà SwiftUI chưa lộ ra: nền trong suốt để lớp nền tự vẽ,
/// thanh tiêu đề ẩn nhưng vẫn kéo được, và tắt hiệu ứng phóng khi mở.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.animationBehavior = .none
            // Trong suốt: tấm nền bên trong tự vẽ hình dạng của mình, và dải chừa ở đáy phải
            // thật sự nhìn xuyên xuống desktop thì nút tròn thò ra mới không như bị cắt.
            w.isOpaque = false
            w.backgroundColor = .clear
            // Tắt bóng cửa sổ. macOS vẽ bóng theo KHUNG CHỮ NHẬT của cửa sổ chứ không theo hình
            // dạng thật của nội dung, nên dải trong suốt ở đáy vẫn bị một đường bóng chạy vòng
            // quanh — nhìn đúng như cửa sổ còn viền ở chỗ lẽ ra trống không. Đã thử ép tính lại
            // bằng `invalidateShadow()` sau khi nội dung đã dựng xong: bóng vẫn ôm nguyên khung
            // cũ. Chụp cửa sổ kèm framing (`XCLEANER_SHOT_FRAMING=1`) đối chiếu hai bản bật/tắt
            // thì thấy rõ, tắt đi là sạch.
            w.hasShadow = false
            w.standardWindowButton(.zoomButton)?.isEnabled = true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
