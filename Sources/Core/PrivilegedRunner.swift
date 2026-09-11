import Foundation

/// Chạy thao tác cần quyền root mà **không** cần Apple Developer ID.
///
/// `SMJobBless` / `SMAppService` bắt buộc phải ký bằng chứng chỉ Developer ID và khai báo
/// `SMAuthorizedClients`, nên không dùng được ở đây. Thay vào đó xCleaner gọi
/// `do shell script … with administrator privileges`: macOS sẽ tự hiện hộp thoại nhập mật khẩu
/// của hệ thống (SecurityAgent), app không bao giờ nhìn thấy mật khẩu đó.
///
/// Nguyên tắc an toàn:
/// 1. Danh sách đường dẫn **không** được nội suy vào chuỗi lệnh. Chúng được ghi ra một tệp
///    kê khai, ngăn cách bằng byte NUL, rồi `xargs -0` đọc lại — đường dẫn có dấu cách, nháy
///    hay xuống dòng đều vô hại.
/// 2. Tệp kê khai nằm trong thư mục 0700 thuộc sở hữu người dùng, tên ngẫu nhiên, xoá ngay sau khi xong.
/// 3. Mỗi đường dẫn đi qua `SafetyGuard` một lần nữa ngay trước khi ghi vào tệp kê khai.
/// 4. Toàn bộ phiên dọn chỉ hỏi mật khẩu **một lần** vì mọi đường dẫn được gom vào một lệnh.
enum PrivilegedRunner {

    enum Failure: LocalizedError {
        case cancelledByUser
        case manifest(String)
        case script(String)

        var errorDescription: String? {
            switch self {
            case .cancelledByUser: return "Bạn đã huỷ yêu cầu quyền quản trị."
            case .manifest(let m): return "Không tạo được danh sách tạm: \(m)"
            case .script(let m):   return m
            }
        }
    }

    struct Report {
        var stdout: String = ""
        /// Những dòng `rm` báo lỗi (nếu có).
        var errorLines: [String] = []
    }

    // MARK: - API

    /// Xoá danh sách đường dẫn dưới quyền root. Hỏi mật khẩu đúng một lần.
    @discardableResult
    static func remove(paths: [URL], prompt: String) throws -> Report {
        let (accepted, rejected) = SafetyGuard.partition(paths)
        for (url, reason) in rejected {
            NSLog("[xCleaner] SafetyGuard chặn (admin): %@ — %@", url.path, reason.localizedDescription)
        }
        guard !accepted.isEmpty else { return Report() }

        let manifest = try writeManifest(accepted)
        defer { try? FileManager.default.removeItem(at: manifest) }

        let m = shellQuote(manifest.path)
        let command = "/usr/bin/xargs -0 /bin/rm -rf -- < \(m) 2>&1; /bin/rm -f \(m); exit 0"
        let out = try runAsAdmin(command: command, prompt: prompt)

        var report = Report(stdout: out)
        report.errorLines = out
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return report
    }

    /// Dọn sạch *nội dung* của các thư mục nhưng giữ lại chính thư mục đó
    /// (một số thư mục hệ thống sẽ không được tạo lại nếu bị xoá hẳn).
    @discardableResult
    static func emptyContents(of dirs: [URL], prompt: String) throws -> Report {
        var children: [URL] = []
        let fm = FileManager.default
        for d in dirs where SafetyGuard.isValid(d) {
            let items = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil,
                                                     options: [])) ?? []
            children.append(contentsOf: items)
        }
        return try remove(paths: children, prompt: prompt)
    }

    /// Kiểm tra nhanh xem người dùng có quyền ghi trực tiếp không (để biết có cần hỏi mật khẩu).
    static func needsAdmin(for url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().path
        if access(parent, W_OK) != 0 { return true }
        // Thư mục con do root sở hữu bên trong thư mục cha ghi được vẫn xoá được, nên chỉ cần cha.
        return false
    }

    // MARK: - Thực thi

    /// Ưu tiên Authorization Services (hộp thoại mang tên và icon xCleaner);
    /// nếu API đó không dùng được thì lùi về osascript, vốn luôn có mặt.
    private static func runAsAdmin(command: String, prompt: String) throws -> String {
        do {
            return try AuthorizationRunner.run(command: command, prompt: prompt)
        } catch AuthorizationRunner.Failure.cancelled {
            throw Failure.cancelledByUser
        } catch {
            NSLog("[xCleaner] Authorization Services không dùng được (%@) — chuyển sang osascript.",
                  error.localizedDescription)
            return try runViaAppleScript(command: command, prompt: prompt)
        }
    }

    private static func runViaAppleScript(command: String, prompt: String) throws -> String {
        let script = "do shell script \(appleScriptQuote(command)) " +
                     "with prompt \(appleScriptQuote(prompt)) " +
                     "with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]

        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do { try proc.run() } catch {
            throw Failure.script("Không khởi chạy được osascript: \(error.localizedDescription)")
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        if proc.terminationStatus != 0 {
            // -128 là mã chuẩn khi người dùng bấm Cancel ở hộp thoại mật khẩu.
            if stderr.contains("-128") || stderr.lowercased().contains("user canceled") {
                throw Failure.cancelledByUser
            }
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.script(msg.isEmpty ? "Lệnh quản trị thất bại (mã \(proc.terminationStatus))." : msg)
        }
        return stdout
    }

    // MARK: - Tệp kê khai

    private static func manifestDirectory() throws -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("xCleaner", isDirectory: true)
            .appendingPathComponent("privileged", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try fm.createDirectory(at: base, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } else {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: base.path)
        }
        return base
    }

    private static func writeManifest(_ urls: [URL]) throws -> URL {
        do {
            let dir = try manifestDirectory()
            let name = "batch-" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + ".list"
            let file = dir.appendingPathComponent(name)

            var data = Data()
            for u in urls {
                data.append(contentsOf: Array(u.path.utf8))
                data.append(0)
            }
            try data.write(to: file, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return file
        } catch let e as Failure {
            throw e
        } catch {
            throw Failure.manifest(error.localizedDescription)
        }
    }

    // MARK: - Escape

    /// Bọc trong nháy đơn cho shell; nháy đơn bên trong được thoát theo kiểu `'\''`.
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Bọc trong nháy kép cho AppleScript.
    static func appleScriptQuote(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\\", with: "\\\\")
        t = t.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + t + "\""
    }
}
