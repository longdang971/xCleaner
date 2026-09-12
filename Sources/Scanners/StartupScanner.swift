import Foundation
import AppKit

/// Những thứ tự chạy khi bật máy hoặc khi đăng nhập.
///
/// Đọc ba thư mục `LaunchAgents`/`LaunchDaemons` — đây mới là chỗ các app cài thứ chạy ngầm
/// (bộ cập nhật, trình đồng bộ, helper). Mục "Mở khi đăng nhập" kiểu mới của macOS nằm trong
/// cơ sở dữ liệu riêng của hệ thống, app khác không đọc được, nên phần đó chỉ dẫn người dùng
/// sang Cài đặt hệ thống chứ không đoán bừa.
struct StartupScanner {

    struct Item: Identifiable, Hashable {
        var id: String { plist.path }
        let label: String
        /// Tên đọc được: tên app nếu tra ra, không thì chính cái nhãn.
        let name: String
        let plist: URL
        let domain: LaunchControl.Domain
        /// Chương trình mà mục này chạy.
        let program: String?
        /// App chủ của nó, nếu đoán được — để lấy biểu tượng thật.
        let bundleID: String?
        /// Của macOS thì không cho tắt: hỏng thứ này là hỏng máy.
        let isApple: Bool
        /// Tự chạy ngay khi nạp, khác với thứ chỉ chạy khi có việc gọi tới.
        let runAtLoad: Bool
        /// Chạy lại theo chu kỳ — thường là bộ kiểm tra cập nhật.
        let intervalSeconds: Int?
        var isRunning: Bool
        var isDisabled: Bool
        /// Tệp plist trỏ tới một chương trình không còn tồn tại — rác của app đã gỡ.
        let isOrphan: Bool
        /// Nhiều daemon để plist ở chế độ chỉ root đọc được. Vẫn phải hiện nó ra — giấu đi
        /// thì người dùng không bao giờ biết máy mình đang chạy ngầm cái gì — nhưng nói rõ
        /// là chưa đọc được chi tiết.
        let detailsHidden: Bool

        static func == (l: Item, r: Item) -> Bool { l.plist == r.plist }
        func hash(into h: inout Hasher) { h.combine(plist) }

        var needsAdmin: Bool { domain != .userAgent }

        var detail: String {
            var parts: [String] = [domain.title]
            if isOrphan { parts.append("chương trình không còn") }
            else if detailsHidden {
                // Chưa đọc được plist thì không biết nó chạy lúc nào — nói bừa "chạy khi có
                // việc gọi tới" là bịa. Cho xem chương trình nó chạy, đó là thứ chắc chắn.
                if let program {
                    parts.append(FileUtils.prettyPath(URL(fileURLWithPath: program)))
                } else {
                    parts.append("chỉ quản trị viên đọc được chi tiết")
                }
            }
            else if let interval = intervalSeconds { parts.append("lặp lại mỗi \(Fmt.duration(interval))") }
            else if runAtLoad { parts.append("chạy ngay khi đăng nhập") }
            else { parts.append("chạy khi có việc gọi tới") }
            return parts.joined(separator: " · ")
        }
    }

    var stages: [ScanStage] {
        [.init(id: "user", title: "Của bạn", icon: "person.crop.circle"),
         .init(id: "global", title: "Toàn máy", icon: "desktopcomputer"),
         .init(id: "daemon", title: "Dịch vụ nền", icon: "gearshape.2.fill")]
    }

    func scan(cancel: CancelToken, progress: @escaping (ScanProgress) -> Void) -> [Item] {
        let stage = StageReporter(total: 3, emit: progress)
        let loaded = LaunchControl.loaded()
        var items: [Item] = []

        let domains: [LaunchControl.Domain] = [.userAgent, .globalAgent, .daemon]
        for (i, domain) in domains.enumerated() {
            if cancel.isCancelled { break }
            stage.begin(i)
            let disabled = LaunchControl.disabledLabels(in: domain)
            let files = FileUtils.children(of: domain.directory)
                .filter { $0.pathExtension == "plist" }
            for (n, file) in files.enumerated() {
                if cancel.isCancelled { break }
                stage.working(file.lastPathComponent,
                              within: Double(n) / Double(max(1, files.count)))
                guard let item = read(file, domain: domain, loaded: loaded, disabled: disabled)
                else { continue }
                items.append(item)
            }
            stage.finish(i, bytes: 0)
        }

        stage.done()
        return items.sorted {
            if $0.isApple != $1.isApple { return !$0.isApple }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Đọc một tệp plist

    func read(_ file: URL,
              domain: LaunchControl.Domain,
              loaded: [String: Int32?],
              disabled: Set<String>) -> Item? {
        // Đọc được thì lấy hết; không đọc được (daemon hay để plist chỉ root xem) thì vẫn
        // dựng một mục tối giản từ tên tệp — launchd khuyến nghị đặt tên tệp trùng nhãn,
        // và `launchctl` chỉ cần nhãn là bật/tắt được.
        let dict = (NSDictionary(contentsOf: file) as? [String: Any])
        let hidden = dict == nil
        let d = dict ?? [:]
        let label = (d["Label"] as? String) ?? file.deletingPathExtension().lastPathComponent
        guard !label.isEmpty else { return nil }

        var program = Self.program(in: d)

        // Daemon không nằm trong `launchctl list`, và plist của nó thường chỉ root đọc được.
        // Hỏi riêng launchd để biết nó có đang chạy không và chạy cái gì.
        var running = loaded[label].map { $0 != nil } ?? false
        let detailsHidden = hidden
        if domain == .daemon || hidden, let info = LaunchControl.describe(label: label, domain: domain) {
            running = info.running
            // launchd cho biết nó chạy chương trình nào, nhưng không cho biết lịch chạy
            // (`RunAtLoad`, `StartInterval`) — thứ đó chỉ nằm trong plist.
            if program == nil { program = info.program }
        }
        let isApple = label.hasPrefix("com.apple.")
            || (program?.hasPrefix("/System/") ?? false)
            || (program?.hasPrefix("/usr/libexec/") ?? false)
        let bundleID = Self.bundleID(forLabel: label, program: program)

        return Item(
            label: label,
            name: Self.displayName(label: label, program: program, bundleID: bundleID),
            plist: file,
            domain: domain,
            program: program,
            bundleID: bundleID,
            isApple: isApple,
            runAtLoad: (d["RunAtLoad"] as? Bool) ?? false,
            intervalSeconds: d["StartInterval"] as? Int,
            isRunning: running,
            isDisabled: disabled.contains(label) || (d["Disabled"] as? Bool ?? false),
            isOrphan: Self.isOrphan(program: program),
            detailsHidden: detailsHidden)
    }

    /// Chương trình được chạy: `Program` nếu có, không thì phần tử đầu của `ProgramArguments`.
    static func program(in dict: [String: Any]) -> String? {
        if let p = dict["Program"] as? String, !p.isEmpty { return p }
        if let args = dict["ProgramArguments"] as? [String], let first = args.first, !first.isEmpty {
            return first
        }
        return nil
    }

    /// Đường dẫn trỏ vào hư không nghĩa là app đã bị gỡ mà bỏ quên tệp này lại.
    /// Chỉ kết luận với đường dẫn tuyệt đối — `/bin/sh` hay tên lệnh trần thì không tính.
    static func isOrphan(program: String?) -> Bool {
        guard let program, program.hasPrefix("/") else { return false }
        return !FileManager.default.fileExists(atPath: program)
    }

    /// Đoán app chủ: nhãn thường chính là bundle id, hoặc bớt đi phần đuôi kiểu
    /// `com.acme.Tool.helper`. Nếu chương trình nằm trong một `.app` thì lấy luôn id của app đó.
    static func bundleID(forLabel label: String, program: String?) -> String? {
        if let program, let range = program.range(of: ".app/") {
            let appPath = String(program[program.startIndex..<range.lowerBound]) + ".app"
            if let b = Bundle(path: appPath)?.bundleIdentifier { return b }
        }
        var parts = label.split(separator: ".").map(String.init)
        while parts.count >= 2 {
            let candidate = parts.joined(separator: ".")
            if AppCatalog.shared.name(forBundleID: candidate) != nil { return candidate }
            parts.removeLast()
        }
        return nil
    }

    static func displayName(label: String, program: String?, bundleID: String?) -> String {
        if let bundleID, let name = AppCatalog.shared.name(forBundleID: bundleID) { return name }
        if let program, let range = program.range(of: ".app/") {
            let appPath = String(program[program.startIndex..<range.lowerBound]) + ".app"
            return URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        }
        // Nhãn ngược tên miền đọc rất chán; lấy đoạn có nghĩa nhất làm tên.
        let parts = label.split(separator: ".").map(String.init)
        if parts.count >= 3, let last = parts.last, last.count > 2 {
            return parts.dropFirst(2).joined(separator: ".")
        }
        return label
    }
}
