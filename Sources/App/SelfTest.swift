#if DEBUG
import Foundation
import AppKit
import SwiftUI

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
        testTrashOfTrash()
        testHiddenIsNotGone()
        testRootBatchEvidence()
        testRegressionGuards()
        testUpdater()
        testCountingValue()
        testPageGeometry()
        testBottomStripGate()
        testIntroBadges()
        testSmartDeleteMemory()
        testTrashWatcher()
        testLaunchAgent()
        testSmartDeleteController()
        testQuitPrompt()
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

        // `standardizingPath` tự bỏ `/private` — nhật ký xoay vòng từng bị chặn vì thế.
        check("chấp nhận nhật ký xoay vòng trong /private/var/log",
              SafetyGuard.validate(URL(fileURLWithPath: "/private/var/log/system.log.0.gz"),
                                   requireExists: false) == nil)
        check("chuẩn hoá giữ nguyên dạng /private",
              SafetyGuard.standardized(URL(fileURLWithPath: "/var/log/x")).path == "/private/var/log/x")
        for p in ["/var/db/sudo/ts", "/private/var/db/sudo/ts", "/etc/passwd", "/var/vm/sleepimage",
                  "/var/db/dslocal/nodes"] {
            check("vẫn từ chối \(p)",
                  SafetyGuard.validate(URL(fileURLWithPath: p), requireExists: false) != nil)
        }
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

        // Mức quyền đổi thì danh sách cũ không còn đúng nữa: phần lớn thứ "không xoá nổi" là
        // do chưa có Toàn quyền truy cập đĩa, cấp quyền xong là dọn được.
        let g = dir.appendingPathComponent("sau-khi-cấp-quyền.bin")
        FileManager.default.createFile(atPath: g.path, contents: Data(repeating: 0x4A, count: 1024))
        memory.record(g)
        UserDefaults.standard.set(!FileUtils.hasFullDiskAccess, forKey: "undeletableRecordedWithFullDisk")
        memory.refresh()
        check("đổi mức quyền thì quên hết", !memory.contains(g))
        try? FileManager.default.removeItem(at: g)
    }

    /// Bật "chuyển vào Thùng rác" rồi dọn chính Thùng rác thì phải xoá thẳng.
    ///
    /// `trashItem` trên thứ đã nằm trong Thùng rác **không ném lỗi**: nó trả về thành công
    /// kèm đúng đường dẫn cũ và để nguyên tệp ở đó (đo trên máy thật). Tin vào nó là app báo
    /// đã dọn trong khi Thùng rác còn nguyên.
    private static func testTrashOfTrash() {
        print("[Remover] dọn Thùng rác khi đang bật chuyển-vào-Thùng-rác")
        let fm = FileManager.default
        let f = FileUtils.homePath(".Trash/xcleaner-selftest-trash.bin")
        fm.createFile(atPath: f.path, contents: Data(repeating: 0x49, count: 2048))
        guard FileUtils.exists(f) else {
            check("dựng được tệp trong Thùng rác", false, "(macOS chặn ghi vào ~/.Trash)")
            return
        }
        let item = CleanItem(url: f, size: 2048, isDirectory: false)
        let outcome = Remover.perform(Remover.Request(items: [item], moveToTrash: true,
                                                      adminPrompt: "test")) { _, _ in }
        check("tệp đã biến mất khỏi Thùng rác", !FileUtils.exists(f))
        check("báo đã dọn", outcome.removedCount == 1, "(\(outcome.removedCount))")
        check("không báo lỗi", outcome.failures.isEmpty)
        try? fm.removeItem(at: f)
    }

    /// "Không được nhìn" không bao giờ được hiểu thành "đã xoá".
    ///
    /// `fileExists` trả về `false` cho tệp còn nguyên nằm trong thư mục app không được đi vào,
    /// và cho liên kết hỏng vẫn nằm trên đĩa. Engine từng kết luận "đã dọn" bằng chính nó.
    private static func testHiddenIsNotGone() {
        print("[Remover] không được nhìn thì không phải đã xoá")
        let dir = makeSandbox()
        let fm = FileManager.default

        let locked = dir.appendingPathComponent("khoá")
        try? fm.createDirectory(at: locked, withIntermediateDirectories: true)
        let inside = locked.appendingPathComponent("còn-nguyên.bin")
        fm.createFile(atPath: inside.path, contents: Data(repeating: 0x4B, count: 4096))
        chmod(locked.path, 0o000)
        defer { chmod(locked.path, 0o700) }

        check("tệp trong thư mục khoá: không phải 'không có'",
              FileUtils.presence(inside) == .unknown, "(\(FileUtils.presence(inside)))")
        check("tệp trong thư mục khoá: không coi là đã xoá", !FileUtils.isGone(inside))
        var saysMissing = false
        if case .notExist? = SafetyGuard.validate(inside) { saysMissing = true }
        check("hàng rào an toàn không báo 'không tồn tại'", !saysMissing)
        check("isCleared không tin là đã sạch",
              !Remover.isCleared(CleanItem(url: inside, size: 4096, isDirectory: false)))
        let lockedChild = locked.appendingPathComponent("thư-mục-con")
        check("thư mục con của thư mục khoá là bị chặn, không phải mất",
              FileUtils.directoryState(lockedChild) == .blocked)

        // Không gọi Remover.perform ở đây: mục này sẽ bị đẩy sang đợt root và bật hộp mật khẩu
        // thật. Chặn được `.notExist` ở trên là đã chặn đúng đường Remover từng báo "đã dọn".
        chmod(locked.path, 0o700)

        // Liên kết hỏng: bản thân nó vẫn nằm trên đĩa.
        let link = dir.appendingPathComponent("liên-kết-hỏng")
        try? fm.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent("không-có"))
        check("liên kết hỏng vẫn được thấy là có mặt", FileUtils.presence(link) == .present)
        check("liên kết hỏng chưa xoá thì không coi là đã xoá", !FileUtils.isGone(link))
        try? fm.removeItem(at: link)
        check("xoá rồi thì mới là đã xoá", FileUtils.isGone(link))
    }

    /// Chạy **đúng lệnh mà đợt root sẽ chạy**, chỉ khác là bằng `/bin/sh` dưới quyền người dùng,
    /// để kiểm được cả tầng xác minh của root mà không phải bật hộp mật khẩu.
    ///
    /// Điều cần chứng minh: một mục chỉ được báo đã xoá khi có lời khẳng định cho đúng nó, và
    /// mọi sự cố — không xoá nổi, không được nhìn, output bị cắt, bị đổi xuống dòng — đều ngả
    /// về phía "chưa xoá".
    private static func testRootBatchEvidence() {
        print("[PrivilegedRunner] lệnh root chỉ báo đã xoá khi có bằng chứng")
        let dir = makeSandbox()
        let fm = FileManager.default
        func file(_ rel: String) -> URL {
            let u = dir.appendingPathComponent(rel)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: u.path, contents: Data(repeating: 0x4C, count: 512))
            return u
        }

        let plain = file("thường.bin")
        let weird = file("tên \"lạ\" $(touch PWNED) `x` 'y'\nxuống-dòng.bin")
        let stuck = file("cha-chỉ-đọc/kẹt.bin")                       // cha 0555: không xoá được
        let hidden = file("cha-khoá/giấu.bin")                        // cha 0000: không được nhìn
        let link = dir.appendingPathComponent("liên-kết-hỏng")
        try? fm.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent("không-có"))
        let emptyDir = dir.appendingPathComponent("dọn-ruột")
        _ = file("dọn-ruột/a.bin"); _ = file("dọn-ruột/.ẩn")
        let stuckDir = dir.appendingPathComponent("dọn-ruột-kẹt")
        _ = file("dọn-ruột-kẹt/b.bin")
        // Liên kết tới một thư mục đầy: `find` không đi theo nên thấy "rỗng".
        let fullTarget = dir.appendingPathComponent("đầy")
        let keep = file("đầy/giữ.bin")
        let linkDir = dir.appendingPathComponent("dọn-ruột-là-liên-kết")
        try? fm.createSymbolicLink(at: linkDir, withDestinationURL: fullTarget)

        chmod(dir.appendingPathComponent("cha-chỉ-đọc").path, 0o555)
        chmod(dir.appendingPathComponent("dọn-ruột-kẹt").path, 0o555)
        chmod(dir.appendingPathComponent("cha-khoá").path, 0o000)
        defer {
            for d in ["cha-chỉ-đọc", "dọn-ruột-kẹt", "cha-khoá"] {
                chmod(dir.appendingPathComponent(d).path, 0o755)
            }
        }

        guard let batch = try? PrivilegedRunner.makeBatch(
                remove: [plain, weird, stuck, hidden, link],
                emptyContents: [emptyDir, stuckDir, linkDir]) else {
            check("dựng được lệnh", false); return
        }
        defer { for m in batch.manifests { try? fm.removeItem(at: m) } }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Đúng như AuthorizationRunner chạy: `/bin/sh -c`.
        proc.arguments = ["-c", batch.command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try? proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        let r = PrivilegedRunner.parse(out, attempted: batch.attempted)

        func key(_ u: URL) -> String { SafetyGuard.standardized(u).path }
        check("tệp thường: khẳng định đã mất", r.confirmedGone.contains(key(plain)))
        check("tên có nháy/$()/backtick/xuống dòng: khẳng định đã mất",
              r.confirmedGone.contains(key(weird)), "(\(out.prefix(300)))")
        check("không lệnh chèn nào chạy",
              !fm.fileExists(atPath: dir.appendingPathComponent("PWNED").path)
              && !fm.fileExists(atPath: FileManager.default.currentDirectoryPath + "/PWNED"))
        check("liên kết hỏng: khẳng định đã mất (đã xoá được)", r.confirmedGone.contains(key(link)))
        check("không xoá nổi: KHÔNG báo đã mất", !r.confirmedGone.contains(key(stuck)))
        check("không xoá nổi: khẳng định vẫn còn", r.confirmedLeft.contains(key(stuck)))
        check("không được nhìn: KHÔNG báo đã mất", !r.confirmedGone.contains(key(hidden)))
        check("không được nhìn: không bị ghi là còn (không biết thì không kết luận)",
              !r.confirmedLeft.contains(key(hidden)))
        check("dọn ruột (kể cả tệp ẩn): khẳng định đã rỗng", r.confirmedGone.contains(key(emptyDir)))
        check("dọn ruột không nổi: KHÔNG báo đã rỗng", !r.confirmedGone.contains(key(stuckDir)))
        check("dọn ruột một liên kết: KHÔNG báo đã rỗng", !r.confirmedGone.contains(key(linkDir)),
              "(find không đi theo liên kết nên thấy rỗng)")
        check("dọn ruột một liên kết: nơi được trỏ tới còn nguyên", fm.fileExists(atPath: keep.path))

        // Đường osascript đổi `\n` thành `\r`: bằng chứng vẫn phải đọc ra y như vậy.
        let viaAppleScript = PrivilegedRunner.parse(out.replacingOccurrences(of: "\n", with: "\r"),
                                                    attempted: batch.attempted)
        check("xuống dòng kiểu \\r vẫn đọc đúng",
              viaAppleScript.confirmedGone == r.confirmedGone
              && viaAppleScript.confirmedLeft == r.confirmedLeft)

        // Lệnh chết giữa chừng / output bị cắt: không tin tức thì không được báo là đã xoá.
        let truncated = PrivilegedRunner.parse(String(out.prefix(10)), attempted: batch.attempted)
        check("output bị cắt: không báo mục nào đã xoá", truncated.confirmedGone.isEmpty)
        let empty = PrivilegedRunner.parse("", attempted: batch.attempted)
        check("không có output: không báo mục nào đã xoá", empty.confirmedGone.isEmpty)
        // Báo cho một đường dẫn không nằm trong lệnh thì bỏ qua.
        let forged = PrivilegedRunner.parse("xcleaner-gone\t2f6574632f706173737764\n",
                                            attempted: batch.attempted)
        check("bằng chứng cho đường dẫn ngoài lệnh bị bỏ qua", forged.confirmedGone.isEmpty)
    }

    /// Chặn những tác dụng phụ mà chính các bản vá trước đã gây ra.
    private static func testRegressionGuards() {
        print("[Hồi quy] tác dụng phụ của các bản vá trước")
        let dir = makeSandbox()
        let fm = FileManager.default

        // Sổ "không xoá được" không được ghi thứ hệ thống vừa tạo lại.
        let cutoff = Date().addingTimeInterval(-2)
        let recreated = dir.appendingPathComponent("đệm-tạo-lại")
        try? fm.createDirectory(at: recreated, withIntermediateDirectories: true)
        fm.createFile(atPath: recreated.appendingPathComponent("mới.bin").path, contents: Data([1]))
        check("thư mục vừa được tạo lại: không phải thứ cũ còn sót",
              !Remover.hasOldContent(CleanItem(url: recreated, size: 1), before: cutoff))
        check("dọn ruột mà chỉ còn tệp mới: không phải thứ cũ còn sót",
              !Remover.hasOldContent(CleanItem(url: recreated, size: 1, emptyContentsOnly: true),
                                     before: cutoff))
        let future = Date().addingTimeInterval(3600)
        check("thứ đã có từ trước mốc: đúng là còn sót",
              Remover.hasOldContent(CleanItem(url: recreated, size: 1), before: future))
        check("dọn ruột còn tệp cũ: đúng là còn sót",
              Remover.hasOldContent(CleanItem(url: recreated, size: 1, emptyContentsOnly: true),
                                    before: future))
        let locked = dir.appendingPathComponent("khoá-sổ")
        try? fm.createDirectory(at: locked, withIntermediateDirectories: true)
        fm.createFile(atPath: locked.appendingPathComponent("x").path, contents: Data([1]))
        chmod(locked.path, 0o000)
        check("không nhìn được thì không ghi sổ",
              !Remover.hasOldContent(CleanItem(url: locked, size: 1, emptyContentsOnly: true),
                                     before: future))
        chmod(locked.path, 0o755)

        // "Dọn ruột" một liên kết tượng trưng: không được xoá ruột nơi nó trỏ tới.
        let target = dir.appendingPathComponent("nơi-được-trỏ-tới")
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        let precious = target.appendingPathComponent("quý.bin")
        fm.createFile(atPath: precious.path, contents: Data(repeating: 0x50, count: 256))
        let link = dir.appendingPathComponent("đệm-là-liên-kết")
        try? fm.createSymbolicLink(at: link, withDestinationURL: target)
        var ok: Bool?
        let outcome = Remover.perform(
            Remover.Request(items: [CleanItem(url: link, size: 256, emptyContentsOnly: true)],
                            moveToTrash: false, adminPrompt: ""),
            progress: { _, _ in }, itemFinished: { _, r in ok = r })
        // Nhánh thường vốn không đi theo liên kết (đã đo), nên đây là chốt chặn cho thứ tự
        // kiểm tra chứ không phải cho việc xoá; lỗi thật nằm ở tầng root, test ở trên.
        check("ruột của nơi được trỏ tới còn nguyên", fm.fileExists(atPath: precious.path))
        check("không báo là đã dọn", ok == false && outcome.removedCount == 0,
              "(ok=\(String(describing: ok)), removed=\(outcome.removedCount))")

        // Liên kết trỏ vào vùng cấm dạng /private phải bị nhận ra.
        let sudoLink = dir.appendingPathComponent("trỏ-vào-sudo")
        try? fm.createSymbolicLink(at: sudoLink, withDestinationURL: URL(fileURLWithPath: "/private/var/db/sudo"))
        var escaped = false
        if case .symlinkEscape? = SafetyGuard.validate(sudoLink) { escaped = true }
        check("liên kết trỏ vào /private/var/db/sudo bị chặn", escaped,
              "(\(String(describing: SafetyGuard.validate(sudoLink))))")
    }

    // MARK: Hỏi thoát ứng dụng

    @MainActor
    private static func testQuitPrompt() {
        print("[Thoát app] chỉ hỏi ứng dụng có mục đang được chọn")
        let dir = makeSandbox()
        func item(_ n: String, _ cat: String, _ on: Bool) -> CleanItem {
            CleanItem(url: dir.appendingPathComponent(n), size: 1024,
                      isSelected: on, category: cat)
        }

        // Thẻ gộp "Trình duyệt": mỗi trình duyệt là một phần riêng.
        var merged = CleanGroup(
            id: "browsers", title: "Trình duyệt", subtitle: "", icon: "globe", safety: .safe,
            items: [item("chrome.bin", "Google Chrome", false),
                    item("safari.bin", "Safari", true)],
            categoryAppIDs: ["Google Chrome": "com.google.Chrome",
                             "Safari": "com.apple.Safari"])

        var ids = ScanStore.appIDsToQuit(in: [merged])
        check("bỏ chọn hết phần Chrome thì không hỏi Chrome",
              ids == ["com.apple.Safari"], "(được \(ids))")

        merged.items[0].isSelected = true
        ids = ScanStore.appIDsToQuit(in: [merged])
        check("chọn cả hai phần thì hỏi cả hai",
              Set(ids) == ["com.google.Chrome", "com.apple.Safari"], "(được \(ids))")

        merged.items[1].isSelected = false
        ids = ScanStore.appIDsToQuit(in: [merged])
        check("đổi sang chỉ chọn Chrome thì chỉ hỏi Chrome",
              ids == ["com.google.Chrome"], "(được \(ids))")

        for i in merged.items.indices { merged.items[i].isSelected = false }
        check("không chọn gì thì không hỏi ai",
              ScanStore.appIDsToQuit(in: [merged]).isEmpty)

        // Nhóm không chia phần thì vẫn rơi về ứng dụng của cả nhóm.
        let plain = CleanGroup(id: "g", title: "Một app", subtitle: "", icon: "gear",
                               safety: .safe, items: [item("x.bin", "", true)],
                               runningBundleID: "com.example.App",
                               appBundleID: "com.example.App")
        check("nhóm một ứng dụng vẫn hỏi đúng nó",
              ScanStore.appIDsToQuit(in: [plain]) == ["com.example.App"])
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
            ("Library/LaunchAgents", "\(bundleID).plist"),
            // Bốn chỗ nằm sâu hơn một tầng. Chúng là lý do AppCleaner từng tìm được nhiều hơn.
            ("Library/Caches/com.apple.helpd/Generated", "\(bundleID).help*1.0"),
            ("Library/Preferences/ByHost",
             "\(bundleID).00000000-1111-2222-3333-444444444444.plist"),
            ("Library/Application Support/CrashReporter", "\(appName)_selftest.plist"),
            ("Library/Logs/DiagnosticReports", "\(appName)_2026-09-21-000000_selftest.ips")
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
        // macOS 26 trở đi đặt đuôi .sfl4; .sfl3 là của các bản cũ. Phải bắt được cả hai,
        // và phải bắt theo tên chứ không theo đuôi — Apple còn đổi đuôi nữa.
        for f in ["com.apple.LSSharedFileList.RecentDocuments.sfl4",
                  "com.apple.LSSharedFileList.RecentApplications.sfl4",
                  "com.apple.LSSharedFileList.RecentServers.sfl3",
                  "com.apple.LSSharedFileList.ProjectsItems.sfl4",
                  "com.apple.LSSharedFileList.FavoriteItems.sfl4",
                  "com.apple.LSSharedFileList.FavoriteVolumes.sfl4"] {
            fm.createFile(atPath: base.appendingPathComponent(f).path, contents: blob)
        }
        fm.createFile(atPath: perApp.appendingPathComponent("com.apple.TextEdit.sfl4").path,
                      contents: blob)

        let items = SystemJunkScanner().recentLists(root: base, cancel: CancelToken())
        let names = Set(items.map(\.url.lastPathComponent))

        check("tìm ra tài liệu mở gần đây (.sfl4)",
              names.contains("com.apple.LSSharedFileList.RecentDocuments.sfl4"))
        check("tìm ra ứng dụng mở gần đây (.sfl4)",
              names.contains("com.apple.LSSharedFileList.RecentApplications.sfl4"))
        check("vẫn bắt được đuôi .sfl3 của macOS cũ",
              names.contains("com.apple.LSSharedFileList.RecentServers.sfl3"))
        check("tìm ra danh sách riêng của từng app",
              names.contains("com.apple.TextEdit.sfl4"))
        check("KHÔNG đụng mục yêu thích Finder",
              !names.contains("com.apple.LSSharedFileList.FavoriteItems.sfl4"))
        check("KHÔNG đụng ổ đĩa yêu thích",
              !names.contains("com.apple.LSSharedFileList.FavoriteVolumes.sfl4"))
        check("KHÔNG đụng danh sách Projects của Finder",
              !names.contains("com.apple.LSSharedFileList.ProjectsItems.sfl4"))
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

    /// Hiệu ứng đếm số ở màn dọn xong chỉ được chạy PHẦN SỐ, đơn vị phải đứng yên —
    /// nội suy thẳng byte rồi định dạng lại mỗi khung hình thì người dùng thấy
    /// "0 KB → 900 MB → 12,4 GB", đơn vị nhảy loạn giữa chừng.
    private static func testCountingValue() {
        print("[Fmt] đếm số ở màn dọn xong")

        // Bám theo locale của máy thay vì viết cứng "12,4": chính `sizeParts` sinh ra chuỗi này.
        let final = Fmt.sizeParts(12_400_000_000).value
        let parser = NumberFormatter()
        parser.numberStyle = .decimal
        let sep = parser.decimalSeparator ?? "."
        func number(_ s: String) -> Double? { parser.number(from: s)?.doubleValue }
        func decimals(_ s: String) -> Int {
            guard let r = s.range(of: sep) else { return 0 }
            return s[r.upperBound...].count
        }

        check("chạy hết đường thì trả đúng chuỗi cuối",
              Fmt.countingValue(finalValue: final, fraction: 1) == final,
              "(\(Fmt.countingValue(finalValue: final, fraction: 1)) ≠ \(final))")

        let half = Fmt.countingValue(finalValue: final, fraction: 0.5)
        check("nửa đường ra nửa giá trị",
              abs((number(half) ?? -1) - (number(final) ?? 0) / 2) < 0.06,
              "(\(half) so với \(final))")
        check("nửa đường giữ nguyên số chữ số thập phân",
              decimals(half) == decimals(final),
              "(\(half) so với \(final))")

        let start = Fmt.countingValue(finalValue: final, fraction: 0)
        check("đầu đường là số không", number(start) == 0, "(\(start))")
        check("số không vẫn giữ số chữ số thập phân", decimals(start) == decimals(final),
              "(\(start) so với \(final))")

        // Giá trị tròn ("512 MB") không được mọc thêm phần thập phân giữa chừng.
        let whole = Fmt.countingValue(finalValue: "512", fraction: 0.5)
        check("số nguyên vẫn là số nguyên", whole == "256", "(\(whole))")

        // Không phân tích được thì thà mất hiệu ứng còn hơn hiện sai số.
        check("chuỗi không phải số thì trả lại nguyên vẹn",
              Fmt.countingValue(finalValue: "—", fraction: 0.5) == "—")
    }
    /// Khuôn cắt của TRANG chỉ được phủ đúng vùng trang: không thò xuống dải trong suốt ở đáy,
    /// cũng không trùm lên dải thanh tiêu đề.
    ///
    /// Hai lỗi người dùng nhìn thấy khi đổi qua lại giữa hai mục KHÔNG có nút tròn (Gỡ ứng dụng
    /// và Khởi động cùng máy) đều từ đây mà ra:
    ///
    /// - Bướu tròn trong `PageClip` là đồ thừa từ hồi nút còn nằm trong trang. Nút nay do
    ///   `RootView` vẽ ở NGOÀI lớp bị đẩy, nên bướu ấy chẳng chừa đường cho ai nữa — nó chỉ
    ///   cho trang đang trượt vẽ lọt xuống dải trong suốt, thành một vòng tròn nội dung lơ
    ///   lửng trên desktop. Trang nào có nút thì nút với quầng sáng che mất nên không ai thấy.
    /// - Khuôn cũ bắt đầu từ mép trên cửa sổ, tức trùm luôn 46pt thanh tiêu đề. Trang đang bị
    ///   đẩy ra vẽ vào đó, và vì lò xo tắt dần theo hàm mũ nên mấy chục pt cuối bò rất lâu —
    ///   một vệt nội dung của trang cũ đứng lại ở đỉnh app gần một giây rồi mới tắt.
    private static func testPageGeometry() {
        print("[Bố cục] khuôn cắt trang và khuôn tấm nền")

        let rect = CGRect(x: 0, y: 0, width: 1140, height: 652)
        let page = PageClip().path(in: rect).boundingRect

        check("khuôn trang không thò xuống dưới tấm nền",
              page.maxY <= rect.maxY + 0.01,
              "(chạm tới \(page.maxY), đáy tấm nền \(rect.maxY))")
        check("khuôn trang chừa đúng dải thanh tiêu đề",
              abs(page.minY - Metrics.titleBarHeight) < 0.01,
              "(bắt đầu từ \(page.minY), cần \(Metrics.titleBarHeight))")
        check("khuôn trang vẫn rộng bằng cả vùng nội dung",
              abs(page.minX - rect.minX) < 0.01 && abs(page.maxX - rect.maxX) < 0.01,
              "(\(page.minX)…\(page.maxX))")

        // Khuôn của TẤM NỀN thì ngược lại: bướu tròn phải còn, vì chính nút tròn nằm ở đó.
        let card = CardShape().path(in: rect).boundingRect
        check("khuôn tấm nền vẫn chừa chỗ cho nút tròn thò ra",
              abs(card.maxY - (rect.maxY + Metrics.actionButtonHalo - 16)) < 0.01,
              "(chạm tới \(card.maxY), cần \(rect.maxY + Metrics.actionButtonHalo - 16))")
        check("dải trong suốt ở đáy cửa sổ đủ chứa bướu tròn",
              Metrics.windowBottomInset >= Metrics.actionButtonHalo - 16,
              "(\(Metrics.windowBottomInset) < \(Metrics.actionButtonHalo - 16))")
    }

    /// Dải trong suốt ở đáy cửa sổ phải cho cú bấm đi xuyên xuống app phía sau — trừ đúng cái
    /// nút tròn. Đo được trước khi sửa: đưa xCleaner lên trước rồi bấm vào giữa dải, app đứng
    /// trước vẫn là xCleaner; bấm ra ngoài khung cửa sổ cùng độ cao thì app sau lên ngay.
    private static func testBottomStripGate() {
        print("[Cửa sổ] dải trống ở đáy cho bấm xuyên qua")

        // Toạ độ AppKit: gốc góc DƯỚI-trái.
        let frame = CGRect(x: 500, y: 300, width: 1140, height: 752)
        let cardBottom = frame.minY + Metrics.windowBottomInset
        let buttonCenter = CGPoint(x: frame.midX + Metrics.sidebarWidth / 2, y: cardBottom + 16)
        func dead(_ p: CGPoint, hasButton: Bool = true) -> Bool {
            BottomStripMouseGate.isDeadZone(p, windowFrame: frame, hasButton: hasButton)
        }

        check("giữa dải trống: bấm xuyên qua",
              dead(CGPoint(x: frame.minX + 200, y: cardBottom - 40)))
        check("ngay trên mép tấm nền: vẫn là app",
              !dead(CGPoint(x: frame.minX + 200, y: cardBottom + 2)))
        check("tâm nút tròn: vẫn là app", !dead(buttonCenter))
        check("mép nút tròn: vẫn là app",
              !dead(CGPoint(x: buttonCenter.x + BottomStripMouseGate.liveRadius - 2,
                            y: buttonCenter.y)))

        // Quầng sáng loang gần hết dải nhưng nó là ánh sáng của nút hắt ra, không phải chỗ bấm.
        check("quầng sáng quanh nút: bấm xuyên qua",
              dead(CGPoint(x: buttonCenter.x, y: buttonCenter.y - 84)))

        // Nửa dưới nút thò xuống dải trống: còn nút thì đó vẫn là nút, hết nút thì là chỗ trống.
        let underButton = CGPoint(x: buttonCenter.x, y: cardBottom - 10)
        check("nửa nút thò xuống dải: vẫn là app", !dead(underButton))
        check("trang không có nút: cả dải bấm xuyên qua",
              dead(underButton, hasButton: false))
        check("ngoài khung cửa sổ: không đụng tới",
              !dead(CGPoint(x: frame.minX - 10, y: cardBottom - 40)))
    }

    /// Mỗi mục một dáng viên biểu tượng, như CleanMyMac — chứ không phải cùng một hình đổi màu.
    /// Màu thì đổi theo nền của chính mục ấy nên không dùng để phân biệt được; dáng thì có.
    private static func testIntroBadges() {
        print("[Giới thiệu] dáng viên biểu tượng")

        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

        let pennant = PennantBadge().path(in: rect)
        check("viên cờ nằm gọn trong khung",
              rect.insetBy(dx: -0.01, dy: -0.01).contains(pennant.boundingRect),
              "(\(pennant.boundingRect))")
        check("viên cờ bị khoét chữ V ở mép dưới",
              !pennant.contains(CGPoint(x: rect.midX, y: rect.maxY - 2)))
        check("hai mũi của viên cờ vẫn còn",
              pennant.contains(CGPoint(x: rect.minX + 6, y: rect.maxY - 2)) &&
              pennant.contains(CGPoint(x: rect.maxX - 6, y: rect.maxY - 2)))
        check("nửa trên viên cờ đặc", pennant.contains(CGPoint(x: rect.midX, y: rect.midY)))

        let petal = PetalBadge().path(in: rect)
        check("cánh hoa nằm gọn trong khung",
              rect.insetBy(dx: -0.01, dy: -0.01).contains(petal.boundingRect),
              "(\(petal.boundingRect))")
        // Bốn góc phình ra, bốn cạnh hóp vào: điểm ở giữa cạnh phải nằm NGOÀI, điểm cùng khoảng
        // cách ấy trên đường chéo phải nằm TRONG.
        let r = rect.width / 2 * 0.96
        let onEdge = CGPoint(x: rect.midX + r, y: rect.midY)
        let onCorner = CGPoint(x: rect.midX + r * cos(.pi / 4), y: rect.midY + r * sin(.pi / 4))
        check("giữa cạnh cánh hoa hóp vào", !petal.contains(onEdge))
        check("góc cánh hoa phình ra", petal.contains(onCorner))

        // Ba mục phải ra ba dáng khác nhau, không được trùng.
        let shapes = [IntroBadge.squircle, .pennant, .petal].map { $0.size }
        check("ba dáng ba kích thước khung riêng", Set(shapes.map { "\($0)" }).count == 3)
    }
    // MARK: Dọn tàn dư khi người dùng tự xoá ứng dụng

    private static func testSmartDeleteMemory() {
        print("[SmartDelete] bảng nhớ app không hỏi lại")
        let m = SmartDeleteMemory(storageKey: "selftest.smartDeleteSuppressed")
        m.forgetAll()

        check("chưa ghi thì không bị bỏ qua", !m.isSuppressed(bundleID: "com.acme.foo"))
        m.suppress(bundleID: "com.acme.foo")
        check("ghi rồi thì bỏ qua", m.isSuppressed(bundleID: "com.acme.foo"))
        check("không phân biệt hoa thường", m.isSuppressed(bundleID: "COM.ACME.FOO"))
        check("app khác không ảnh hưởng", !m.isSuppressed(bundleID: "com.acme.bar"))

        m.stamp(bundleID: "com.acme.old", at: Date().addingTimeInterval(-SmartDeleteMemory.ttl - 60))
        check("quá hạn thì hỏi lại", !m.isSuppressed(bundleID: "com.acme.old"))

        check("luôn bỏ qua chính xCleaner",
              m.isSuppressed(bundleID: Bundle.main.bundleIdentifier ?? "com.pikalong.xCleaner"))

        m.forget(bundleID: "com.acme.foo")
        check("quên được một mục", !m.isSuppressed(bundleID: "com.acme.foo"))
        m.forgetAll()
    }

    private static func testTrashWatcher() {
        print("[SmartDelete] nhận ra .app mới rơi vào Thùng rác")
        let box = makeSandbox().appendingPathComponent("trash")
        let fm = FileManager.default
        try? fm.createDirectory(at: box, withIntermediateDirectories: true)

        func makeApp(_ dir: URL, _ name: String, id: String?, version: String = "1.0") {
            let contents = dir.appendingPathComponent("\(name).app/Contents")
            try? fm.createDirectory(at: contents, withIntermediateDirectories: true)
            var d: [String: Any] = ["CFBundleName": name, "CFBundleShortVersionString": version]
            if let id { d["CFBundleIdentifier"] = id }
            (d as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"),
                                      atomically: true)
        }

        makeApp(box, "Foo", id: "com.acme.foo", version: "2.1")
        makeApp(box, "NoID", id: nil)
        let deep = box.appendingPathComponent("Một thư mục")
        try? fm.createDirectory(at: deep, withIntermediateDirectories: true)
        makeApp(deep, "Nested", id: "com.acme.nested")
        try? "x".write(to: box.appendingPathComponent("ghi chú.txt"),
                       atomically: true, encoding: .utf8)

        let found = TrashWatcher.trashedApps(in: box, ignoring: [])
        check("thấy đúng một app", found.count == 1, "(được \(found.map(\.name)))")
        check("đọc đúng bundle id", found.first?.bundleID == "com.acme.foo")
        check("đọc đúng tên", found.first?.name == "Foo")
        check("đọc đúng phiên bản", found.first?.version == "2.1")
        check("bỏ qua bundle không có bundle id",
              !found.contains { $0.name == "NoID" })
        check("bỏ qua .app nằm trong thư mục khác",
              !found.contains { $0.bundleID == "com.acme.nested" })

        let ignored = TrashWatcher.trashedApps(
            in: box, ignoring: [box.appendingPathComponent("Foo.app").path])
        check("mục đã thấy ở lần chụp trước thì bỏ qua", ignored.isEmpty)
    }

    private static func testLaunchAgent() {
        print("[SmartDelete] plist khởi động cùng máy")
        let exe = "/Applications/xCleaner.app/Contents/MacOS/xCleaner"
        let d = LaunchAgentInstaller.plistContents(executable: exe)
        check("có Label đúng", d["Label"] as? String == "com.pikalong.xCleaner.watcher")
        check("chạy lúc đăng nhập", d["RunAtLoad"] as? Bool == true)
        check("không khai KeepAlive", d["KeepAlive"] == nil)
        let args = d["ProgramArguments"] as? [String] ?? []
        check("gọi đúng binary", args.first == exe)
        check("truyền cờ --watch", args.last == "--watch")

        check("chưa có plist thì phải ghi",
              LaunchAgentInstaller.needsRewrite(existing: nil, executable: exe))
        check("plist trỏ đúng chỗ thì thôi",
              !LaunchAgentInstaller.needsRewrite(existing: d, executable: exe))
        check("plist trỏ sai chỗ thì ghi lại",
              LaunchAgentInstaller.needsRewrite(
                existing: d, executable: "/Volumes/USB/xCleaner.app/Contents/MacOS/xCleaner"))
        check("plist thiếu cờ --watch thì ghi lại",
              LaunchAgentInstaller.needsRewrite(
                existing: ["Label": "x", "ProgramArguments": [exe], "RunAtLoad": true],
                executable: exe))
    }

    @MainActor
    private static func testSmartDeleteController() {
        print("[SmartDelete] dựng app từ bundle trong Thùng rác")
        let t = TrashedApp(url: FileUtils.homePath(".Trash/Foo.app"),
                           bundleID: "com.acme.foo", name: "Foo", version: "2.1")
        let app = SmartDeleteController.installedApp(from: t)
        check("giữ bundle id", app.id == "com.acme.foo")
        check("giữ tên", app.name == "Foo")
        check("trỏ vào bundle trong Thùng rác", app.url == t.url)
        check("không đòi quyền quản trị", !app.needsAdmin)

        let items = [
            CleanItem(url: t.url, name: "Foo.app", detail: "Ứng dụng", size: 100),
            CleanItem(url: FileUtils.homePath("Library/Caches/com.acme.foo"),
                      name: "com.acme.foo", detail: "Bộ nhớ đệm", size: 10)
        ]
        let shown = SmartDeleteController.leftoversToShow(items, bundle: t.url)
        check("bỏ chính bundle khỏi danh sách dọn", shown.count == 1)
        check("giữ lại tàn dư", shown.first?.name == "com.acme.foo")

        // Nhận ra chính mình bị xoá — để còn gỡ agent và thoát, không thành cái bóng như helper
        // SmartDelete của AppCleaner (xoá app rồi nó vẫn nằm trong RAM bật hộp thoại).
        check("app khác thì không phải chính mình", !SmartDeleteController.isSelf(t))
        let me = TrashedApp(url: FileUtils.homePath(".Trash/xCleaner.app"),
                            bundleID: Bundle.main.bundleIdentifier ?? "com.pikalong.xCleaner",
                            name: "xCleaner", version: "1.0")
        check("nhận ra chính xCleaner bị kéo vào Thùng rác", SmartDeleteController.isSelf(me))
        check("bản đang chạy còn đó thì đừng thoát (chỉ là bản sao bị xoá)",
              !SmartDeleteController.shouldQuitAfterSelfTrashed(runningBundleExists: true))
        check("bản đang chạy mất rồi thì thoát",
              SmartDeleteController.shouldQuitAfterSelfTrashed(runningBundleExists: false))
    }
}
#endif
