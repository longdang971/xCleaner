#if DEBUG
import Foundation
import AppKit

/// Bộ kiểm tra chạy được từ dòng lệnh: `XCLEANER_SELFTEST=1`.
/// Chỉ đụng vào một thư mục thử nghiệm riêng trong thư mục nhà, không chạm dữ liệu thật.
enum SelfTest {

    private static var passed = 0
    private static var failed = 0

    @MainActor
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
        testScatteredCaches()
        testRecentLists()
        testDuplicates()
        testLargeOld()
        testStartup()
        testNestedPackageSize()
        testHardLinkDuplicates()
        testTrashKeepsFolder()
        testCleanAccounting()
        testBlockedEmptyContents()
        testSmartScanAlwaysFiveCards()
        testUndeletableMemory()
        testUpdater()
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

    /// Con số "đã giải phóng" và tiếng báo cho từng mục phải khớp với thực tế trên đĩa.
    ///
    /// Bản trước cộng dung lượng của mọi mục được chọn, nên `~/Library/Caches/Homebrew` nằm
    /// cả trong thẻ "Bộ nhớ đệm" lẫn thẻ "Công cụ lập trình" được tính hai lần; mục con của
    /// một thư mục cũng đang bị xoá cũng vậy. Mục đã biến mất từ trước thì không được báo gì
    /// cả, nên màn "đang dọn" đếm hụt và trông như app bỏ sót.
    private static func testCleanAccounting() {
        print("[Remover] đếm đúng mục và dung lượng")
        let dir = makeSandbox()
        let fm = FileManager.default

        let dup = dir.appendingPathComponent("trùng")
        try? fm.createDirectory(at: dup, withIntermediateDirectories: true)
        fm.createFile(atPath: dup.appendingPathComponent("x.bin").path,
                      contents: Data(repeating: 0x45, count: 2048))

        let parent = dir.appendingPathComponent("cha")
        let child = parent.appendingPathComponent("con")
        try? fm.createDirectory(at: child, withIntermediateDirectories: true)
        fm.createFile(atPath: child.appendingPathComponent("y.bin").path,
                      contents: Data(repeating: 0x46, count: 4096))

        let ghost = dir.appendingPathComponent("đã-biến-mất")

        let items = [CleanItem(url: dup, name: "trùng #1", size: 2048),
                     CleanItem(url: dup, name: "trùng #2", size: 2048),
                     CleanItem(url: parent, name: "cha", size: 4096),
                     CleanItem(url: child, name: "con", size: 4096),
                     CleanItem(url: ghost, name: "ma", size: 1024)]

        var finished: [String] = []
        let outcome = Remover.perform(
            Remover.Request(items: items, moveToTrash: false, adminPrompt: "test"),
            progress: { _, _ in },
            itemFinished: { item, _ in finished.append(item.name) })

        check("mỗi mục được báo đúng một lần", finished.count == items.count,
              "(\(finished.count)/\(items.count): \(finished.joined(separator: ", ")))")
        check("không cộng đôi dung lượng", outcome.freedBytes == 2048 + 4096,
              "(\(outcome.freedBytes) thay vì \(2048 + 4096))")
        check("đếm đủ số mục đã dọn", outcome.removedCount == items.count,
              "(\(outcome.removedCount))")
        check("không báo lỗi", outcome.failures.isEmpty,
              "(\(outcome.failures.map(\.reason).joined(separator: "; ")))")
        check("cả hai thư mục đã biến mất", !FileUtils.exists(dup) && !FileUtils.exists(parent))
    }

    /// Thư mục "dọn ruột" mà macOS chặn đọc thì tuyệt đối không được báo là đã dọn xong.
    ///
    /// `FileUtils.children` trả về mảng rỗng cho cả thư mục sạch lẫn thư mục cấm đọc. Bản
    /// trước không phân biệt hai thứ đó nên im lặng tính là xong, còn người dùng quét lại thì
    /// thấy mọi thứ y nguyên — đúng cái cảm giác "app dọn sót".
    private static func testBlockedEmptyContents() {
        print("[Remover] thư mục cấm đọc không được coi là đã dọn")
        let dir = makeSandbox()
        let fm = FileManager.default
        let blocked = dir.appendingPathComponent("cấm-đọc")
        try? fm.createDirectory(at: blocked, withIntermediateDirectories: true)
        fm.createFile(atPath: blocked.appendingPathComponent("bí-mật.bin").path,
                      contents: Data(repeating: 0x47, count: 4096))
        chmod(blocked.path, 0o000)
        defer { chmod(blocked.path, 0o700) }

        check("directoryState nhận ra bị chặn", FileUtils.directoryState(blocked) == .blocked)
        check("isCleared không tin thư mục cấm đọc là sạch",
              !Remover.isCleared(CleanItem(url: blocked, size: 4096, emptyContentsOnly: true)))
    }

    /// Quét thông minh luôn có đủ năm chặng và năm thẻ, kể cả khi chặng đó chẳng tìm thấy gì.
    private static func testSmartScanAlwaysFiveCards() {
        print("[SmartScan] luôn đủ năm thẻ")
        let ids = ["cache", "logs", "misc", "trash", "browsers"]
        let stages = SmartScanScanner().stages
        check("có đúng năm chặng", stages.count == 5, "(\(stages.count))")
        check("đúng năm chặng cần có", Set(stages.map(\.id)) == Set(ids),
              "(\(stages.map(\.id).joined(separator: ", ")))")

        let groups = SmartScanScanner().scan(cancel: CancelToken()) { _ in }
        check("có đúng năm thẻ", groups.count == 5, "(\(groups.count))")
        check("đúng năm thẻ cần có", Set(groups.map(\.id)) == Set(ids),
              "(\(groups.map(\.id).joined(separator: ", ")))")
    }

    /// Mục đã thử dọn bằng quyền quản trị mà vẫn không xoá nổi thì không được mời người dùng
    /// dọn lại lần sau — đó là cả nguồn gốc của con số "N mục không xoá được" đã bỏ đi.
    private static func testUndeletableMemory() {
        print("[Undeletable] mục không xoá được thì thôi liệt kê")
        let memory = UndeletableMemory.shared
        let saved = UserDefaults.standard.stringArray(forKey: "undeletablePaths.v1")
        memory.forgetAll()
        defer {
            memory.forgetAll()
            if let saved { UserDefaults.standard.set(saved, forKey: "undeletablePaths.v1") }
        }

        let dir = makeSandbox()
        let f = dir.appendingPathComponent("cứng-đầu.bin")
        FileManager.default.createFile(atPath: f.path, contents: Data(repeating: 0x48, count: 2048))
        let scanner = SystemJunkScanner()

        check("bình thường thì vẫn liệt kê",
              scanner.makeItem(f, cancel: CancelToken()) != nil)

        memory.record(f)
        check("đã nhớ là không xoá được thì bỏ qua",
              scanner.makeItem(f, cancel: CancelToken()) == nil)
        check("nhớ cả sau khi đọc lại đường dẫn", memory.contains(f))

        try? FileManager.default.removeItem(at: f)
        memory.forgetMissing()
        check("mục biến mất thì quên đi", !memory.contains(f))
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

    // MARK: Bộ nhớ đệm nằm rải

    private static func testScatteredCaches() {
        print("[ScatteredCaches] cache ngoài ~/Library/Caches")
        let fm = FileManager.default
        let appDir = FileUtils.homePath("Application Support/XCleanerSelfTestApp")
        let realAppDir = FileUtils.homePath("Library/Application Support/XCleanerSelfTestApp")
        _ = appDir
        let groupDir = FileUtils.homePath("Library/Group Containers/group.xcleaner.selftest")

        let cacheDirs = [realAppDir.appendingPathComponent("Cache"),
                         realAppDir.appendingPathComponent("Code Cache"),
                         realAppDir.appendingPathComponent("CachedData"),
                         groupDir.appendingPathComponent("Library/Caches")]
        let dataDir = realAppDir.appendingPathComponent("User")   // dữ liệu thật, không được đụng

        for d in cacheDirs + [dataDir] {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
            fm.createFile(atPath: d.appendingPathComponent("x.bin").path,
                          contents: Data(repeating: 7, count: 64 * 1024))
        }
        defer {
            try? fm.removeItem(at: realAppDir)
            try? fm.removeItem(at: groupDir)
        }

        let items = SystemJunkScanner().scatteredCaches(cancel: CancelToken())
        let paths = Set(items.map(\.url.path))
        for d in cacheDirs {
            check("tìm ra \(d.lastPathComponent) của app", paths.contains(d.path))
        }
        check("không đụng thư mục dữ liệu của app", !paths.contains(dataDir.path))
        check("chỉ dọn ruột, giữ lại thư mục",
              items.filter { cacheDirs.map(\.path).contains($0.url.path) }
                   .allSatisfy(\.emptyContentsOnly))
    }

    // MARK: Danh sách mở gần đây

    private static func testRecentLists() {
        print("[RecentLists] danh sách mở gần đây")
        let fm = FileManager.default
        let base = makeSandbox()
        defer { try? fm.removeItem(at: base) }

        let perApp = base.appendingPathComponent("com.apple.LSSharedFileList.ApplicationRecentDocuments")
        try? fm.createDirectory(at: perApp, withIntermediateDirectories: true)

        let blob = Data(repeating: 3, count: 4096)
        for f in ["com.apple.LSSharedFileList.RecentDocuments.sfl3",
                  "com.apple.LSSharedFileList.RecentApplications.sfl3",
                  "com.apple.LSSharedFileList.FavoriteItems.sfl3",
                  "com.apple.LSSharedFileList.FavoriteVolumes.sfl3"] {
            fm.createFile(atPath: base.appendingPathComponent(f).path, contents: blob)
        }
        fm.createFile(atPath: perApp.appendingPathComponent("com.apple.TextEdit.sfl3").path,
                      contents: blob)

        let items = SystemJunkScanner().recentLists(root: base, cancel: CancelToken())
        let names = Set(items.map(\.url.lastPathComponent))

        check("tìm ra tài liệu mở gần đây",
              names.contains("com.apple.LSSharedFileList.RecentDocuments.sfl3"))
        check("tìm ra ứng dụng mở gần đây",
              names.contains("com.apple.LSSharedFileList.RecentApplications.sfl3"))
        check("tìm ra danh sách riêng của từng app",
              names.contains("com.apple.TextEdit.sfl3"))
        check("KHÔNG đụng mục yêu thích Finder",
              !names.contains("com.apple.LSSharedFileList.FavoriteItems.sfl3"))
        check("KHÔNG đụng ổ đĩa yêu thích",
              !names.contains("com.apple.LSSharedFileList.FavoriteVolumes.sfl3"))
        check("mặc định không chọn sẵn", items.allSatisfy { !$0.defaultSelected })
        check("xoá cả tệp chứ không chỉ dọn ruột", items.allSatisfy { !$0.emptyContentsOnly })
    }

    // MARK: Tệp trùng lặp

    @MainActor
    private static func testDuplicates() {
        print("[Duplicates] so khớp nội dung")
        let fm = FileManager.default
        let dir = makeSandbox()

        // Ba bản giống hệt nhau, tên khác nhau, một bản nằm sâu hơn
        let payload = Data((0..<(2 * 1024 * 1024)).map { UInt8($0 % 251) })
        let deep = dir.appendingPathComponent("sâu/hơn")
        try? fm.createDirectory(at: deep, withIntermediateDirectories: true)
        let copies = [dir.appendingPathComponent("a.bin"),
                      dir.appendingPathComponent("bản sao.bin"),
                      deep.appendingPathComponent("c.bin")]
        for u in copies { fm.createFile(atPath: u.path, contents: payload) }

        // Cùng kích thước nhưng khác nội dung — không được gộp chung
        var twist = payload
        twist[twist.count - 1] = twist[twist.count - 1] &+ 1
        let sameSize = dir.appendingPathComponent("khác-ruột.bin")
        fm.createFile(atPath: sameSize.path, contents: twist)

        // Dưới ngưỡng, và nằm trong thư mục bị bỏ qua
        fm.createFile(atPath: dir.appendingPathComponent("bé.bin").path,
                      contents: Data(repeating: 9, count: 500))
        let skipped = dir.appendingPathComponent("node_modules")
        try? fm.createDirectory(at: skipped, withIntermediateDirectories: true)
        fm.createFile(atPath: skipped.appendingPathComponent("a.bin").path, contents: payload)

        var opts = DuplicateScanner.Options()
        opts.roots = [dir]
        opts.minimumSize = 1024 * 1024
        let sets = DuplicateScanner().scan(options: opts, cancel: CancelToken()) { _ in }

        check("tìm đúng một nhóm trùng", sets.count == 1, "(được \(sets.count))")
        guard let set = sets.first else { try? fm.removeItem(at: sandbox); return }
        check("nhóm có đúng ba bản", set.files.count == 3, "(được \(set.files.count))")
        check("không gộp tệp cùng cỡ khác ruột",
              !set.files.contains { $0.lastPathComponent == "khác-ruột.bin" })
        check("bỏ qua node_modules", !set.files.contains { $0.path.contains("node_modules") })
        check("tính đúng chỗ lấy lại được", set.reclaimable == set.size * 2)

        // Chọn tự động: giữ lại bản đường dẫn ngắn nhất
        let store = DuplicateStore(settings: AppSettings())
        store.sets = sets
        store.autoSelect()
        check("tự chọn để lại đúng một bản", store.selected.count == 2,
              "(chọn \(store.selected.count))")
        let kept = set.files.first { !store.selected.contains($0) }
        check("bản giữ lại là bản ở đường dẫn ngắn nhất",
              kept == set.files.min(by: { $0.path.count < $1.path.count }))

        // Không cho phép bỏ hết cả nhóm
        if let keepURL = kept { store.toggle(keepURL, in: set) }
        check("không cho xoá sạch cả nhóm", store.selected.count == 2,
              "(chọn \(store.selected.count))")

        try? fm.removeItem(at: sandbox)
    }

    // MARK: Tệp lớn & cũ

    private static func testLargeOld() {
        print("[LargeOld] tìm tệp lớn")
        let fm = FileManager.default
        let dir = makeSandbox()

        let big = dir.appendingPathComponent("phim.mp4")
        let medium = dir.appendingPathComponent("bộ-cài.dmg")
        let small = dir.appendingPathComponent("nhỏ.txt")
        fm.createFile(atPath: big.path, contents: Data(repeating: 1, count: 5 * 1024 * 1024))
        fm.createFile(atPath: medium.path, contents: Data(repeating: 2, count: 2 * 1024 * 1024))
        fm.createFile(atPath: small.path, contents: Data(repeating: 3, count: 1024))

        // Nằm trong thư mục cố tình bỏ qua
        for skip in ["node_modules", "Library", ".git"] {
            let sub = dir.appendingPathComponent(skip)
            try? fm.createDirectory(at: sub, withIntermediateDirectories: true)
            fm.createFile(atPath: sub.appendingPathComponent("to.bin").path,
                          contents: Data(repeating: 4, count: 5 * 1024 * 1024))
        }

        // Một tệp cũ hẳn để kiểm tra cờ "lâu không dùng"
        let old = dir.appendingPathComponent("cũ.zip")
        fm.createFile(atPath: old.path, contents: Data(repeating: 5, count: 3 * 1024 * 1024))
        let longAgo = Date().addingTimeInterval(-400 * 86_400)
        try? fm.setAttributes([.modificationDate: longAgo], ofItemAtPath: old.path)

        var opts = LargeOldScanner.Options()
        opts.roots = [dir]
        opts.minimumSize = 1024 * 1024
        let found = LargeOldScanner().scan(options: opts, cancel: CancelToken()) { _ in }

        let names = found.map(\.url.lastPathComponent)
        check("tìm đủ ba tệp lớn", found.count == 3, "(được \(found.count): \(names))")
        check("bỏ qua tệp nhỏ", !names.contains("nhỏ.txt"))
        check("bỏ qua thư mục node_modules/Library/.git",
              !found.contains { $0.url.path.contains("node_modules")
                               || $0.url.path.contains("/Library/")
                               || $0.url.path.contains("/.git/") })
        check("sắp theo dung lượng giảm dần",
              found.map(\.size) == found.map(\.size).sorted(by: >))
        check("nhận ra định dạng video",
              found.first { $0.url.lastPathComponent == "phim.mp4" }?.kind == "Video")
        check("nhận ra bộ cài",
              found.first { $0.url.lastPathComponent == "bộ-cài.dmg" }?.kind == "Nén / bộ cài")
        check("đánh dấu tệp sửa từ hơn nửa năm trước là cũ",
              found.first { $0.url.lastPathComponent == "cũ.zip" }?.isOld == true)
        check("tệp vừa tạo thì không bị coi là cũ",
              found.first { $0.url.lastPathComponent == "phim.mp4" }?.isOld == false)

        try? fm.removeItem(at: sandbox)
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

    private static func testStartup() {
        print("[Startup] mục khởi động")
        let fm = FileManager.default
        let dir = makeSandbox()
        let scanner = StartupScanner()

        // Một agent bình thường, chạy ngay khi đăng nhập.
        let normal = dir.appendingPathComponent("com.acme.updater.plist")
        let normalPlist: [String: Any] = [
            "Label": "com.acme.updater",
            "ProgramArguments": ["/bin/sh", "-c", "echo hi"],
            "RunAtLoad": true,
            "StartInterval": 3600
        ]
        (normalPlist as NSDictionary).write(to: normal, atomically: true)

        // Một agent trỏ tới chương trình đã bị xoá.
        let orphan = dir.appendingPathComponent("com.gone.helper.plist")
        (["Label": "com.gone.helper",
          "Program": dir.appendingPathComponent("khong-ton-tai").path] as NSDictionary)
            .write(to: orphan, atomically: true)

        let a = scanner.read(normal, domain: .userAgent, loaded: ["com.acme.updater": 42],
                             disabled: [])
        check("đọc được nhãn trong plist", a?.label == "com.acme.updater")
        check("thấy chương trình được chạy", a?.program == "/bin/sh")
        check("biết là đang chạy", a?.isRunning == true)
        check("biết chu kỳ lặp lại", a?.intervalSeconds == 3600)
        check("không nhầm là rác", a?.isOrphan == false)
        check("đọc được chi tiết", a?.detailsHidden == false)

        let b = scanner.read(orphan, domain: .userAgent, loaded: [:],
                             disabled: ["com.gone.helper"])
        check("nhận ra chương trình không còn", b?.isOrphan == true)
        check("nhận ra mục đang tắt", b?.isDisabled == true)
        check("chưa nạp thì không báo đang chạy", b?.isRunning == false)

        // Tệp không đọc được vẫn phải hiện ra, nhãn suy từ tên tệp.
        let unreadable = dir.appendingPathComponent("com.vendor.daemon.plist")
        try? "khong-phai-plist".write(to: unreadable, atomically: true, encoding: .utf8)
        let c = scanner.read(unreadable, domain: .daemon, loaded: [:], disabled: [])
        check("plist không đọc được vẫn hiện ra", c != nil)
        check("lấy nhãn từ tên tệp", c?.label == "com.vendor.daemon")
        check("đánh dấu là chưa đọc được chi tiết", c?.detailsHidden == true)
        check("daemon thì cần quyền quản trị", c?.needsAdmin == true)

        check("mục của Apple bị khoá lại",
              scanner.read({ let u = dir.appendingPathComponent("com.apple.something.plist")
                             (["Label": "com.apple.something"] as NSDictionary)
                                 .write(to: u, atomically: true); return u }(),
                           domain: .globalAgent, loaded: [:], disabled: [])?.isApple == true)

        // Hai kiểu in ra của `launchctl print-disabled` qua các phiên bản macOS.
        let cũ = LaunchControl.parseDisabled("""
        disabled services = {
        \t"com.a.one" => true
        \t"com.a.two" => false
        }
        """)
        check("đọc được kiểu true/false", cũ == ["com.a.one"])
        let mới = LaunchControl.parseDisabled("""
        disabled services = {
        \t"com.b.one" => disabled
        \t"com.b.two" => enabled
        }
        """)
        check("đọc được kiểu disabled/enabled", mới == ["com.b.one"])

        // `launchctl print` là nguồn duy nhất biết daemon có đang chạy không: `launchctl list`
        // chạy dưới quyền người dùng không hề thấy daemon hệ thống.
        let printed = LaunchControl.parsePrint("""
        system/com.vendor.helper = {
        \tactive count = 2
        \tpath = /Library/LaunchDaemons/com.vendor.helper.plist
        \tstate = running

        \tprogram = /Library/PrivilegedHelperTools/com.vendor.helper
        }
        """)
        check("đọc được trạng thái đang chạy của daemon", printed.running == true)
        check("lấy được đường dẫn chương trình từ launchd",
              printed.program == "/Library/PrivilegedHelperTools/com.vendor.helper")
        // Output thật còn kèm vài dòng `state` của endpoint con; lấy nhầm dòng cuối là báo
        // một daemon đang chạy thành đã dừng.
        let noisy = LaunchControl.parsePrint("""
        system/com.vendor.helper = {
        \tstate = running
        \tendpoints = {
        \t\t"com.vendor.xpc" = {
        \t\t\tstate = active
        \t\t}
        \t}
        \tjob state = running
        }
        """)
        check("bỏ qua các dòng state của endpoint con", noisy.running == true)
        let stopped = LaunchControl.parsePrint("system/x = {\n\tstate = not running\n}")
        check("biết daemon đang dừng", stopped.running == false)

        check("agent không đòi mật khẩu", LaunchControl.Domain.userAgent.needsAdmin == false)
        check("agent toàn máy cũng không đòi mật khẩu",
              LaunchControl.Domain.globalAgent.needsAdmin == false)
        check("dịch vụ nền thì có", LaunchControl.Domain.daemon.needsAdmin == true)

        try? fm.removeItem(at: dir)
    }

    /// Thư mục chứa một `.app` con bên trong: dung lượng phải tính cả ruột cái `.app` đó.
    /// Chrome, Xcode và hàng loạt app khác đặt helper dạng `.app` lồng bên trong.
    private static func testNestedPackageSize() {
        print("[FileUtils] dung lượng có gói lồng bên trong")
        let fm = FileManager.default
        let dir = makeSandbox()
        let outer = dir.appendingPathComponent("Outer")
        let inner = outer.appendingPathComponent("Inner.app/Contents")
        try? fm.createDirectory(at: inner, withIntermediateDirectories: true)
        let four = Data(count: 4 * 1024 * 1024)
        let one = Data(count: 1024 * 1024)
        try? four.write(to: inner.appendingPathComponent("big.bin"))
        try? one.write(to: outer.appendingPathComponent("plain.bin"))

        let measured = FileUtils.size(of: outer)
        check("đếm cả ruột của gói lồng bên trong",
              measured >= 5 * 1024 * 1024,
              "đo được \(measured) byte, đáng lẽ ≥ 5 MB")

        try? fm.removeItem(at: dir)
    }

    /// Hai đường dẫn trỏ vào **cùng một tệp vật lý** (hard link) không phải là bản trùng:
    /// xoá một cái chẳng giải phóng byte nào, mà người dùng lại tưởng vừa dọn được.
    private static func testHardLinkDuplicates() {
        print("[Duplicates] liên kết cứng")
        let fm = FileManager.default
        let dir = makeSandbox()
        let a = dir.appendingPathComponent("a.bin")
        let b = dir.appendingPathComponent("b.bin")
        let c = dir.appendingPathComponent("c.bin")
        let payload = Data(repeating: 7, count: 2 * 1024 * 1024)
        try? payload.write(to: a)
        try? fm.linkItem(at: a, to: b)          // cùng một tệp, hai tên
        try? payload.write(to: c)               // bản sao thật

        var opts = DuplicateScanner.Options()
        opts.roots = [dir]
        opts.minimumSize = 1024
        let sets = DuplicateScanner().scan(options: opts, cancel: CancelToken()) { _ in }

        let paths = Set(sets.flatMap { $0.files.map(\.lastPathComponent) })
        check("không coi liên kết cứng là bản trùng", !(paths.contains("a.bin") && paths.contains("b.bin")),
              "gộp cả a.bin lẫn b.bin vào một nhóm")
        check("vẫn tìm ra bản sao thật", paths.contains("c.bin"))

        try? fm.removeItem(at: dir)
    }

    /// Bật "chuyển vào Thùng rác" thì nội dung thư mục đệm phải đi vào Thùng rác,
    /// còn chính thư mục vẫn ở lại (app không tự tạo lại vài thư mục đệm).
    private static func testTrashKeepsFolder() {
        print("[Remover] dọn ruột nhưng vào Thùng rác")
        let fm = FileManager.default
        let dir = makeSandbox()
        let cacheDir = dir.appendingPathComponent("SomeApp/Caches")
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let inside = cacheDir.appendingPathComponent("blob.bin")
        try? Data(repeating: 1, count: 4096).write(to: inside)

        let item = CleanItem(url: cacheDir, size: 4096, emptyContentsOnly: true)
        let outcome = Remover.perform(
            Remover.Request(items: [item], moveToTrash: true, adminPrompt: ""),
            progress: { _, _ in })

        check("thư mục đệm vẫn còn", FileUtils.isDirectory(cacheDir))
        check("ruột đã được dọn", FileUtils.children(of: cacheDir).isEmpty)
        check("báo là đã dọn", outcome.removedCount == 1)
        // Không thể liệt kê ~/.Trash để kiểm (macOS chặn nếu chưa có Toàn quyền truy cập đĩa),
        // nên hỏi chính kết quả: mục này đi vào Thùng rác hay bị xoá thẳng.
        check("tệp đi vào Thùng rác chứ không bị xoá thẳng", outcome.trashedCount == 1,
              "trashedCount = \(outcome.trashedCount)")

        try? fm.removeItem(at: dir)
    }

    private static func testUpdater() {
        print("[Update] kiểm tra cập nhật")
        let fm = FileManager.default

        check("1.2.10 mới hơn 1.2.9",
              SemanticVersion("1.2.9") < SemanticVersion("1.2.10"))
        check("bỏ được chữ v ở đầu thẻ", SemanticVersion("v2.0") == SemanticVersion("2.0.0"))
        check("cùng phiên bản thì không phải bản mới",
              !(SemanticVersion("1.0.0") < SemanticVersion("1.0")))
        check("số lẻ ở cuối vẫn tính là mới hơn",
              SemanticVersion("1.0") < SemanticVersion("1.0.1"))

        let plain = UpdateService.plainText("## Có gì mới\n- Thêm **Kiểm tra cập nhật…** vào menu\n- Xem [trang phát hành](https://example.com)")
        check("gỡ được cú pháp Markdown khỏi ghi chú",
              plain == "Có gì mới\n• Thêm Kiểm tra cập nhật… vào menu\n• Xem trang phát hành",
              "nhận được: \(plain)")

        // Chốt an toàn: gói tải về phải tự nhận mình là xCleaner, nếu không thì dừng trước
        // khi có bất cứ thứ gì bị chép đè.
        let dir = makeSandbox()
        let fakeApp = dir.appendingPathComponent("Something.app/Contents")
        try? fm.createDirectory(at: fakeApp, withIntermediateDirectories: true)
        (["CFBundleIdentifier": "com.kegian.malware",
          "CFBundleName": "Something"] as NSDictionary)
            .write(to: fakeApp.appendingPathComponent("Info.plist"), atomically: true)

        let zip = dir.appendingPathComponent("payload.zip")
        let pack = Process()
        pack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        pack.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent",
                          dir.appendingPathComponent("Something.app").path, zip.path]
        try? pack.run()
        pack.waitUntilExit()

        var refused = false
        do { try UpdateService.install(archive: zip) }
        catch { refused = true }
        check("từ chối gói không phải xCleaner", refused,
              "gói lạ vẫn được cài đè lên app")
        check("không tạo script thay thế khi đã từ chối",
              !FileUtils.exists(dir.appendingPathComponent("swap.sh")))

        try? fm.removeItem(at: dir)
    }
}
#endif
