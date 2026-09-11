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
