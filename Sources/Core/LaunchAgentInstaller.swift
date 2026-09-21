import Foundation

/// Ghi/gỡ LaunchAgent để xCleaner trực Thùng rác ngay từ lúc đăng nhập.
///
/// Dùng plist thuần chứ **không** `SMAppService`: cái đó đòi app ký bằng Developer ID, còn
/// xCleaner ký bằng chứng chỉ tự ký (xem ghi chú ở `PrivilegedRunner`). Agent gọi lại đúng binary
/// này với cờ `--watch`, nên nó dùng chung quyền Toàn quyền truy cập đĩa đã cấp — một helper
/// riêng sẽ là "app khác" với macOS và phải xin quyền lần thứ hai.
enum LaunchAgentInstaller {

    static let label = "com.pikalong.xCleaner.watcher"

    static var plistURL: URL {
        FileUtils.homePath("Library/LaunchAgents/\(label).plist")
    }

    /// Đường dẫn thật của tiến trình đang chạy.
    static var currentExecutable: String {
        URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    }

    static func plistContents(executable: String) -> [String: Any] {
        // KHÔNG khai `KeepAlive`: người dùng thoát app là cố ý, dựng dậy là chống lại họ. Và
        // `KeepAlive/SuccessfulExit` đã từng cho ra kiểu daemon chết im lặng ở Clawdmeter.
        ["Label": label,
         "ProgramArguments": [executable, "--watch"],
         "RunAtLoad": true,
         "ProcessType": "Background"]
    }

    /// Plist cũ có còn đúng không. Người dùng cập nhật app hoặc chuyển thư mục là nó trỏ vào chỗ
    /// trống, và một agent trỏ vào chỗ trống thì im lặng không chạy — hỏng mà không ai biết.
    static func needsRewrite(existing: [String: Any]?, executable: String) -> Bool {
        guard let existing,
              let args = existing["ProgramArguments"] as? [String],
              args.first == executable,
              args.contains("--watch"),
              existing["RunAtLoad"] as? Bool == true else { return true }
        return false
    }

    static func install(executable: String = currentExecutable) {
        #if DEBUG
        // Bản Debug chạy thẳng từ DerivedData. Ghi một agent trỏ vào /tmp là để lại trong máy
        // người dùng một mục khởi động trỏ vào chỗ sẽ bị xoá — đặt `XCLEANER_AGENT=1` nếu muốn
        // thử chính phần này.
        guard ProcessInfo.processInfo.environment["XCLEANER_AGENT"] == "1" else { return }
        #endif
        let existing = NSDictionary(contentsOf: plistURL) as? [String: Any]
        guard needsRewrite(existing: existing, executable: executable) else { return }
        try? FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        (plistContents(executable: executable) as NSDictionary).write(to: plistURL, atomically: true)
    }

    static func uninstall() {
        try? FileManager.default.removeItem(at: plistURL)
        // Chưa nạp thì `bootout` báo lỗi — bình thường, nuốt luôn.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
