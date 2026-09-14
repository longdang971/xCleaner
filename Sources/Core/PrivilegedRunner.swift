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
        /// Những đường dẫn thật sự được đưa cho root. Mục không có mặt ở đây — vì bị hàng rào an
        /// toàn loại, hoặc vì lệnh không chạy — thì không được phép kết luận là đã xoá.
        var attempted: Set<String> = []
        /// Đường dẫn mà **root tự kiểm tra** thấy vẫn còn sau khi xoá. Đây là bằng chứng duy
        /// nhất đáng tin cho thư mục mà bản thân app còn không được phép đọc.
        var remaining: Set<String> = []
    }

    /// Tiền tố của dòng báo cáo do đoạn script kiểm tra lại in ra.
    private static let leftMarker = "xcleaner-left\t"

    /// Đoạn script hỏi lại từng đường dẫn trong tệp kê khai xem nó còn không.
    ///
    /// Đường dẫn đi vào `sh` như **đối số** (`sh @`) chứ không được nội suy vào chuỗi lệnh,
    /// nên tên tệp chứa nháy, `$` hay backtick cũng không thành lệnh.
    private static func verifyScript(manifest: String, emptyOnly: Bool) -> String {
        let test = emptyOnly
            ? "[ -n \"$(/usr/bin/find \"$1\" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)\" ]"
            // `-e` đi theo liên kết: liên kết hỏng vẫn nằm đó mà báo là không có. Hỏi thêm `-L`.
            : "[ -e \"$1\" ] || [ -L \"$1\" ]"
        return "/usr/bin/xargs -0 -I @ /bin/sh -c 'if \(test); then printf \"\(leftMarker)%s\\n\" \"$1\"; fi' sh @ < \(manifest) 2>/dev/null"
    }

    // MARK: - API

    /// Xoá hẳn nhóm này và dọn ruột nhóm kia trong **một** lần hỏi mật khẩu.
    ///
    /// Gọi `remove` rồi `emptyContents` là hai lệnh, mà mỗi lệnh dựng một `AuthorizationRef`
    /// mới nên người dùng phải nhập mật khẩu hai lần cho cùng một cú bấm "Dọn".
    @discardableResult
    static func removeAndEmpty(remove paths: [URL],
                               emptyContents dirs: [URL],
                               prompt: String) throws -> Report {
        let (toRemove, rejectedRemove) = SafetyGuard.partition(paths)
        let (toEmpty, rejectedEmpty) = SafetyGuard.partition(dirs)
        for (url, reason) in rejectedRemove + rejectedEmpty {
            NSLog("[xCleaner] SafetyGuard chặn (admin): %@ — %@", url.path, reason.localizedDescription)
        }
        guard !toRemove.isEmpty || !toEmpty.isEmpty else { return Report() }

        var manifests: [URL] = []
        defer { for m in manifests { try? FileManager.default.removeItem(at: m) } }

        var parts: [String] = []
        var verifies: [String] = []
        if !toRemove.isEmpty {
            let m = try writeManifest(toRemove)
            manifests.append(m)
            parts.append("/usr/bin/xargs -0 /bin/rm -rf -- < \(shellQuote(m.path)) 2>&1")
            verifies.append(verifyScript(manifest: shellQuote(m.path), emptyOnly: false))
        }
        if !toEmpty.isEmpty {
            let m = try writeManifest(toEmpty)
            manifests.append(m)
            // `-mindepth 1` giữ lại chính thư mục; `-maxdepth 1` để `rm -rf` lo phần bên trong.
            parts.append("/usr/bin/xargs -0 -I DIR /usr/bin/find DIR -mindepth 1 -maxdepth 1 "
                         + "-exec /bin/rm -rf -- {} + < \(shellQuote(m.path)) 2>&1")
            verifies.append(verifyScript(manifest: shellQuote(m.path), emptyOnly: true))
        }
        // Kiểm tra lại phải do chính root làm: thư mục mà app không được phép đọc thì
        // `FileManager` của app nhìn vào chỉ thấy "rỗng" dù bên trong còn nguyên.
        parts.append(contentsOf: verifies)
        parts.append("/bin/rm -f " + manifests.map { shellQuote($0.path) }.joined(separator: " "))
        parts.append("exit 0")

        let out = try runAsAdmin(command: parts.joined(separator: "; "), prompt: prompt)
        var report = Report(stdout: out)
        report.attempted = Set((toRemove + toEmpty).map(\.path))
        // Tách theo MỌI kiểu xuống dòng: đường osascript (`do shell script`) đổi `\n` thành `\r`
        // (đã đo), tách theo `\n` là cả báo cáo dính thành một dòng — chỉ đường dẫn đầu tiên được
        // nhận là "còn", mọi mục sau bị coi là đã xoá.
        for line in out.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if line.hasPrefix(leftMarker) {
                report.remaining.insert(String(line.dropFirst(leftMarker.count)))
            } else {
                report.errorLines.append(trimmed)
            }
        }
        return report
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
