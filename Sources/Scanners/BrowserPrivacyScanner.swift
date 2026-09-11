import Foundation
import AppKit

/// Dấu vết duyệt web: bộ nhớ đệm, cookie, lịch sử, phiên đăng nhập của mọi trình duyệt có trên máy.
///
/// Quy ước chọn sẵn:
/// - Bộ nhớ đệm → chọn sẵn (mất không sao).
/// - Lịch sử → chọn sẵn ở mức "nên xem lại".
/// - Cookie / phiên → **không** chọn sẵn, vì xoá là đăng xuất khỏi mọi trang.
struct BrowserPrivacyScanner: ModuleScanner {

    struct Browser {
        let name: String
        let bundleID: String
        let kind: Kind
        /// Thư mục hồ sơ (Application Support) và thư mục bộ nhớ đệm (Caches).
        let support: String
        let caches: [String]

        enum Kind { case chromium, firefox, safari }
    }

    static let browsers: [Browser] = [
        .init(name: "Google Chrome", bundleID: "com.google.Chrome", kind: .chromium,
              support: "Library/Application Support/Google/Chrome",
              caches: ["Library/Caches/Google/Chrome"]),
        .init(name: "Google Chrome Canary", bundleID: "com.google.Chrome.canary", kind: .chromium,
              support: "Library/Application Support/Google/Chrome Canary",
              caches: ["Library/Caches/Google/Chrome Canary"]),
        .init(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", kind: .chromium,
              support: "Library/Application Support/Microsoft Edge",
              caches: ["Library/Caches/Microsoft Edge"]),
        .init(name: "Brave", bundleID: "com.brave.Browser", kind: .chromium,
              support: "Library/Application Support/BraveSoftware/Brave-Browser",
              caches: ["Library/Caches/BraveSoftware/Brave-Browser"]),
        .init(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", kind: .chromium,
              support: "Library/Application Support/Vivaldi",
              caches: ["Library/Caches/Vivaldi"]),
        .init(name: "Opera", bundleID: "com.operasoftware.Opera", kind: .chromium,
              support: "Library/Application Support/com.operasoftware.Opera",
              caches: ["Library/Caches/com.operasoftware.Opera"]),
        .init(name: "Arc", bundleID: "company.thebrowser.Browser", kind: .chromium,
              support: "Library/Application Support/Arc/User Data",
              caches: ["Library/Caches/company.thebrowser.Browser"]),
        .init(name: "Chromium", bundleID: "org.chromium.Chromium", kind: .chromium,
              support: "Library/Application Support/Chromium",
              caches: ["Library/Caches/Chromium"]),
        .init(name: "Firefox", bundleID: "org.mozilla.firefox", kind: .firefox,
              support: "Library/Application Support/Firefox/Profiles",
              caches: ["Library/Caches/Firefox/Profiles"]),
        .init(name: "Zen", bundleID: "app.zen-browser.zen", kind: .firefox,
              support: "Library/Application Support/zen/Profiles",
              caches: ["Library/Caches/zen/Profiles"]),
        .init(name: "Safari", bundleID: "com.apple.Safari", kind: .safari,
              support: "Library/Safari",
              caches: ["Library/Caches/com.apple.Safari",
                       "Library/Containers/com.apple.Safari/Data/Library/Caches"])
    ]

    func scan(cancel: CancelToken, progress: @escaping (ScanProgress) -> Void) -> [CleanGroup] {
        var groups: [CleanGroup] = []
        var found: Int64 = 0

        let present = Self.browsers.filter { b in
            FileUtils.exists(FileUtils.homePath(b.support))
                || b.caches.contains { FileUtils.exists(FileUtils.homePath($0)) }
        }

        for (idx, browser) in present.enumerated() {
            if cancel.isCancelled { break }
            progress(ScanProgress(fraction: Double(idx) / Double(max(1, present.count)),
                                  message: browser.name, bytesFound: found))

            var items: [CleanItem] = []
            let running = FileUtils.isRunning(bundleID: browser.bundleID)

            switch browser.kind {
            case .chromium: items = chromiumItems(browser, cancel: cancel)
            case .firefox:  items = firefoxItems(browser, cancel: cancel)
            case .safari:   items = safariItems(browser, cancel: cancel)
            }

            guard !items.isEmpty else { continue }
            found += items.reduce(0) { $0 + $1.size }

            groups.append(CleanGroup(
                id: "browser-" + browser.bundleID,
                title: browser.name,
                subtitle: running
                    ? "⚠︎ Đang mở — hãy thoát trình duyệt trước khi dọn"
                    : "\(items.count) mục",
                icon: "globe",
                safety: .review,
                items: items.sorted { $0.size > $1.size },
                runningBundleID: running ? browser.bundleID : nil))
        }

        progress(ScanProgress(fraction: 1, message: "Xong", bytesFound: found))
        return groups
    }

    // MARK: - Chromium

    private func chromiumItems(_ b: Browser, cancel: CancelToken) -> [CleanItem] {
        var items: [CleanItem] = []
        let root = FileUtils.homePath(b.support)

        for cache in b.caches {
            if let i = makeItem(FileUtils.homePath(cache), name: "Bộ nhớ đệm",
                                detail: "Ảnh và tệp trang web đã tải", emptyContentsOnly: true,
                                cancel: cancel) { items.append(i) }
        }

        // Mỗi hồ sơ (Default, Profile 1…) có bộ tệp riêng.
        var profiles = FileUtils.children(of: root).filter {
            let n = $0.lastPathComponent
            return FileUtils.isDirectory($0) && (n == "Default" || n.hasPrefix("Profile "))
        }
        if profiles.isEmpty && FileUtils.isDirectory(root) { profiles = [root] }

        for p in profiles {
            if cancel.isCancelled { break }
            let label = p.lastPathComponent == "Default" ? "" : " · \(p.lastPathComponent)"

            let spec: [(file: String, name: String, detail: String, selected: Bool)] = [
                ("Cache",            "Bộ nhớ đệm hồ sơ\(label)", "Tệp trang web đã tải về", true),
                ("Code Cache",       "Bộ nhớ đệm mã\(label)",    "JavaScript đã biên dịch", true),
                ("GPUCache",         "Bộ nhớ đệm GPU\(label)",   "Kết xuất đồ hoạ", true),
                ("Service Worker",   "Service Worker\(label)",   "Dữ liệu ngoại tuyến của trang", false),
                ("History",          "Lịch sử duyệt web\(label)", "Địa chỉ đã truy cập (không ảnh hưởng dấu trang)", true),
                ("History-journal",  "Lịch sử (nhật ký)\(label)", "", true),
                ("Visited Links",    "Liên kết đã xem\(label)",  "Đánh dấu link đã ghé", true),
                ("Top Sites",        "Trang hay vào\(label)",    "Ô gợi ý ở trang chủ", true),
                ("Cookies",          "Cookie\(label)",           "Xoá sẽ đăng xuất khỏi các trang", false),
                ("Cookies-journal",  "Cookie (nhật ký)\(label)", "", false),
                ("Network/Cookies",  "Cookie (mạng)\(label)",    "Xoá sẽ đăng xuất khỏi các trang", false),
                ("Sessions",         "Phiên làm việc\(label)",   "Tab đang mở sẽ không khôi phục được", false),
                ("Local Storage",    "Local Storage\(label)",    "Dữ liệu trang lưu cục bộ", false),
                ("Session Storage",  "Session Storage\(label)",  "", false),
                ("IndexedDB",        "IndexedDB\(label)",        "Cơ sở dữ liệu của trang web", false)
            ]
            for s in spec {
                if let i = makeItem(p.appendingPathComponent(s.file), name: s.name,
                                    detail: s.detail, selected: s.selected, cancel: cancel) {
                    items.append(i)
                }
            }
        }
        return items
    }

    // MARK: - Firefox

    private func firefoxItems(_ b: Browser, cancel: CancelToken) -> [CleanItem] {
        var items: [CleanItem] = []

        for cacheRoot in b.caches {
            let root = FileUtils.homePath(cacheRoot)
            for profile in FileUtils.children(of: root) {
                if let i = makeItem(profile.appendingPathComponent("cache2"),
                                    name: "Bộ nhớ đệm · \(profile.lastPathComponent)",
                                    detail: "Tệp trang web đã tải", emptyContentsOnly: true,
                                    cancel: cancel) { items.append(i) }
            }
        }

        for profile in FileUtils.children(of: FileUtils.homePath(b.support)) {
            if cancel.isCancelled { break }
            guard FileUtils.isDirectory(profile) else { continue }
            let label = profile.lastPathComponent

            // places.sqlite chứa cả lịch sử **và** dấu trang nên không bao giờ xoá cả tệp.
            let spec: [(String, String, String, Bool)] = [
                ("cookies.sqlite",       "Cookie · \(label)", "Xoá sẽ đăng xuất khỏi các trang", false),
                ("sessionstore.jsonlz4", "Phiên làm việc · \(label)", "Tab đang mở", false),
                ("sessionstore-backups", "Sao lưu phiên · \(label)", "", true),
                ("storage/default",      "Dữ liệu trang · \(label)", "IndexedDB, Local Storage", false),
                ("thumbnails",           "Ảnh thu nhỏ · \(label)", "Hình xem trước trang chủ", true),
                ("startupCache",         "Bộ nhớ đệm khởi động · \(label)", "", true)
            ]
            for (file, name, detail, selected) in spec {
                if let i = makeItem(profile.appendingPathComponent(file), name: name,
                                    detail: detail, selected: selected, cancel: cancel) {
                    items.append(i)
                }
            }
        }
        return items
    }

    // MARK: - Safari

    private func safariItems(_ b: Browser, cancel: CancelToken) -> [CleanItem] {
        var items: [CleanItem] = []

        for cache in b.caches {
            if let i = makeItem(FileUtils.homePath(cache), name: "Bộ nhớ đệm",
                                detail: "Tệp trang web đã tải", emptyContentsOnly: true,
                                cancel: cancel) { items.append(i) }
        }

        let spec: [(String, String, String, Bool)] = [
            ("Library/Safari/History.db",            "Lịch sử duyệt web", "Không ảnh hưởng dấu trang", true),
            ("Library/Safari/History.db-wal",        "Lịch sử (nhật ký)", "", true),
            ("Library/Safari/History.db-shm",        "Lịch sử (bộ nhớ chia sẻ)", "", true),
            ("Library/Safari/Downloads.plist",       "Danh sách tải về", "", true),
            ("Library/Safari/TopSites.plist",        "Trang hay vào", "", true),
            ("Library/Safari/RecentlyClosedTabs.plist", "Tab vừa đóng", "", true),
            ("Library/Containers/com.apple.Safari/Data/Library/Caches/WebKit",
             "Bộ nhớ đệm WebKit", "", true),
            ("Library/Cookies/Cookies.binarycookies", "Cookie", "Xoá sẽ đăng xuất khỏi các trang", false),
            ("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
             "Cookie (container)", "Xoá sẽ đăng xuất khỏi các trang", false)
        ]
        for (path, name, detail, selected) in spec {
            if let i = makeItem(FileUtils.homePath(path), name: name, detail: detail,
                                selected: selected, cancel: cancel) { items.append(i) }
        }

        if items.isEmpty && FileUtils.exists(FileUtils.homePath("Library/Safari")) {
            // Thường là do chưa cấp Full Disk Access — báo cho người dùng bằng một mục rỗng có chú thích.
            NSLog("[xCleaner] Không đọc được dữ liệu Safari — có thể thiếu Full Disk Access.")
        }
        return items
    }
}
