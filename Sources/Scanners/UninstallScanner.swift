import Foundation

/// Gỡ ứng dụng tận gốc: tìm mọi tệp mà app để lại rải rác trong hệ thống.
struct UninstallScanner {

    struct InstalledApp: Identifiable, Hashable {
        let id: String          // bundle id
        let name: String
        let url: URL
        let version: String
        var appSize: Int64
        var leftoverSize: Int64
        var lastUsed: Date?
        var isSystemApp: Bool
        var needsAdmin: Bool

        var totalSize: Int64 { appSize + leftoverSize }

        static func == (l: InstalledApp, r: InstalledApp) -> Bool { l.url == r.url }
        func hash(into h: inout Hasher) { h.combine(url) }
    }

    /// Nơi các app hay để lại dấu vết. `true` = nằm ngoài home nên cần quyền quản trị.
    private static let leftoverRoots: [(path: String, system: Bool, label: String)] = [
        ("Library/Application Support",           false, "Dữ liệu ứng dụng"),
        ("Library/Caches",                        false, "Bộ nhớ đệm"),
        ("Library/Preferences",                   false, "Tuỳ chọn"),
        ("Library/Containers",                    false, "Container"),
        ("Library/Group Containers",              false, "Group Container"),
        ("Library/Logs",                          false, "Nhật ký"),
        ("Library/Saved Application State",       false, "Trạng thái cửa sổ"),
        ("Library/HTTPStorages",                  false, "Dữ liệu mạng"),
        ("Library/WebKit",                        false, "Dữ liệu WebKit"),
        ("Library/Cookies",                       false, "Cookie"),
        ("Library/LaunchAgents",                  false, "Tác vụ nền"),
        ("Library/Application Scripts",           false, "Script ứng dụng"),
        // Bốn chỗ dưới đây nằm SÂU HƠN một tầng so với các thư mục trên. Vòng quét chỉ duyệt con
        // trực tiếp của mỗi thư mục, nên không kể tên ra ở đây thì không bao giờ tìm tới —
        // AppCleaner tìm được `com.titanium.OnyX.help*5.0.2` trong `com.apple.helpd/Generated`
        // còn xCleaner thì không, chính vì chuyện này.
        ("Library/Caches/com.apple.helpd/Generated", false, "Trợ giúp"),
        ("Library/Preferences/ByHost",            false, "Tuỳ chọn theo máy"),
        ("Library/Application Support/CrashReporter", false, "Báo cáo sự cố"),
        ("Library/Logs/DiagnosticReports",        false, "Nhật ký sự cố"),
        ("/Library/Application Support",          true,  "Dữ liệu ứng dụng (hệ thống)"),
        ("/Library/Caches",                       true,  "Bộ nhớ đệm (hệ thống)"),
        ("/Library/Preferences",                  true,  "Tuỳ chọn (hệ thống)"),
        ("/Library/Logs",                         true,  "Nhật ký (hệ thống)"),
        ("/Library/LaunchAgents",                 true,  "Tác vụ nền (hệ thống)"),
        ("/Library/LaunchDaemons",                true,  "Dịch vụ nền"),
        ("/Library/PrivilegedHelperTools",        true,  "Công cụ quyền cao"),
        ("/Library/Logs/DiagnosticReports",       true,  "Nhật ký sự cố (hệ thống)")
    ]

    // MARK: - Danh sách app

    func listApps(cancel: CancelToken, progress: @escaping (ScanProgress) -> Void) -> [InstalledApp] {
        AppCatalog.shared.refresh()
        let entries = AppCatalog.shared.allApps()
        var result: [InstalledApp] = []

        for (i, e) in entries.enumerated() {
            if cancel.isCancelled { break }
            progress(ScanProgress(fraction: Double(i) / Double(max(1, entries.count)), message: e.name))
            let size = FileUtils.size(of: e.url, isCancelled: { cancel.isCancelled })
            result.append(InstalledApp(
                id: e.bundleID,
                name: e.name,
                url: e.url,
                version: e.version,
                appSize: size,
                leftoverSize: 0,
                lastUsed: FileUtils.lastUsedDate(of: e.url),
                isSystemApp: e.url.path.hasPrefix("/System") || isAppleBundled(e.bundleID),
                needsAdmin: PrivilegedRunner.needsAdmin(for: e.url)))
        }
        progress(ScanProgress(fraction: 1, message: "Xong"))
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func isAppleBundled(_ bid: String) -> Bool {
        bid.hasPrefix("com.apple.")
    }

    // MARK: - Tệp còn sót

    /// Tìm mọi thứ liên quan tới app: chính bundle + tệp mang tên bundle id hoặc tên app.
    func leftovers(for app: InstalledApp, cancel: CancelToken) -> [CleanItem] {
        var items: [CleanItem] = []

        // Chính ứng dụng.
        if let appItem = makeItem(app.url, name: "\(app.name).app",
                                  detail: "Ứng dụng", cancel: cancel) {
            items.append(appItem)
        }

        let needles = matchTokens(for: app)

        for root in Self.leftoverRoots {
            if cancel.isCancelled { break }
            let base = root.path.hasPrefix("/")
                ? URL(fileURLWithPath: root.path)
                : FileUtils.homePath(root.path)
            guard FileUtils.isDirectory(base) else { continue }

            for child in FileUtils.children(of: base) {
                if cancel.isCancelled { break }
                let n = child.lastPathComponent
                guard matches(n, needles: needles) else { continue }
                guard child.path != app.url.path else { continue }
                if let i = makeItem(child, name: n, detail: root.label, cancel: cancel) {
                    items.append(i)
                }
            }
        }

        // Biên nhận cài đặt (.bom/.plist trong /var/db/receipts).
        let receipts = URL(fileURLWithPath: "/private/var/db/receipts")
        for f in FileUtils.children(of: receipts) {
            if cancel.isCancelled { break }
            let n = f.lastPathComponent
            guard matches(n, needles: needles) else { continue }
            if let i = makeItem(f, name: n, detail: "Biên nhận cài đặt", cancel: cancel) {
                items.append(i)
            }
        }

        // Bỏ mục trùng và mục nằm trong mục khác đã có.
        var seen = Set<String>()
        var unique: [CleanItem] = []
        for i in items.sorted(by: { $0.url.path.count < $1.url.path.count }) {
            let p = i.url.path
            if seen.contains(p) { continue }
            if unique.contains(where: { p.hasPrefix($0.url.path + "/") }) { continue }
            seen.insert(p)
            unique.append(i)
        }
        return unique.sorted { $0.size > $1.size }
    }

    /// Chuỗi dùng để nhận diện tệp của app: bundle id, tên app (bỏ dấu cách) và tiền tố nhà phát triển.
    private func matchTokens(for app: InstalledApp) -> [String] {
        var t: [String] = [app.id.lowercased()]
        let plain = app.name.lowercased()
        t.append(plain)
        t.append(plain.replacingOccurrences(of: " ", with: ""))
        // com.acme.MyApp → "com.acme.myapp" đã có; thêm "myapp"
        if let last = app.id.split(separator: ".").last, last.count >= 4 {
            t.append(String(last).lowercased())
        }
        return Array(Set(t)).filter { $0.count >= 4 }
    }

    private func matches(_ filename: String, needles: [String]) -> Bool {
        let f = filename.lowercased()
        for n in needles {
            if f == n || f.hasPrefix(n + ".") || f.hasPrefix(n + "-") || f.hasPrefix(n + "_") {
                return true
            }
            // Tên thư mục kiểu "MyApp" khớp chính xác, tránh khớp nhầm "Mail" với "Mailbird".
            if f == n { return true }
            if f.hasPrefix(n), f.count <= n.count + 6, f.dropFirst(n.count).allSatisfy({
                $0.isNumber || $0 == "." || $0 == "-" || $0 == "_"
            }) { return true }
        }
        return false
    }

    private func makeItem(_ url: URL, name: String, detail: String, cancel: CancelToken) -> CleanItem? {
        guard FileUtils.exists(url), SafetyGuard.isValid(url) else { return nil }
        let size = FileUtils.size(of: url, isCancelled: { cancel.isCancelled })
        return CleanItem(url: url, name: name,
                         detail: "\(detail) · \(FileUtils.prettyPath(url))",
                         size: size, isSelected: true,
                         requiresAdmin: PrivilegedRunner.needsAdmin(for: url),
                         isDirectory: FileUtils.isDirectory(url))
    }
}
