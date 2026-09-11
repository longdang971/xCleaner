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
}
#endif
