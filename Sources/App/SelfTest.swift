#if DEBUG
import Foundation
import AppKit

/// Bộ kiểm tra chạy được từ dòng lệnh: `XCLEANER_SELFTEST=1`.
/// Chỉ đụng vào một thư mục thử nghiệm riêng trong thư mục nhà, không chạm dữ liệu thật.
enum SelfTest {

    private static var passed = 0
    private static var failed = 0

    static func run() {
        passed = 0; failed = 0
        print("=== xCleaner self-test ===")
        testSafetyGuardRejects()
        testSafetyGuardAccepts()
        testRemoveUserFiles()
        testTrashMode()
        testEmptyContentsOnly()
        testSizeCalculation()
        testSelectionMemory()
        testUninstaller()
        print("=== \(passed) đạt, \(failed) hỏng ===")
        exit(failed == 0 ? 0 : 1)
    }

    private static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition { passed += 1; print("  ✓ \(name)") }
        else { failed += 1; print("  ✗ \(name) \(detail)") }
    }

    private static var sandbox: URL {
        FileUtils.homePath(".xcleaner-selftest")
    }

    private static func makeSandbox() -> URL {
        let fm = FileManager.default
        try? fm.removeItem(at: sandbox)
        try? fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
        return sandbox
    }

    // MARK: Hàng rào an toàn

    private static func testSafetyGuardRejects() {
        print("[SafetyGuard] những đường dẫn phải bị từ chối")
        let mustReject = [
            "/", "/System", "/System/Library", "/usr", "/usr/bin", "/bin/sh",
            "/Library", "/Library/Caches", "/Library/Keychains", "/Applications",
            "/Users", "/Volumes", "/private/etc", "/private/var",
            NSHomeDirectory(), NSHomeDirectory() + "/Documents",
            NSHomeDirectory() + "/Library", NSHomeDirectory() + "/Library/Caches",
            NSHomeDirectory() + "/Library/Mobile Documents",
            "/tmp/../System",
            "/private/var/db/sudo", "/Library/LaunchDaemons", "/Library/Security",
            "/Volumes/SomeDisk", "/Users/someone-else",
            "/System/Volumes/Data", "/cores", "/dev/null",
            Bundle.main.bundlePath
        ]
        for p in mustReject {
            let rejected = SafetyGuard.validate(URL(fileURLWithPath: p), requireExists: false) != nil
            check("từ chối \(p)", rejected)
        }
    }

    private static func testSafetyGuardAccepts() {
        print("[SafetyGuard] những đường dẫn phải được chấp nhận")
        let dir = makeSandbox()
        let f = dir.appendingPathComponent("file.txt")
        FileManager.default.createFile(atPath: f.path, contents: Data("x".utf8))

        check("chấp nhận tệp trong thư mục nhà", SafetyGuard.isValid(f))
        check("chấp nhận thư mục con của ~/Library/Caches",
              SafetyGuard.validate(FileUtils.homePath("Library/Caches/com.example.app"),
                                   requireExists: false) == nil)
        check("chấp nhận thư mục con của /Library/Caches",
              SafetyGuard.validate(URL(fileURLWithPath: "/Library/Caches/com.example.app"),
                                   requireExists: false) == nil)
        check("chấp nhận app trong /Applications",
              SafetyGuard.validate(URL(fileURLWithPath: "/Applications/Example.app"),
                                   requireExists: false) == nil)
    }

    // MARK: Xoá

    private static func testRemoveUserFiles() {
        print("[Remover] xoá vĩnh viễn")
        let dir = makeSandbox()
        var items: [CleanItem] = []
        for name in ["a.txt", "tệp có dấu cách.txt", "it's \"quoted\".txt"] {
            let f = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: f.path, contents: Data(repeating: 0x41, count: 4096))
            items.append(CleanItem(url: f, size: 4096, isDirectory: false))
        }
        let sub = dir.appendingPathComponent("thư mục con")
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sub.appendingPathComponent("b.bin").path,
                                       contents: Data(repeating: 0x42, count: 8192))
        items.append(CleanItem(url: sub, size: 8192))

        let outcome = Remover.perform(Remover.Request(items: items, moveToTrash: false,
                                                      adminPrompt: "test")) { _, _ in }
        check("xoá đủ 4 mục", outcome.removedCount == 4, "(được \(outcome.removedCount))")
        check("không có lỗi", outcome.failures.isEmpty,
              "(\(outcome.failures.map(\.reason).joined(separator: "; ")))")
        check("tệp đã biến mất", items.allSatisfy { !FileUtils.exists($0.url) })
        check("không dùng tới quyền quản trị", !outcome.usedAdmin)
    }

    private static func testTrashMode() {
        print("[Remover] chuyển vào Thùng rác")
        let dir = makeSandbox()
        let f = dir.appendingPathComponent("vào-thùng-rác.txt")
        FileManager.default.createFile(atPath: f.path, contents: Data(repeating: 0x43, count: 2048))
        let item = CleanItem(url: f, size: 2048, isDirectory: false)

        let outcome = Remover.perform(Remover.Request(items: [item], moveToTrash: true,
                                                      adminPrompt: "test")) { _, _ in }
        check("báo đã xử lý", outcome.removedCount == 1)
        check("không còn ở chỗ cũ", !FileUtils.exists(f))
        let inTrash = FileUtils.homePath(".Trash/vào-thùng-rác.txt")
        check("nằm trong Thùng rác", FileUtils.exists(inTrash))
        try? FileManager.default.removeItem(at: inTrash)
    }

    private static func testEmptyContentsOnly() {
        print("[Remover] chỉ dọn ruột, giữ lại thư mục")
        let dir = makeSandbox()
        let keep = dir.appendingPathComponent("giữ-lại")
        try? FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
        for i in 0..<3 {
            FileManager.default.createFile(atPath: keep.appendingPathComponent("\(i).bin").path,
                                           contents: Data(repeating: 0x44, count: 1024))
        }
        let item = CleanItem(url: keep, size: 3072, emptyContentsOnly: true)
        let outcome = Remover.perform(Remover.Request(items: [item], moveToTrash: false,
                                                      adminPrompt: "test")) { _, _ in }
        check("không báo lỗi", outcome.failures.isEmpty)
        check("thư mục vẫn còn", FileUtils.isDirectory(keep))
        check("ruột đã rỗng", FileUtils.children(of: keep).isEmpty)
    }

    // MARK: Nhớ lựa chọn

    private static func testSelectionMemory() {
        print("[SelectionMemory] nhớ đúng phần người dùng đã đổi")
        let memory = SelectionMemory.shared
        let saved = UserDefaults.standard.dictionary(forKey: "selectionOverrides.v2")
        memory.forgetAll()

        let dir = makeSandbox()
        let a = dir.appendingPathComponent("a.bin")   // mặc định chọn, người dùng bỏ
        let b = dir.appendingPathComponent("b.bin")   // mặc định không chọn, người dùng chọn
        let c = dir.appendingPathComponent("c.bin")   // không ai đụng tới
        for u in [a, b, c] {
            FileManager.default.createFile(atPath: u.path, contents: Data(repeating: 0x5A, count: 2048))
        }

        func freshGroups() -> [CleanGroup] {
            [CleanGroup(id: "g", title: "Thử", subtitle: "", icon: "gear", safety: .safe,
                        items: [CleanItem(url: a, size: 2048, isSelected: true),
                                CleanItem(url: b, size: 2048, isSelected: false),
                                CleanItem(url: c, size: 2048, isSelected: true)])]
        }

        var groups = freshGroups()
        groups[0].items[0].isSelected = false
        groups[0].items[1].isSelected = true
        memory.record(groups[0].items)

        var next = freshGroups()
        let restored = memory.apply(to: &next)
        check("khôi phục đúng 2 mục", restored == 2, "(được \(restored))")
        check("mục bị bỏ chọn vẫn tắt", next[0].items[0].isSelected == false)
        check("mục được chọn thêm vẫn bật", next[0].items[1].isSelected == true)
        check("mục không đụng tới giữ nguyên đề xuất", next[0].items[2].isSelected == true)

        // Quay về đúng đề xuất thì phải quên đi, không giữ rác vô hạn
        var back = freshGroups()
        _ = memory.apply(to: &back)
        back[0].items[0].isSelected = true
        back[0].items[1].isSelected = false
        memory.record(back[0].items)
        check("trở lại mặc định thì xoá khỏi bộ nhớ", memory.count == 0, "(còn \(memory.count))")

        // Ghi nhớ mà làm cho không còn gì được chọn thì phải bị bỏ qua
        var all = freshGroups()
        for i in all[0].items.indices { all[0].items[i].isSelected = false }
        memory.record(all[0].items)
        var afterAll = freshGroups()
        let restoredAll = memory.apply(to: &afterAll)
        let everythingOff = afterAll.allSatisfy { $0.selectedCount == 0 }
        check("ghi nhớ bỏ chọn hết thì nhận ra được", restoredAll > 0 && everythingOff)
        memory.forget(afterAll.flatMap(\.items))
        var recovered = freshGroups()
        _ = memory.apply(to: &recovered)
        check("quên đi rồi thì quay lại mặc định",
              recovered[0].items.filter(\.isSelected).count == 2)

        memory.forgetAll()
        if let saved { UserDefaults.standard.set(saved, forKey: "selectionOverrides.v2") }
        try? FileManager.default.removeItem(at: sandbox)
    }

    // MARK: Gỡ ứng dụng

    /// Dựng một app giả trong ~/Applications cùng đủ loại tệp nó "để lại", rồi kiểm tra
    /// bộ dò có tìm đúng, có bỏ sót, và quan trọng nhất là có vơ nhầm của app khác không.
    private static func testUninstaller() {
        print("[Uninstaller] tìm tệp còn sót")
        let fm = FileManager.default
        let bundleID = "com.xcleaner.selftest.fakeapp"
        let appName = "XCleanerFakeApp"
        let appURL = FileUtils.homePath("Applications/\(appName).app")

        // App giả: chỉ cần Info.plist hợp lệ là Bundle đọc được
        try? fm.createDirectory(at: appURL.appendingPathComponent("Contents"),
                                withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(bundleID)</string>
        <key>CFBundleName</key><string>\(appName)</string>
        <key>CFBundleExecutable</key><string>\(appName)</string>
        </dict></plist>
        """
        try? plist.write(to: appURL.appendingPathComponent("Contents/Info.plist"),
                         atomically: true, encoding: .utf8)

        // Tệp nó để lại ở những chỗ quen thuộc
        var expected: [URL] = [appURL]
        let leftovers: [(String, String)] = [
            ("Library/Caches", bundleID),
            ("Library/Preferences", "\(bundleID).plist"),
            ("Library/Application Support", appName),
            ("Library/Logs", bundleID),
            ("Library/Saved Application State", "\(bundleID).savedState"),
            ("Library/HTTPStorages", bundleID),
            ("Library/LaunchAgents", "\(bundleID).plist")
        ]
        for (dir, name) in leftovers {
            let parent = FileUtils.homePath(dir)
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            let url = parent.appendingPathComponent(name)
            if name.hasSuffix(".plist") {
                fm.createFile(atPath: url.path, contents: Data(repeating: 0x41, count: 2048))
            } else {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
                fm.createFile(atPath: url.appendingPathComponent("data.bin").path,
                              contents: Data(repeating: 0x42, count: 4096))
            }
            expected.append(url)
        }

        // Mồi nhử: tên gần giống nhưng của app khác, không được đụng vào
        let decoyNames = ["\(bundleID)extra", "\(appName)Helper", "com.other.app"]
        var decoys: [URL] = []
        for name in decoyNames {
            let url = FileUtils.homePath("Library/Caches").appendingPathComponent(name)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            fm.createFile(atPath: url.appendingPathComponent("x.bin").path,
                          contents: Data(repeating: 0x43, count: 1024))
            decoys.append(url)
        }

        defer {
            for url in expected + decoys { try? fm.removeItem(at: url) }
        }

        let scanner = UninstallScanner()
        let token = CancelToken()
        let apps = scanner.listApps(cancel: token) { _ in }
        guard let app = apps.first(where: { $0.id == bundleID }) else {
            check("thấy app giả trong danh sách", false, "(không thấy \(bundleID))")
            return
        }
        check("thấy app giả trong danh sách", true)
        check("đọc đúng tên app", app.name == appName, "(được \(app.name))")

        let found = scanner.leftovers(for: app, cancel: token)
        let paths = Set(found.map(\.url.path))
        for url in expected {
            check("tìm ra \(url.lastPathComponent)", paths.contains(url.path))
        }
        for url in decoys {
            check("không vơ nhầm \(url.lastPathComponent)", !paths.contains(url.path))
        }
        check("mọi mục đều qua được hàng rào an toàn",
              found.allSatisfy { SafetyGuard.isValid($0.url) })
        check("không mục nào đòi quyền quản trị", found.allSatisfy { !$0.requiresAdmin })

        // Gỡ thật rồi kiểm tra sạch sẽ
        let outcome = Remover.perform(Remover.Request(items: found, moveToTrash: false,
                                                      adminPrompt: "test")) { _, _ in }
        check("gỡ không lỗi", outcome.failures.isEmpty,
              "(\(outcome.failures.map(\.reason).joined(separator: "; ")))")
        check("app đã biến mất", !FileUtils.exists(appURL))
        check("tệp còn sót đã sạch", expected.allSatisfy { !FileUtils.exists($0) })
        check("mồi nhử vẫn còn nguyên", decoys.allSatisfy { FileUtils.exists($0) })
    }

    private static func testSizeCalculation() {
        print("[FileUtils] đo dung lượng")
        let dir = makeSandbox()
        let sub = dir.appendingPathComponent("đo")
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for i in 0..<4 {
            FileManager.default.createFile(atPath: sub.appendingPathComponent("\(i).bin").path,
                                           contents: Data(repeating: 0x45, count: 100_000))
        }
        let size = FileUtils.directorySize(sub)
        check("tổng ≈ 400 KB", size >= 400_000 && size < 500_000, "(được \(size))")

        // Liên kết tượng trưng không được tính vào tổng.
        let link = sub.appendingPathComponent("link")
        try? FileManager.default.createSymbolicLink(at: link,
                                                    withDestinationURL: sub.appendingPathComponent("0.bin"))
        check("bỏ qua symlink", FileUtils.directorySize(sub) == size)

        try? FileManager.default.removeItem(at: sandbox)
    }
}
#endif
