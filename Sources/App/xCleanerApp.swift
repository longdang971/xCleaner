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
        .defaultSize(width: 1140, height: 760)
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
            w.backgroundColor = NSColor(hex: "#101219")
            w.standardWindowButton(.zoomButton)?.isEnabled = true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
