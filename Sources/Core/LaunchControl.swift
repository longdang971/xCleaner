import Foundation

/// Nói chuyện với `launchctl`.
///
/// Bật/tắt một mục khởi động **không** sửa tệp plist của người khác: `launchctl enable/disable`
/// ghi vào cơ sở dữ liệu ghi đè của hệ thống, nên khi người dùng bật lại thì mọi thứ về đúng
/// như cũ, và bản cập nhật của app đó cũng không ghi đè mất lựa chọn.
enum LaunchControl {

    /// Miền mà một mục khởi động sống trong đó.
    enum Domain: String {
        /// `~/Library/LaunchAgents` — chỉ chạy cho người dùng này.
        case userAgent
        /// `/Library/LaunchAgents` — chạy cho mọi người dùng khi đăng nhập.
        case globalAgent
        /// `/Library/LaunchDaemons` — chạy nền kể cả khi chưa ai đăng nhập, quyền root.
        case daemon

        /// Agent — kể cả agent toàn máy — đều chạy trong phiên giao diện của người dùng,
        /// nên tắt chúng không cần mật khẩu. Chỉ daemon mới đụng tới miền `system`.
        var needsAdmin: Bool { self == .daemon }

        var target: String {
            switch self {
            case .userAgent, .globalAgent: return "gui/\(getuid())"
            case .daemon:                  return "system"
            }
        }

        var directory: URL {
            switch self {
            case .userAgent:   return FileUtils.homePath("Library/LaunchAgents")
            case .globalAgent: return URL(fileURLWithPath: "/Library/LaunchAgents")
            case .daemon:      return URL(fileURLWithPath: "/Library/LaunchDaemons")
            }
        }

        var title: String {
            switch self {
            case .userAgent:   return "Của bạn"
            case .globalAgent: return "Toàn máy"
            case .daemon:      return "Dịch vụ nền"
            }
        }
    }

    // MARK: - Đọc trạng thái

    /// Nhãn của mọi thứ đang được nạp, kèm PID nếu nó đang thật sự chạy.
    static func loaded() -> [String: Int32?] {
        var result: [String: Int32?] = [:]
        let out = run("/bin/launchctl", ["list"]).out
        for line in out.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let label = String(cols[2]).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            result[label] = Int32(cols[0])
        }
        return result
    }

    /// Nhãn đã bị tắt trong một miền. macOS đổi cách in ra giữa các phiên bản
    /// (`=> true` rồi `=> disabled`), nên chỗ này chấp nhận cả hai.
    static func disabledLabels(in domain: Domain) -> Set<String> {
        parseDisabled(run("/bin/launchctl", ["print-disabled", domain.target]).out)
    }

    static func parseDisabled(_ text: String) -> Set<String> {
        var result: Set<String> = []
        for line in text.split(separator: "\n") {
            guard let arrow = line.range(of: "=>") else { continue }
            let left = line[line.startIndex..<arrow.lowerBound]
            let right = line[arrow.upperBound...].lowercased()
            guard right.contains("true") || right.contains("disabled") else { continue }
            let label = left.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            if !label.isEmpty { result.insert(label) }
        }
        return result
    }

    /// Hỏi thẳng launchd về một mục.
    ///
    /// `launchctl list` chỉ thấy những gì nằm trong miền của người dùng: đo trên máy thật thì
    /// một daemon đang chạy ngon lành cũng không hề xuất hiện ở đó. `launchctl print` thì đọc
    /// được cả miền `system` mà không cần mật khẩu, và tiện thể cho luôn đường dẫn chương
    /// trình — thứ mà tệp plist của daemon (chỉ root đọc được) không chịu nói.
    static func describe(label: String, domain: Domain) -> (running: Bool, program: String?)? {
        let r = run("/bin/launchctl", ["print", "\(domain.target)/\(label)"])
        guard r.status == 0 else { return nil }
        return parsePrint(r.out)
    }

    static func parsePrint(_ text: String) -> (running: Bool, program: String?) {
        var running: Bool?
        var program: String?
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // Chỉ dòng `state` ĐẦU TIÊN nói về chính dịch vụ. Bên dưới còn vài dòng `state`
            // nữa của các endpoint con, giá trị là "active" — lấy nhầm dòng cuối thì một
            // daemon đang chạy bị báo là đã dừng.
            if running == nil, line.hasPrefix("state = ") {
                running = line.dropFirst("state = ".count).hasPrefix("running")
            } else if program == nil, line.hasPrefix("program = ") {
                program = String(line.dropFirst("program = ".count))
            } else if program == nil, line.hasPrefix("path = "), !line.hasSuffix(".plist") {
                program = String(line.dropFirst("path = ".count))
            }
        }
        return (running ?? false, program)
    }

    // MARK: - Bật / tắt

    /// Bật hoặc tắt một mục. Với daemon thì hệ thống sẽ hỏi mật khẩu quản trị.
    static func setEnabled(_ enabled: Bool, label: String, plist: URL, domain: Domain) throws {
        let q = PrivilegedRunner.shellQuote
        let target = "\(domain.target)/\(label)"
        var steps: [String] = ["/bin/launchctl \(enabled ? "enable" : "disable") \(q(target))"]
        if enabled {
            // Nạp lại ngay để người dùng không phải khởi động lại máy mới thấy tác dụng.
            steps.append("/bin/launchctl bootstrap \(q(domain.target)) \(q(plist.path)) || true")
        } else {
            // Đang chạy thì tống ra khỏi bộ nhớ luôn; chưa chạy thì lệnh này báo lỗi, kệ nó.
            steps.append("/bin/launchctl bootout \(q(target)) || true")
        }
        let command = steps.joined(separator: "; ")

        if domain.needsAdmin {
            _ = try AuthorizationRunner.run(
                command: command,
                prompt: "xCleaner cần quyền quản trị để \(enabled ? "bật" : "tắt") dịch vụ nền “\(label)”.")
        } else {
            let r = run("/bin/sh", ["-c", command])
            // `disable` là bước duy nhất bắt buộc phải thành công; hai bước sau chỉ là dọn dẹp.
            if r.status != 0 && !r.out.isEmpty && r.out.lowercased().contains("permission") {
                throw LaunchError.refused(r.out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    /// Tắt rồi xoá luôn tệp, gói trong **một** lần hỏi mật khẩu.
    ///
    /// Chỉ dùng cho dịch vụ nền: tắt nó đã cần root, xoá tệp trong `/Library` cũng cần root,
    /// nên tách làm hai bước là bắt người dùng gõ mật khẩu hai lần liên tiếp cho cùng một việc.
    /// - Returns: `true` nếu tệp đã biến mất.
    static func disableAndRemove(label: String, plist: URL, domain: Domain) throws -> Bool {
        // Vẫn phải qua hàng rào an toàn như mọi đường xoá khác của app.
        if let reason = SafetyGuard.validate(plist) {
            throw LaunchError.refused(reason.localizedDescription)
        }
        let q = PrivilegedRunner.shellQuote
        let target = "\(domain.target)/\(label)"
        let command = [
            "/bin/launchctl disable \(q(target)) || true",
            "/bin/launchctl bootout \(q(target)) || true",
            "/bin/rm -f \(q(plist.path))"
        ].joined(separator: "; ")
        _ = try AuthorizationRunner.run(
            command: command,
            prompt: "xCleaner cần quyền quản trị để tắt và xoá mục khởi động “\(label)”.")
        // `fileExists` báo `false` cả khi chỉ là không được nhìn — chỉ tin lstat.
        return FileUtils.isGone(plist)
    }

    enum LaunchError: LocalizedError {
        case refused(String)
        var errorDescription: String? {
            switch self {
            case .refused(let m): return m.isEmpty ? "macOS từ chối thao tác này." : m
            }
        }
    }

    /// Người dùng bấm Huỷ ở hộp mật khẩu không phải là lỗi — đừng bắn cảnh báo đỏ vào mặt họ.
    static func isCancellation(_ error: Error) -> Bool {
        if case AuthorizationRunner.Failure.cancelled = error { return true }
        if case PrivilegedRunner.Failure.cancelledByUser = error { return true }
        return false
    }

    // MARK: - Chạy lệnh

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
