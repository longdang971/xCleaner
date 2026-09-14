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
        /// Những đường dẫn thật sự được đưa cho root.
        var attempted: Set<String> = []
        /// Đường dẫn mà **root khẳng định** đã không còn (hoặc, với thư mục dọn ruột, đã rỗng).
        ///
        /// Chỉ thứ có mặt ở đây mới được báo là đã xoá. Bản trước làm ngược lại — "không thấy
        /// báo còn thì là đã mất" — nên mọi sự cố (lệnh chết giữa chừng, output bị cắt, tên tệp
        /// chứa xuống dòng) đều ngả về phía báo đã xoá. Giờ chúng ngả về phía "chưa xoá".
        var confirmedGone: Set<String> = []
        /// Đường dẫn mà root khẳng định **vẫn còn**. Chỉ thứ ở đây mới được ghi sổ "không xoá
        /// được" — không có tin tức gì thì không được kết luận gì.
        var confirmedLeft: Set<String> = []
    }

    /// Một lệnh root đã dựng xong, cùng những thứ phải dọn sau khi chạy.
    struct Batch {
        let command: String
        let manifests: [URL]
        let attempted: Set<String>
    }

    private static let goneMarker = "xcleaner-gone\t"
    private static let leftMarker = "xcleaner-left\t"

    /// In đường dẫn `$1` dưới dạng hex. Hex không chứa xuống dòng, không bị `do shell script`
    /// đổi `\n` thành `\r`, không bị `fgets` cắt ngang một ký tự tiếng Việt — tên tệp kỳ quặc
    /// đến đâu cũng về tới app nguyên vẹn. `-v` để `od` không nén các dòng giống nhau thành `*`.
    private static let hexOfArg = #"$(printf %s "$1" | /usr/bin/od -An -v -tx1 | /usr/bin/tr -d " \n")"#

    /// Kết luận "đã mất" chỉ khi `stat` nói đúng là không có. `[ -e ]` không phân biệt được
    /// "không có" với "không được phép nhìn", và còn đi theo liên kết tượng trưng.
    private static let statVerdict = #"if err=$(LC_ALL=C /usr/bin/stat -f "" -- "$1" 2>&1 >/dev/null); then printf "xcleaner-left\t%s\n" "HEX"; else case "$err" in *": No such file or directory"|*": Not a directory") printf "xcleaner-gone\t%s\n" "HEX";; esac; fi"#

    /// Đoạn script hỏi lại từng đường dẫn trong tệp kê khai.
    ///
    /// Đường dẫn đi vào `sh` như **đối số** (`sh @`) chứ không được nội suy vào chuỗi lệnh,
    /// nên tên tệp chứa nháy, `$` hay backtick cũng không thành lệnh.
    private static func verifyScript(manifest: String, emptyOnly: Bool) -> String {
        let verdict = statVerdict.replacingOccurrences(of: "HEX", with: hexOfArg)
        let body: String
        if emptyOnly {
            // Thư mục dọn ruột: `find` chạy trót lọt mà không in gì mới là rỗng. `find` lỗi thì
            // hỏi `stat` xem thư mục còn không, chứ không đoán.
            //
            // Trừ liên kết tượng trưng: `find` không đi theo liên kết ở điểm xuất phát, nên với nó
            // một liên kết tới thư mục đầy ắp cũng "không in gì, thoát 0" (đã đo) — tức là rỗng.
            // Liên kết thì không bao giờ được khẳng định là đã dọn.
            body = #"if [ -L "$1" ]; then printf "xcleaner-left\t%s\n" "HEX"; elif out=$(/usr/bin/find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null); then if [ -z "$out" ]; then printf "xcleaner-gone\t%s\n" "HEX"; else printf "xcleaner-left\t%s\n" "HEX"; fi; else "#
                .replacingOccurrences(of: "HEX", with: hexOfArg) + verdict + "; fi"
        } else {
            body = verdict
        }
        // `-p`: shell con cũng là bash, không có nó thì chính bước soi lại tự hạ về quyền thường
        // (xem AuthorizationRunner) và nhìn đĩa bằng con mắt của người dùng thay vì của root.
        return "/usr/bin/xargs -0 -I @ /bin/sh -p -c '\(body)' sh @ < \(manifest)"
    }

    // MARK: - API

    /// Dựng lệnh xoá hẳn nhóm này, dọn ruột nhóm kia, rồi để root tự soi lại từng đường dẫn.
    /// Tách riêng khỏi việc chạy để kiểm tra được mà không phải nhập mật khẩu.
    static func makeBatch(remove paths: [URL], emptyContents dirs: [URL]) throws -> Batch? {
        let (toRemove, rejectedRemove) = SafetyGuard.partition(paths)
        let (toEmpty, rejectedEmpty) = SafetyGuard.partition(dirs)
        for (url, reason) in rejectedRemove + rejectedEmpty {
            NSLog("[xCleaner] SafetyGuard chặn (admin): %@ — %@", url.path, reason.localizedDescription)
        }
        guard !toRemove.isEmpty || !toEmpty.isEmpty else { return nil }

        var manifests: [URL] = []
        var parts: [String] = []
        var verifies: [String] = []
        do {
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
        } catch {
            for m in manifests { try? FileManager.default.removeItem(at: m) }
            throw error
        }
        // Kiểm tra lại phải do chính root làm: thư mục mà app không được phép đọc thì
        // `FileManager` của app nhìn vào chỉ thấy "rỗng" dù bên trong còn nguyên.
        parts.append(contentsOf: verifies)
        parts.append("/bin/rm -f " + manifests.map { shellQuote($0.path) }.joined(separator: " "))
        parts.append("exit 0")

        return Batch(command: parts.joined(separator: "; "),
                     manifests: manifests,
                     attempted: Set((toRemove + toEmpty).map(\.path)))
    }

    /// Đọc những gì lệnh root in ra thành bằng chứng theo từng đường dẫn.
    static func parse(_ out: String, attempted: Set<String>) -> Report {
        var report = Report(stdout: out, attempted: attempted)
        // Tách theo MỌI kiểu xuống dòng: đường osascript (`do shell script`) đổi `\n` thành `\r`.
        for raw in out.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if raw.hasPrefix(goneMarker), let path = decodeHex(raw.dropFirst(goneMarker.count)),
               attempted.contains(path) {
                report.confirmedGone.insert(path)
            } else if raw.hasPrefix(leftMarker), let path = decodeHex(raw.dropFirst(leftMarker.count)),
                      attempted.contains(path) {
                report.confirmedLeft.insert(path)
            } else {
                report.errorLines.append(line)
            }
        }
        // Một đường dẫn không thể vừa mất vừa còn; có mâu thuẫn thì tin phía "còn".
        report.confirmedGone.subtract(report.confirmedLeft)
        return report
    }

    private static func decodeHex(_ hex: Substring) -> String? {
        let chars = Array(hex.trimmingCharacters(in: .whitespaces))
        guard !chars.isEmpty, chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            bytes.append(b)
            i += 2
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// Xoá hẳn nhóm này và dọn ruột nhóm kia trong **một** lần hỏi mật khẩu.
    ///
    /// Gọi hai lệnh riêng thì mỗi lệnh dựng một `AuthorizationRef` mới và người dùng phải
    /// nhập mật khẩu hai lần cho cùng một cú bấm "Dọn".
    @discardableResult
    static func removeAndEmpty(remove paths: [URL],
                               emptyContents dirs: [URL],
                               prompt: String) throws -> Report {
        guard let batch = try makeBatch(remove: paths, emptyContents: dirs) else { return Report() }
        defer { for m in batch.manifests { try? FileManager.default.removeItem(at: m) } }
        let out = try runAsAdmin(command: batch.command, prompt: prompt)
        return parse(out, attempted: batch.attempted)
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
