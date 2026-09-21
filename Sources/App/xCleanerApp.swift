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
                // Chiều cao nhỏ nhất kéo được. 660 là con số từ hồi nội dung còn dùng trọn cửa sổ;
                // nay đáy chừa 100pt trong suốt cho nút tròn nên ở 660 phần nội dung chỉ còn
                // 560pt, chật.
                .frame(minWidth: 980, minHeight: 720)
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
            // Cửa sổ mặc định không gửi sự kiện "chuột vừa đi qua"; không bật thì cái cổng
            // dưới đây mù một nửa (chỉ thấy đường ra, không thấy đường vào).
            w.acceptsMouseMovedEvents = true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Mắc cái cổng chuột vào cửa sổ, và bảo nó trang đang xem có nút tròn hay không.
struct BottomStripGate: NSViewRepresentable {
    /// Trang đang xem có nút tròn ở đáy hay không. Không có thì cả dải đều cho bấm xuyên qua.
    var hasButton: Bool

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: v.window)
            context.coordinator.hasButton = hasButton
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.window == nil { context.coordinator.attach(to: nsView.window) }
        context.coordinator.hasButton = hasButton
    }

    func makeCoordinator() -> BottomStripMouseGate { BottomStripMouseGate() }

    static func dismantleNSView(_ nsView: NSView, coordinator: BottomStripMouseGate) {
        coordinator.detach()
    }
}

/// Dải trong suốt ở đáy cửa sổ **vẫn là cửa sổ**: bấm vào đó macOS vẫn tính là bấm vào xCleaner,
/// nên app nằm sau không được đưa lên. Mắt thấy desktop, tay bấm thì không qua được — đọc ra
/// đúng như app đang lỗi.
///
/// Đã đo bằng CGEvent: đưa xCleaner lên trước rồi bấm vào giữa dải (xa nút) — app đứng trước vẫn
/// là xCleaner; bấm ra ngoài khung cửa sổ cùng độ cao ấy — Chrome lên ngay. Tức là cửa sổ nuốt
/// cú bấm chứ không phải máy không nhận.
///
/// macOS không có API "khoét lỗ" cho cửa sổ: thứ duy nhất có là `ignoresMouseEvents`, và nó áp
/// cho CẢ cửa sổ. Nên cách duy nhất là bám theo con trỏ — vào vùng chết thì bật cờ, ra thì tắt.
/// Lúc cờ đang bật, cửa sổ không nhận chuột nữa nên tin "con trỏ đã đi ra" chỉ về qua monitor
/// TOÀN CỤC (sự kiện lúc ấy thuộc về app khác); chỉ có monitor cục bộ là không bao giờ thoát ra
/// được nữa.
///
/// Vùng sống trong dải chỉ đúng bằng cái nút tròn, KHÔNG tính quầng sáng: quầng là ánh sáng của
/// nút hắt ra chứ không phải chỗ bấm được, và nó loang gần hết dải.
final class BottomStripMouseGate {
    private(set) weak var window: NSWindow?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    var hasButton: Bool = true { didSet { if hasButton != oldValue { update() } } }

    /// Bán kính vùng còn bấm được quanh tâm nút: nửa nút (42) cộng 2pt cho mép.
    static let liveRadius: CGFloat = 44

    func attach(to window: NSWindow?) {
        guard let window, self.window !== window else { return }
        detach()
        self.window = window

        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                            .leftMouseUp, .rightMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { [weak self] _ in
            self?.update()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { [weak self] e in
            self?.update(); return e
        }) { monitors.append(m) }

        // Cửa sổ tự dịch chỗ dưới một con trỏ đang đứng yên thì không có sự kiện chuột nào bắn ra.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main) { [weak self] _ in self?.update() })
        }
        update()
    }

    func detach() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        window?.ignoresMouseEvents = false
        window = nil
    }

    private func update() {
        guard let w = window, w.isVisible else { return }
        // Đang giữ chuột thì đừng đổi gì: kéo cửa sổ bằng thân cửa sổ mà giữa chừng cửa sổ thôi
        // nhận chuột là cú kéo đứt ngang.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let dead = isDead(NSEvent.mouseLocation, in: w)
        if w.ignoresMouseEvents != dead { w.ignoresMouseEvents = dead }
    }

    private func isDead(_ point: CGPoint, in w: NSWindow) -> Bool {
        // Toàn màn hình thì không còn dải trống nào — `RootView` cũng hạ `bottomInset` về 0.
        guard !w.styleMask.contains(.fullScreen) else { return false }
        return Self.isDeadZone(point, windowFrame: w.frame, hasButton: hasButton)
    }

    /// `point` và `windowFrame` theo toạ độ màn hình của AppKit: gốc ở góc DƯỚI-trái, y hướng lên.
    static func isDeadZone(_ point: CGPoint, windowFrame frame: CGRect, hasButton: Bool) -> Bool {
        guard frame.contains(point) else { return false }

        // Mép dưới tấm nền. Dưới nó là dải trong suốt.
        let cardBottom = frame.minY + Metrics.windowBottomInset
        guard point.y < cardBottom else { return false }

        guard hasButton else { return true }

        // Nút căn giữa VÙNG NỘI DUNG (đã bị sidebar ăn mất 76pt bên trái), và tâm nó nằm cao hơn
        // mép tấm nền 16pt — nút cao 84, thò xuống 26.
        let center = CGPoint(x: frame.midX + Metrics.sidebarWidth / 2, y: cardBottom + 16)
        return hypot(point.x - center.x, point.y - center.y) > liveRadius
    }
}
