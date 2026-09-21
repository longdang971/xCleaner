# Kế hoạch: dọn tàn dư khi người dùng tự xoá ứng dụng (SmartDelete)

> **Cho người thực thi:** làm tuần tự từng Task. Mỗi Task kết thúc bằng một lần chạy
> `XCLEANER_SELFTEST=1` xanh và một commit.

**Goal:** Kéo/⌘⌫ một app vào Thùng rác → xCleaner (đang chạy nền, vô hình) hiện một cửa sổ nhỏ
liệt kê tàn dư của app đó để dọn.

**Architecture:** Một binary, hai chế độ (`.regular` khi có cửa sổ, `.accessory` khi chạy nền).
`TrashWatcher` (FSEvents trên `~/.Trash`) → `SmartDeleteController` (hàng đợi + quét bằng
`UninstallScanner` có sẵn) → `LeftoverPanel` (NSPanel + SwiftUI theo ngôn ngữ giao diện app).
Khởi động cùng máy bằng LaunchAgent tự ghi, **không** `SMAppService`.

**Tech Stack:** Swift 5, SwiftUI + AppKit, XcodeGen, bộ kiểm tra tự viết trong
`Sources/App/SelfTest.swift` (`XCLEANER_SELFTEST=1`).

## Global Constraints

- Đích biên dịch **macOS 14.0** — mọi API mới hơn phải bọc `if #available`.
- Bundle id: `com.pikalong.xCleaner`. Label agent: `com.pikalong.xCleaner.watcher`.
- Chỉ **một binary**; tuyệt đối không thêm helper riêng (mất quyền Toàn quyền truy cập đĩa).
- Mặc định **BẬT** (`@AppStorage("smartDelete") = true`).
- Không icon Dock, không icon thanh menu khi chạy nền.
- Mọi chữ hiện ra cho người dùng bằng **tiếng Việt**, giọng như phần còn lại của app.
- Build kiểm tra: `xcodebuild -project xCleaner.xcodeproj -scheme xCleaner -configuration Debug -derivedDataPath /tmp/xcleaner-dbg build`
- Chạy test: `XCLEANER_SELFTEST=1 /tmp/xcleaner-dbg/Build/Products/Debug/xCleaner.app/Contents/MacOS/xCleaner`
- Sau khi thêm tệp nguồn mới: `xcodegen generate` (dự án liệt kê nguồn theo thư mục nên thường tự
  bắt, nhưng chạy lại cho chắc).

---

### Task 1: `SmartDeleteMemory` — không hỏi lại hai lần

**Files:**
- Create: `Sources/Core/SmartDeleteMemory.swift`
- Modify: `Sources/App/SelfTest.swift` (thêm `testSmartDeleteMemory()` vào `run()`)

**Interfaces:**
- Produces:
  - `SmartDeleteMemory.shared`
  - `func suppress(bundleID: String)`
  - `func isSuppressed(bundleID: String) -> Bool`
  - `func forget(bundleID: String)`
  - `static let ttl: TimeInterval` (24 giờ)
  - `var storageKey: String` (đổi được trong test để không đụng dữ liệu thật)

- [ ] **Step 1: Viết bộ kiểm tra hỏng trước**

Thêm vào `SelfTest.swift`:

```swift
private static func testSmartDeleteMemory() {
    print("— SmartDeleteMemory —")
    let m = SmartDeleteMemory(storageKey: "selftest.smartDeleteSuppressed")
    m.forgetAll()

    check("chưa ghi thì không bị bỏ qua", !m.isSuppressed(bundleID: "com.acme.foo"))
    m.suppress(bundleID: "com.acme.foo")
    check("ghi rồi thì bỏ qua", m.isSuppressed(bundleID: "com.acme.foo"))
    check("app khác không ảnh hưởng", !m.isSuppressed(bundleID: "com.acme.bar"))

    m.stamp(bundleID: "com.acme.old", at: Date().addingTimeInterval(-SmartDeleteMemory.ttl - 60))
    check("quá hạn thì hỏi lại", !m.isSuppressed(bundleID: "com.acme.old"))

    check("luôn bỏ qua chính xCleaner",
          m.isSuppressed(bundleID: Bundle.main.bundleIdentifier ?? "com.pikalong.xCleaner"))
    m.forgetAll()
}
```

- [ ] **Step 2: Chạy để chắc là hỏng**

Build sẽ **không biên dịch được** (`cannot find 'SmartDeleteMemory'`). Đó là trạng thái hỏng cần thấy.

- [ ] **Step 3: Viết `SmartDeleteMemory`**

```swift
import Foundation

/// Nhớ những app KHÔNG được hỏi lại "có dọn tàn dư không".
///
/// Khoá theo **bundle id** chứ không theo đường dẫn: app bị gỡ từ `/Applications` nhưng lúc
/// watcher nhìn thấy thì nó đã nằm ở `~/.Trash/Tên.app`, đường dẫn không còn khớp nữa.
final class SmartDeleteMemory {

    static let shared = SmartDeleteMemory(storageKey: "smartDeleteSuppressed")

    /// Hết hạn sau một ngày: xoá nhầm rồi bỏ vào lại, hôm sau xoá lần nữa thì vẫn nên được hỏi.
    static let ttl: TimeInterval = 24 * 60 * 60

    private let storageKey: String
    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    init(storageKey: String) { self.storageKey = storageKey }

    private var table: [String: Double] {
        get { defaults.dictionary(forKey: storageKey) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: storageKey) }
    }

    func suppress(bundleID: String) { stamp(bundleID: bundleID, at: Date()) }

    func stamp(bundleID: String, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        var t = table
        t[bundleID.lowercased()] = date.timeIntervalSince1970
        // Dọn luôn những mục đã quá hạn để bảng không phình mãi.
        let cutoff = Date().addingTimeInterval(-Self.ttl).timeIntervalSince1970
        t = t.filter { $0.value >= cutoff }
        table = t
    }

    func isSuppressed(bundleID: String) -> Bool {
        // Người dùng xoá chính xCleaner thì không có gì để mời chào.
        if let own = Bundle.main.bundleIdentifier,
           own.compare(bundleID, options: .caseInsensitive) == .orderedSame { return true }
        lock.lock(); defer { lock.unlock() }
        guard let at = table[bundleID.lowercased()] else { return false }
        return Date().timeIntervalSince1970 - at < Self.ttl
    }

    func forget(bundleID: String) {
        lock.lock(); defer { lock.unlock() }
        var t = table
        t.removeValue(forKey: bundleID.lowercased())
        table = t
    }

    func forgetAll() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: storageKey)
    }
}
```

- [ ] **Step 4: Chạy test, phải xanh**

- [ ] **Step 5: Commit** — `SmartDeleteMemory: nhớ app nào không hỏi lại`

---

### Task 2: `TrashWatcher` — tai nghe Thùng rác

**Files:**
- Create: `Sources/Core/TrashWatcher.swift`
- Modify: `Sources/App/SelfTest.swift`

**Interfaces:**
- Consumes: không.
- Produces:
  - `struct TrashedApp { let url: URL; let bundleID: String; let name: String; let version: String }`
  - `static func trashedApps(in dir: URL, ignoring seen: Set<String>) -> [TrashedApp]` (hàm thuần,
    đọc đĩa nhưng không giữ trạng thái — test bằng thư mục giả)
  - `static func readBundle(_ url: URL) -> TrashedApp?`
  - `final class TrashWatcher { init(directory: URL = FileUtils.homePath(".Trash"), onNew: @escaping ([TrashedApp]) -> Void); func start(); func stop() }`

- [ ] **Step 1: Viết bộ kiểm tra hỏng trước**

```swift
private static func testTrashWatcher() {
    print("— TrashWatcher —")
    let box = makeSandbox().appendingPathComponent("trash")
    try? FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)

    func makeApp(_ dir: URL, _ name: String, id: String?, version: String = "1.0") {
        let app = dir.appendingPathComponent("\(name).app/Contents")
        try? FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        var d: [String: Any] = ["CFBundleName": name, "CFBundleShortVersionString": version]
        if let id { d["CFBundleIdentifier"] = id }
        (d as NSDictionary).write(to: app.appendingPathComponent("Info.plist"), atomically: true)
    }

    makeApp(box, "Foo", id: "com.acme.foo", version: "2.1")
    makeApp(box, "NoID", id: nil)
    let deep = box.appendingPathComponent("MộtThưMục")
    try? FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
    makeApp(deep, "Nested", id: "com.acme.nested")
    try? "x".write(to: box.appendingPathComponent("ghi chú.txt"), atomically: true, encoding: .utf8)

    let found = TrashWatcher.trashedApps(in: box, ignoring: [])
    check("thấy đúng một app", found.count == 1, "(được \(found.map(\.name)))")
    check("đọc đúng bundle id", found.first?.bundleID == "com.acme.foo")
    check("đọc đúng tên", found.first?.name == "Foo")
    check("đọc đúng phiên bản", found.first?.version == "2.1")

    let ignored = TrashWatcher.trashedApps(in: box,
                                           ignoring: [box.appendingPathComponent("Foo.app").path])
    check("mục đã thấy rồi thì bỏ qua", ignored.isEmpty)
    cleanSandbox()
}
```

- [ ] **Step 2: Chạy để chắc là hỏng** (không biên dịch được)

- [ ] **Step 3: Viết `TrashWatcher`**

```swift
import Foundation
import CoreServices

/// Một app vừa rơi vào Thùng rác.
struct TrashedApp: Equatable {
    let url: URL
    let bundleID: String
    let name: String
    let version: String
}

/// Nghe ngóng `~/.Trash` và báo khi có `.app` mới xuất hiện.
///
/// Cần quyền Toàn quyền truy cập đĩa mới đọc được thư mục này. Chưa cấp thì luồng sự kiện vẫn
/// chạy nhưng danh sách con luôn rỗng — không phải lỗi, và app đã có chấm than đỏ nhắc quyền.
final class TrashWatcher {

    private let directory: URL
    private let onNew: ([TrashedApp]) -> Void
    private var stream: FSEventStreamRef?
    /// Đường dẫn đã nhìn thấy ở lần chụp trước. Mỗi lần sự kiện bắn thì so với danh sách mới.
    private var seen: Set<String> = []
    private let queue = DispatchQueue(label: "xCleaner.trashwatcher")

    init(directory: URL = FileUtils.homePath(".Trash"),
         onNew: @escaping ([TrashedApp]) -> Void) {
        self.directory = directory
        self.onNew = onNew
    }

    func start() {
        guard stream == nil else { return }
        // Ảnh chụp đầu tiên KHÔNG được báo: mọi thứ đang nằm sẵn trong Thùng rác là chuyện cũ,
        // báo hết lên là người dùng vừa đăng nhập đã ăn một loạt cửa sổ.
        seen = Set(Self.entries(in: directory).map(\.path))

        var ctx = FSEventStreamContext(version: 0,
                                       info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let me = Unmanaged<TrashWatcher>.fromOpaque(info).takeUnretainedValue()
            me.rescan()
        }
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &ctx,
            [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,                                  // gộp sự kiện nửa giây
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func rescan() {
        let fresh = Self.trashedApps(in: directory, ignoring: seen)
        seen = Set(Self.entries(in: directory).map(\.path))
        guard !fresh.isEmpty else { return }
        DispatchQueue.main.async { [onNew] in onNew(fresh) }
    }

    // MARK: - Phần thuần, kiểm tra được

    /// Chỉ mục **cấp 1** của thư mục: `.app` nằm trong một thư mục cũng vừa bị xoá thì người dùng
    /// đang xoá cả thư mục ấy, không phải gỡ app.
    static func entries(in dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: dir,
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsSubdirectoryDescendants])) ?? []
    }

    static func trashedApps(in dir: URL, ignoring seen: Set<String>) -> [TrashedApp] {
        entries(in: dir)
            .filter { $0.pathExtension == "app" && !seen.contains($0.path) }
            .compactMap(readBundle)
    }

    static func readBundle(_ url: URL) -> TrashedApp? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let d = NSDictionary(contentsOf: plist) as? [String: Any],
              let id = d["CFBundleIdentifier"] as? String, !id.isEmpty else { return nil }
        let name = (d["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (d["CFBundleShortVersionString"] as? String)
            ?? (d["CFBundleVersion"] as? String) ?? ""
        return TrashedApp(url: url, bundleID: id, name: name, version: version)
    }
}
```

- [ ] **Step 4: Chạy test, phải xanh**

- [ ] **Step 5: Commit** — `TrashWatcher: nghe ~/.Trash, nhận ra .app mới rơi vào`

---

### Task 3: `LaunchAgentInstaller` — khởi động cùng máy

**Files:**
- Create: `Sources/Core/LaunchAgentInstaller.swift`
- Modify: `Sources/App/SelfTest.swift`

**Interfaces:**
- Produces:
  - `enum LaunchAgentInstaller`
  - `static let label = "com.pikalong.xCleaner.watcher"`
  - `static var plistURL: URL`
  - `static func plistContents(executable: String) -> [String: Any]`
  - `static func needsRewrite(existing: [String: Any]?, executable: String) -> Bool`
  - `static func install(executable: String = ProcessInfo.processInfo.arguments[0])`
  - `static func uninstall()`

- [ ] **Step 1: Viết bộ kiểm tra hỏng trước**

```swift
private static func testLaunchAgent() {
    print("— LaunchAgent —")
    let d = LaunchAgentInstaller.plistContents(executable: "/Applications/xCleaner.app/Contents/MacOS/xCleaner")
    check("có Label đúng", d["Label"] as? String == "com.pikalong.xCleaner.watcher")
    check("chạy lúc đăng nhập", d["RunAtLoad"] as? Bool == true)
    check("không khai KeepAlive", d["KeepAlive"] == nil)
    let args = d["ProgramArguments"] as? [String] ?? []
    check("gọi đúng binary", args.first == "/Applications/xCleaner.app/Contents/MacOS/xCleaner")
    check("truyền cờ --watch", args.last == "--watch")

    check("chưa có plist thì phải ghi",
          LaunchAgentInstaller.needsRewrite(existing: nil, executable: "/A/x"))
    check("plist trỏ đúng chỗ thì thôi",
          !LaunchAgentInstaller.needsRewrite(existing: d,
              executable: "/Applications/xCleaner.app/Contents/MacOS/xCleaner"))
    check("plist trỏ sai chỗ thì ghi lại",
          LaunchAgentInstaller.needsRewrite(existing: d, executable: "/Volumes/USB/xCleaner.app/Contents/MacOS/xCleaner"))
}
```

- [ ] **Step 2: Chạy để chắc là hỏng**

- [ ] **Step 3: Viết `LaunchAgentInstaller`**

```swift
import Foundation

/// Ghi/gỡ LaunchAgent để xCleaner trực Thùng rác ngay từ lúc đăng nhập.
///
/// Dùng plist thuần chứ **không** `SMAppService`: cái đó đòi app ký bằng Developer ID, còn
/// xCleaner ký bằng chứng chỉ tự ký (xem ghi chú ở `PrivilegedRunner`).
enum LaunchAgentInstaller {

    static let label = "com.pikalong.xCleaner.watcher"

    static var plistURL: URL {
        FileUtils.homePath("Library/LaunchAgents/\(label).plist")
    }

    /// Đường dẫn binary thật của tiến trình đang chạy (đã gỡ symlink).
    static var currentExecutable: String {
        URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    }

    static func plistContents(executable: String) -> [String: Any] {
        // KHÔNG khai KeepAlive: người dùng thoát app là cố ý, dựng dậy là chống lại họ — và
        // KeepAlive/SuccessfulExit đã từng cho ra kiểu daemon chết im lặng ở Clawdmeter.
        ["Label": label,
         "ProgramArguments": [executable, "--watch"],
         "RunAtLoad": true,
         "ProcessType": "Background"]
    }

    static func needsRewrite(existing: [String: Any]?, executable: String) -> Bool {
        guard let existing,
              let args = existing["ProgramArguments"] as? [String],
              args.first == executable, args.contains("--watch"),
              existing["RunAtLoad"] as? Bool == true else { return true }
        return false
    }

    static func install(executable: String = currentExecutable) {
        let existing = NSDictionary(contentsOf: plistURL) as? [String: Any]
        guard needsRewrite(existing: existing, executable: executable) else { return }
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        (plistContents(executable: executable) as NSDictionary).write(to: plistURL, atomically: true)
    }

    static func uninstall() {
        try? FileManager.default.removeItem(at: plistURL)
        // Chưa nạp thì lệnh này báo lỗi — bình thường, bỏ qua.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
```

- [ ] **Step 4: Chạy test, phải xanh**

- [ ] **Step 5: Commit** — `LaunchAgentInstaller: ghi/gỡ agent trực Thùng rác`

---

### Task 4: Hai chế độ chạy + công tắc trong Cài đặt

**Files:**
- Modify: `Sources/App/xCleanerApp.swift` (chế độ `--watch`, policy, reopen, một tiến trình)
- Modify: `Sources/App/Stores.swift:8` (thêm `@AppStorage("smartDelete")`)
- Modify: `Sources/Views/SettingsView.swift` (thẻ công tắc trong tab Chung)

**Interfaces:**
- Consumes: `LaunchAgentInstaller.install()/uninstall()`
- Produces:
  - `enum RunMode { case normal, watch }`, `RunMode.current`
  - `AppSettings.smartDelete: Bool`
  - `Notification.Name.xcSmartDeleteChanged`
  - `AppDelegate.enterBackground()` / `.enterForeground()`

- [ ] **Step 1: Thêm cờ trong `AppSettings`**

```swift
@AppStorage("smartDelete")      var smartDelete: Bool = true
```

- [ ] **Step 2: Chế độ chạy trong `xCleanerApp.swift`**

```swift
/// App chạy bình thường (có cửa sổ) hay chỉ trực Thùng rác dưới nền.
enum RunMode {
    case normal, watch
    static let current: RunMode =
        CommandLine.arguments.contains("--watch") ? .watch : .normal
}
```

Trong `body`, bỏ hẳn cửa sổ ở chế độ trực:

```swift
        .defaultLaunchBehaviorCompat(suppressed: RunMode.current == .watch)
```

kèm phần bọc availability (đích là macOS 14, `defaultLaunchBehavior` chỉ có từ 15):

```swift
private extension Scene {
    @SceneBuilder
    func defaultLaunchBehaviorCompat(suppressed: Bool) -> some Scene {
        if #available(macOS 15.0, *) {
            self.defaultLaunchBehavior(suppressed ? .suppressed : .presented)
        } else {
            self
        }
    }
}
```

- [ ] **Step 3: `AppDelegate` — vào nền, ra nền, mở lại**

```swift
    /// Đang chạy nền thì đóng cửa sổ không được thoát app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if UserDefaults.standard.object(forKey: "smartDelete") as? Bool ?? true {
            enterBackground()
            return false
        }
        return true
    }

    /// Bấm vào icon trong Finder/Dock lúc app đang trực dưới nền.
    ///
    /// Trả `false` hoặc quên mở cửa sổ là người dùng bấm mà không thấy gì xảy ra rồi kết luận
    /// "app hỏng" — đúng lỗi đã mất công truy ở xDM.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        enterForeground()
        return true
    }

    func enterBackground() {
        NSApp.setActivationPolicy(.accessory)
    }

    func enterForeground() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true })
            ?? NSApp.windows.first(where: { $0 is NSPanel == false && $0.contentViewController != nil }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: .xcOpenMainWindow, object: nil)
        }
    }
```

`RootView` giữ một `@Environment(\.openWindow)` và nghe `.xcOpenMainWindow` để mở lại cửa sổ khi
SwiftUI đã dẹp hẳn scene.

- [ ] **Step 4: `applicationDidFinishLaunching` phân nhánh**

```swift
        // Đã có một tiến trình xCleaner khác (thường là cái đang trực dưới nền) thì nhường nó.
        if let other = NSRunningApplication.runningApplications(
                withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .first(where: { $0.processIdentifier != getpid() }) {
            other.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }

        if RunMode.current == .watch {
            NSApp.setActivationPolicy(.accessory)
            // macOS 14 không có `defaultLaunchBehavior`: cửa sổ vẫn kịp dựng, đóng ngay khi nó hiện.
            NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeVisibleNotification, object: nil, queue: .main) { n in
                    if let w = n.object as? NSWindow, !(w is NSPanel) { w.close() }
            }
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        SmartDeleteController.shared.applySetting()
```

- [ ] **Step 5: Công tắc trong Cài đặt** (`SettingsView.general`, sau thẻ "Ghi nhớ lựa chọn")

```swift
            SettingCard {
                SettingToggle(
                    title: "Dọn tàn dư khi tôi xoá ứng dụng",
                    detail: "Khi bạn kéo một ứng dụng vào Thùng rác, xCleaner hiện danh sách tệp app đó để lại để dọn luôn. Để làm được việc này, xCleaner ở lại chạy nền sau khi bạn đóng cửa sổ (không có icon ở Dock).",
                    isOn: $settings.smartDelete, accent: accent)
            }
            .onChange(of: settings.smartDelete) { _ in
                SmartDeleteController.shared.applySetting()
            }
```

- [ ] **Step 6: Build + chạy test, phải xanh**

- [ ] **Step 7: Commit** — `Chế độ chạy nền và công tắc dọn tàn dư`

---

### Task 5: `SmartDeleteController` — xếp hàng và quét

**Files:**
- Create: `Sources/App/SmartDeleteController.swift`
- Modify: `Sources/App/SelfTest.swift`

**Interfaces:**
- Consumes: `TrashWatcher`, `SmartDeleteMemory`, `LaunchAgentInstaller`, `UninstallScanner`,
  `LeftoverPanel.show(...)` (Task 6 — viết Task 6 trước phần gọi, hoặc để lời gọi vào cuối Task 6).
- Produces:
  - `SmartDeleteController.shared`
  - `func applySetting()` — đọc `smartDelete`, bật/tắt watcher + agent
  - `static func installedApp(from: TrashedApp) -> UninstallScanner.InstalledApp`
  - `static func leftoversToShow(_ items: [CleanItem], bundle: URL) -> [CleanItem]`

- [ ] **Step 1: Viết bộ kiểm tra hỏng trước**

```swift
private static func testSmartDeleteController() {
    print("— SmartDeleteController —")
    let t = TrashedApp(url: URL(fileURLWithPath: "/Users/x/.Trash/Foo.app"),
                       bundleID: "com.acme.foo", name: "Foo", version: "2.1")
    let app = SmartDeleteController.installedApp(from: t)
    check("giữ bundle id", app.id == "com.acme.foo")
    check("giữ tên", app.name == "Foo")
    check("trỏ vào bundle trong Thùng rác", app.url == t.url)

    let bundle = t.url
    let items = [
        CleanItem(url: bundle, name: "Foo.app", detail: "Ứng dụng", size: 100,
                  isSelected: true, requiresAdmin: false, isDirectory: true),
        CleanItem(url: URL(fileURLWithPath: "/Users/x/Library/Caches/com.acme.foo"),
                  name: "com.acme.foo", detail: "Bộ nhớ đệm", size: 10,
                  isSelected: true, requiresAdmin: false, isDirectory: true)
    ]
    let shown = SmartDeleteController.leftoversToShow(items, bundle: bundle)
    check("bỏ chính bundle khỏi danh sách dọn", shown.count == 1)
    check("giữ lại tàn dư", shown.first?.name == "com.acme.foo")
}
```

- [ ] **Step 2: Chạy để chắc là hỏng**

- [ ] **Step 3: Viết `SmartDeleteController`**

```swift
import AppKit
import SwiftUI

/// Nối tai nghe Thùng rác với bộ quét tàn dư và cửa sổ nổi.
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
        let on = UserDefaults.standard.object(forKey: "smartDelete") as? Bool ?? true
        if on {
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

    private func enqueue(_ apps: [TrashedApp]) {
        for a in apps where !SmartDeleteMemory.shared.isSuppressed(bundleID: a.bundleID) {
            queue.append(a)
        }
        pump()
    }

    /// Mỗi lúc một cửa sổ. Nhiều app vào Thùng rác một lượt thì hỏi lần lượt.
    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        busy = true
        scan(next) { [weak self] items in
            guard let self else { return }
            guard !items.isEmpty, FileUtils.exists(next.url) else {
                // Không còn gì để dọn, hoặc người dùng đã bấm "Put Back" / đổ Thùng rác trong lúc
                // quét. Im lặng — người dùng không yêu cầu gì, đừng bật cửa sổ để khoe.
                self.busy = false
                self.pump()
                return
            }
            LeftoverPanel.show(app: next, items: items) { [weak self] in
                SmartDeleteMemory.shared.suppress(bundleID: next.bundleID)
                self?.busy = false
                self?.pump()
            }
        }
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

    /// Bỏ chính bundle ra khỏi danh sách: nó đã nằm trong Thùng rác rồi, dọn nữa là thừa.
    static func leftoversToShow(_ items: [CleanItem], bundle: URL) -> [CleanItem] {
        items.filter { $0.url.standardizedFileURL != bundle.standardizedFileURL }
    }
}
```

- [ ] **Step 4: Ghi dấu app do chính xCleaner gỡ** — trong `Stores.swift`, đầu `performUninstall()`:

```swift
        SmartDeleteMemory.shared.suppress(bundleID: app.id)
```

- [ ] **Step 5: Chạy test, phải xanh** (lời gọi `LeftoverPanel.show` sẽ có ở Task 6 — làm Task 6
  trước bước build nếu trình biên dịch kêu thiếu)

- [ ] **Step 6: Commit** — `SmartDeleteController: xếp hàng và quét tàn dư`

---

### Task 6: Cửa sổ nổi

**Files:**
- Create: `Sources/Views/LeftoverPanel.swift`

**Interfaces:**
- Consumes: `TrashedApp`, `CleanItem`, `Remover`, `CleanLedger`, `.glass()`, `ActionButton`, `Fmt`
- Produces: `enum LeftoverPanel { static func show(app: TrashedApp, items: [CleanItem], onClose: @escaping () -> Void) }`

- [ ] **Step 1: Viết cửa sổ**

Yêu cầu bắt buộc, đã trả giá ở cửa sổ chính:

```swift
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // macOS vẽ bóng theo KHUNG CHỮ NHẬT của cửa sổ chứ không theo hình dạng nội dung.
        panel.hasShadow = false          // bóng tự vẽ trong SwiftUI
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = true
```

Nội dung (`LeftoverPanelView`): tiêu đề `"Còn sót lại của \(app.name)"`, dòng phụ
`"\(items.count) mục · \(Fmt.size(tổng))"`, danh sách cuộn có checkbox/tên/đường dẫn rút gọn
(`FileUtils.prettyPath`)/dung lượng/nút `magnifyingglass` mở Finder, và một dòng mờ đầu danh sách
`"\(app.name).app · Đã ở trong Thùng rác"` không tick được. Đáy: `ActionButton(title: "Đóng")` và
`ActionButton(title: "Dọn", kind: .prominent)`.

Cỡ cửa sổ 460×420, bo góc 16, nền `.glass()`.

- [ ] **Step 2: Hành vi**

- Esc hoặc "Đóng" → gọi `onClose()` rồi `panel.close()`.
- "Dọn" → `Remover.perform` trên hàng đợi nền với `moveToTrash` theo cài đặt, lời nhắc quyền
  `"xCleaner cần quyền quản trị để dọn tàn dư của \(app.name)."`; xong thì `CleanLedger.shared.record`,
  đổi nội dung thành `"Đã dọn \(Fmt.size(freed))"`, chờ 1,5s rồi tự đóng.
- Hiện cửa sổ: `NSApp.activate(ignoringOtherApps: true)` + `panel.makeKeyAndOrderFront(nil)`.
  App đang `.accessory` nên việc này **không** làm hiện icon Dock.
- `panel.center()` rồi dịch lên trên 60pt cho khỏi che Dock.

- [ ] **Step 3: Build + chạy test, phải xanh**

- [ ] **Step 4: Commit** — `Cửa sổ nổi liệt kê tàn dư`

---

### Task 7: Nối dây, đăng ký test, thử tay

**Files:**
- Modify: `Sources/App/SelfTest.swift` (gọi 4 hàm test mới trong `run()`)
- Modify: `README.md` (một đoạn ngắn về chức năng mới)

- [ ] **Step 1: Đăng ký test** — thêm vào `run()`:

```swift
        testSmartDeleteMemory()
        testTrashWatcher()
        testLaunchAgent()
        testSmartDeleteController()
```

- [ ] **Step 2: Chạy toàn bộ test** — phải xanh, không hụt phép nào so với 225 phép hiện có.

- [ ] **Step 3: Thử tay** (bắt buộc, ghi kết quả lại):

```bash
# dựng một app giả + tàn dư giả
mkdir -p ~/Applications/FakeLeftover.app/Contents
cat > /tmp/fakeinfo.plist <<'EOF'
{ CFBundleIdentifier = "com.test.fakeleftover"; CFBundleName = "FakeLeftover";
  CFBundleShortVersionString = "1.0"; }
EOF
plutil -convert binary1 -o ~/Applications/FakeLeftover.app/Contents/Info.plist /tmp/fakeinfo.plist
mkdir -p ~/Library/Application\ Support/com.test.fakeleftover
dd if=/dev/zero of=~/Library/Application\ Support/com.test.fakeleftover/blob bs=1m count=5
mkdir -p ~/Library/Caches/com.test.fakeleftover
```

Rồi trong Finder chọn `~/Applications/FakeLeftover.app`, bấm ⌘⌫. Cửa sổ phải hiện trong ~1–2 giây,
liệt kê đúng hai mục. Kiểm thêm:

1. Bấm "Đóng" → xoá app khỏi Thùng rác, dựng lại, ⌘⌫ lần nữa → **không** hỏi lại (đã ghi nhớ).
2. `defaults delete com.pikalong.xCleaner smartDeleteSuppressed` → ⌘⌫ lại → hỏi lại.
3. Bấm "Dọn" → hai thư mục kia biến mất.
4. Đóng cửa sổ chính xCleaner → app **không** thoát, icon Dock biến mất, vẫn bắt được ⌘⌫.
5. Bấm xCleaner trong Finder → cửa sổ chính mở lại, icon Dock hiện lại.
6. Tắt công tắc trong Cài đặt → `ls ~/Library/LaunchAgents | grep xCleaner` rỗng; đóng cửa sổ thì
   app thoát hẳn như cũ.

- [ ] **Step 4: Commit** — `Nối dây SmartDelete + test`

## Tự rà lại kế hoạch

- Spec mục 1 (hai chế độ) → Task 4. Mục 2 (LaunchAgent) → Task 3. Mục 3 (watcher) → Task 2.
  Mục 4 (không hỏi lại) → Task 1 + Task 5 Step 4. Mục 5 (controller) → Task 5. Mục 6 (cửa sổ) →
  Task 6. Mục 7 (cài đặt) → Task 4 Step 5. Phần kiểm thử → Task 7.
- Tên hàm dùng ở Task 5 (`LeftoverPanel.show(app:items:onClose:)`) khớp với thứ Task 6 tạo ra.
- `SmartDeleteMemory` khoá theo bundle id ở cả ba chỗ ghi và đọc.
