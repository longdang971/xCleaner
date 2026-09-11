import Foundation
import AppKit

/// Dấu vết duyệt web của mọi trình duyệt có trên máy, chia thành từng phần để người dùng
/// chọn giữ hay xoá: lịch sử, cookie, tự động điền, thẻ & phiên, bộ nhớ đệm, dữ liệu trang.
///
/// Quy ước chọn sẵn:
/// - Bộ nhớ đệm và các bảng phụ trợ (biểu tượng trang, gợi ý thanh địa chỉ) → chọn sẵn.
/// - Lịch sử → chọn sẵn, vì đó là thứ người dùng tìm đến mục này để xoá.
/// - Cookie, phiên, dữ liệu trang → **không** chọn sẵn: xoá là đăng xuất khỏi mọi trang
///   và mất các thẻ đang mở.
/// - Tự động điền → **không** chọn sẵn, đánh dấu cẩn trọng.
///
/// Mật khẩu đã lưu (`Login Data`, `logins.json`, `key4.db`) **cố tình không có mặt ở đây**.
/// Mất mật khẩu là mất hẳn, và không ai mong một công cụ dọn rác đụng tới chúng.
struct BrowserPrivacyScanner: ModuleScanner {

    // MARK: - Tên các phần

    enum Part {
        static let history  = "Lịch sử duyệt web"
        static let downloads = "Danh sách tải về"
        static let cookies  = "Cookie & đăng nhập"
        static let autofill = "Tự động điền"
        static let sessions = "Thẻ & phiên làm việc"
        static let cache    = "Bộ nhớ đệm"
        static let siteData = "Dữ liệu trang web"
    }

    /// Một thứ có thể xoá bên trong hồ sơ trình duyệt.
    private struct Entry {
        let file: String
        let name: String
        let detail: String
        let part: String
        var selected: Bool = true
        var safety: SafetyLevel = .safe
        /// Dọn ruột nhưng giữ lại thư mục (trình duyệt không tự tạo lại vài thư mục bộ nhớ đệm).
        var emptyOnly: Bool = false
    }

    // MARK: - Trình duyệt

    struct Browser {
        let name: String
        let bundleID: String
        let kind: Kind
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

    // MARK: - Quét

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

            let running = FileUtils.isRunning(bundleID: browser.bundleID)
            var items: [CleanItem] = []

            switch browser.kind {
            case .chromium: items = chromiumItems(browser, cancel: cancel, progress: progress)
            case .firefox:  items = firefoxItems(browser, cancel: cancel)
            case .safari:   items = safariItems(browser, cancel: cancel)
            }

            guard !items.isEmpty else { continue }
            found += items.reduce(0) { $0 + $1.size }

            // Sắp theo thứ tự phần đã định, trong mỗi phần thì mục nặng lên trước.
            let order = [Part.history, Part.downloads, Part.cookies, Part.autofill,
                         Part.sessions, Part.cache, Part.siteData]
            items.sort { a, b in
                let ia = order.firstIndex(of: a.category) ?? order.count
                let ib = order.firstIndex(of: b.category) ?? order.count
                return ia == ib ? a.size > b.size : ia < ib
            }

            let parts = Set(items.map(\.category)).count
            let blocked = isBlockedByPrivacy(browser)
            var subtitle = "\(parts) phần · \(items.count) mục"
            if running { subtitle = "⚠︎ Đang mở — hãy thoát trình duyệt trước khi dọn" }
            if blocked { subtitle = "Danh sách chưa đầy đủ — macOS đang chặn đọc thư mục này" }

            groups.append(CleanGroup(
                id: "browser-" + browser.bundleID,
                title: browser.name,
                subtitle: subtitle,
                icon: "globe",
                safety: .review,
                items: items,
                runningBundleID: running ? browser.bundleID : nil,
                needsFullDiskAccess: blocked))
        }

        progress(ScanProgress(fraction: 1, message: "Xong", bytesFound: found))
        return groups
    }

    /// Safari nằm sau hàng rào TCC: thư mục vẫn "tồn tại" nhưng liệt kê ra lại rỗng khi
    /// chưa được cấp Toàn quyền truy cập đĩa. Đó là cách nhận biết đáng tin nhất.
    private func isBlockedByPrivacy(_ b: Browser) -> Bool {
        guard b.kind == .safari else { return false }
        let dir = FileUtils.homePath("Library/Safari")
        guard FileUtils.exists(dir) else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return contents.isEmpty
    }

    // MARK: - Chromium

    /// Mọi thứ dưới đây nằm trong thư mục hồ sơ (Default, Profile 1…).
    private static let chromiumEntries: [Entry] = [
        // --- Lịch sử ---
        .init(file: "History", name: "Địa chỉ đã truy cập",
              detail: "Toàn bộ lịch sử. Không ảnh hưởng dấu trang.", part: Part.history),
        .init(file: "History-journal", name: "Lịch sử (nhật ký ghi)", detail: "", part: Part.history),
        .init(file: "History Provider Cache", name: "Bộ đệm lịch sử",
              detail: "Bản dựng sẵn để tra lịch sử cho nhanh", part: Part.history),
        .init(file: "Visited Links", name: "Liên kết đã xem",
              detail: "Thứ làm liên kết đã ghé đổi màu", part: Part.history),
        .init(file: "Top Sites", name: "Trang hay vào",
              detail: "Lưới gợi ý ở trang chủ", part: Part.history),
        .init(file: "Top Sites-journal", name: "Trang hay vào (nhật ký)", detail: "", part: Part.history),
        .init(file: "Network Action Predictor", name: "Gợi ý thanh địa chỉ",
              detail: "Đoán địa chỉ khi bạn vừa gõ vài ký tự", part: Part.history),
        .init(file: "Shortcuts", name: "Lối tắt thanh địa chỉ",
              detail: "Ghi nhớ bạn hay chọn kết quả nào", part: Part.history),
        .init(file: "Shortcuts-journal", name: "Lối tắt (nhật ký)", detail: "", part: Part.history),
        .init(file: "Favicons", name: "Biểu tượng trang",
              detail: "Hình nhỏ cạnh tên trang, sẽ tải lại khi cần", part: Part.history),
        .init(file: "Favicons-journal", name: "Biểu tượng trang (nhật ký)", detail: "", part: Part.history),

        // --- Cookie ---
        .init(file: "Network/Cookies", name: "Cookie",
              detail: "Xoá là đăng xuất khỏi mọi trang đang đăng nhập",
              part: Part.cookies, selected: false, safety: .review),
        .init(file: "Network/Cookies-journal", name: "Cookie (nhật ký)", detail: "",
              part: Part.cookies, selected: false, safety: .review),
        .init(file: "Cookies", name: "Cookie (vị trí cũ)",
              detail: "Xoá là đăng xuất khỏi mọi trang đang đăng nhập",
              part: Part.cookies, selected: false, safety: .review),
        .init(file: "Cookies-journal", name: "Cookie cũ (nhật ký)", detail: "",
              part: Part.cookies, selected: false, safety: .review),
        .init(file: "Trust Tokens", name: "Trust Token",
              detail: "Dấu tin cậy chống gian lận của các trang",
              part: Part.cookies, selected: false, safety: .review),

        // --- Tự động điền ---
        .init(file: "Web Data", name: "Dữ liệu tự động điền",
              detail: "Biểu mẫu, địa chỉ và thẻ thanh toán đã lưu trong trình duyệt",
              part: Part.autofill, selected: false, safety: .sensitive),
        .init(file: "Web Data-journal", name: "Tự động điền (nhật ký)", detail: "",
              part: Part.autofill, selected: false, safety: .sensitive),
        .init(file: "AutofillStrikeDatabase", name: "Thống kê tự động điền",
              detail: "Ghi nhận lần nào bạn bỏ qua gợi ý điền",
              part: Part.autofill, selected: false, safety: .review),

        // --- Thẻ & phiên ---
        .init(file: "Sessions", name: "Thẻ đang mở & vừa đóng",
              detail: "Xoá thì không khôi phục lại thẻ vừa đóng được nữa",
              part: Part.sessions, selected: false, safety: .review),
        .init(file: "Current Session", name: "Phiên hiện tại", detail: "",
              part: Part.sessions, selected: false, safety: .review),
        .init(file: "Current Tabs", name: "Thẻ hiện tại", detail: "",
              part: Part.sessions, selected: false, safety: .review),
        .init(file: "Last Session", name: "Phiên lần trước",
              detail: "Dùng cho lệnh Mở lại cửa sổ đã đóng",
              part: Part.sessions, selected: false, safety: .review),
        .init(file: "Last Tabs", name: "Thẻ lần trước", detail: "",
              part: Part.sessions, selected: false, safety: .review),
        .init(file: "Session Storage", name: "Session Storage",
              detail: "Dữ liệu tạm của trang trong phiên",
              part: Part.sessions, selected: false, safety: .review),

        // --- Bộ nhớ đệm ---
        .init(file: "Cache", name: "Bộ nhớ đệm trang",
              detail: "Ảnh và tệp trang web đã tải", part: Part.cache, emptyOnly: true),
        .init(file: "Code Cache", name: "Bộ nhớ đệm mã",
              detail: "JavaScript và WebAssembly đã biên dịch", part: Part.cache, emptyOnly: true),
        .init(file: "GPUCache", name: "Bộ nhớ đệm GPU",
              detail: "Kết quả kết xuất đồ hoạ", part: Part.cache, emptyOnly: true),
        .init(file: "DawnCache", name: "Bộ nhớ đệm Dawn", detail: "", part: Part.cache, emptyOnly: true),
        .init(file: "DawnGraphiteCache", name: "Bộ nhớ đệm Dawn Graphite", detail: "",
              part: Part.cache, emptyOnly: true),
        .init(file: "DawnWebGPUCache", name: "Bộ nhớ đệm WebGPU", detail: "",
              part: Part.cache, emptyOnly: true),
        .init(file: "Service Worker", name: "Service Worker",
              detail: "Bản trang lưu sẵn để chạy khi mất mạng", part: Part.cache, emptyOnly: true),
        .init(file: "Application Cache", name: "Application Cache", detail: "",
              part: Part.cache, emptyOnly: true),

        // --- Dữ liệu trang ---
        .init(file: "Local Storage", name: "Local Storage",
              detail: "Trang lưu thiết lập và có khi cả phiên đăng nhập ở đây",
              part: Part.siteData, selected: false, safety: .review),
        .init(file: "IndexedDB", name: "IndexedDB",
              detail: "Cơ sở dữ liệu của trang, gồm cả dữ liệu ngoại tuyến",
              part: Part.siteData, selected: false, safety: .review),
        .init(file: "databases", name: "Web SQL", detail: "",
              part: Part.siteData, selected: false, safety: .review),
        .init(file: "File System", name: "File System API", detail: "",
              part: Part.siteData, selected: false, safety: .review),
        .init(file: "blob_storage", name: "Blob Storage", detail: "Tệp tạm của trang",
              part: Part.siteData, emptyOnly: true)
    ]

    private func chromiumItems(_ b: Browser, cancel: CancelToken,
                               progress: @escaping (ScanProgress) -> Void) -> [CleanItem] {
        var items: [CleanItem] = []
        let root = FileUtils.homePath(b.support)

        // Bộ nhớ đệm nằm ngoài hồ sơ
        for cache in b.caches {
            if let i = makeItem(FileUtils.homePath(cache), name: "Bộ nhớ đệm ứng dụng",
                                detail: "Tệp trang web đã tải về máy",
                                emptyContentsOnly: true, cancel: cancel,
                                category: Part.cache) {
                items.append(i)
            }
        }

        var profiles = FileUtils.children(of: root).filter {
            let n = $0.lastPathComponent
            return FileUtils.isDirectory($0) && (n == "Default" || n.hasPrefix("Profile "))
        }
        if profiles.isEmpty && FileUtils.isDirectory(root) { profiles = [root] }

        for p in profiles {
            if cancel.isCancelled { break }
            let label = (p.lastPathComponent == "Default" || p == root) ? "" : " · \(p.lastPathComponent)"
            progress(ScanProgress(fraction: 0, message: "\(b.name)\(label)"))

            for e in Self.chromiumEntries {
                if cancel.isCancelled { break }
                if let i = makeItem(p.appendingPathComponent(e.file),
                                    name: e.name + label,
                                    detail: e.detail,
                                    selected: e.selected,
                                    emptyContentsOnly: e.emptyOnly,
                                    cancel: cancel,
                                    category: e.part,
                                    safety: e.safety) {
                    items.append(i)
                }
            }
        }
        return items
    }

    // MARK: - Firefox

    /// `places.sqlite` chứa **cả lịch sử lẫn dấu trang** nên không bao giờ có mặt ở đây.
    private static let firefoxEntries: [Entry] = [
        .init(file: "favicons.sqlite", name: "Biểu tượng trang",
              detail: "Hình nhỏ cạnh tên trang", part: Part.history),
        .init(file: "favicons.sqlite-wal", name: "Biểu tượng trang (nhật ký)", detail: "",
              part: Part.history),

        .init(file: "cookies.sqlite", name: "Cookie",
              detail: "Xoá là đăng xuất khỏi mọi trang đang đăng nhập",
              part: Part.cookies, selected: false, safety: .review),
        .init(file: "cookies.sqlite-wal", name: "Cookie (nhật ký)", detail: "",
              part: Part.cookies, selected: false, safety: .review),

        .init(file: "formhistory.sqlite", name: "Lịch sử biểu mẫu",
              detail: "Những gì bạn từng gõ vào ô tìm kiếm và biểu mẫu",
              part: Part.autofill, selected: false, safety: .sensitive),
        .init(file: "autofill-profiles.json", name: "Địa chỉ đã lưu",
              detail: "Hồ sơ tự động điền địa chỉ",
              part: Part.autofill, selected: false, safety: .sensitive),

        .init(file: "sessionstore.jsonlz4", name: "Phiên làm việc",
              detail: "Thẻ đang mở sẽ không khôi phục được",
              part: Part.sessions, selected: false, safety: .review),
        .init(file: "recovery.jsonlz4", name: "Phiên khôi phục", detail: "",
              part: Part.sessions, selected: false, safety: .review),
        .init(file: "sessionstore-backups", name: "Sao lưu phiên",
              detail: "Bản chụp các thẻ ở những lần trước", part: Part.sessions),

        .init(file: "startupCache", name: "Bộ nhớ đệm khởi động",
              detail: "Dựng lại ở lần mở kế tiếp", part: Part.cache, emptyOnly: true),
        .init(file: "thumbnails", name: "Ảnh thu nhỏ",
              detail: "Hình xem trước ở trang chủ", part: Part.cache, emptyOnly: true),
        .init(file: "shader-cache", name: "Bộ nhớ đệm shader", detail: "",
              part: Part.cache, emptyOnly: true),

        .init(file: "webappsstore.sqlite", name: "Local Storage",
              detail: "Trang lưu thiết lập và có khi cả phiên đăng nhập ở đây",
              part: Part.siteData, selected: false, safety: .review),
        .init(file: "storage/default", name: "Dữ liệu trang",
              detail: "IndexedDB và bộ nhớ ngoại tuyến của các trang",
              part: Part.siteData, selected: false, safety: .review)
    ]

    private func firefoxItems(_ b: Browser, cancel: CancelToken) -> [CleanItem] {
        var items: [CleanItem] = []

        for cacheRoot in b.caches {
            for profile in FileUtils.children(of: FileUtils.homePath(cacheRoot)) {
                if let i = makeItem(profile.appendingPathComponent("cache2"),
                                    name: "Bộ nhớ đệm trang · \(profile.lastPathComponent)",
                                    detail: "Ảnh và tệp trang web đã tải",
                                    emptyContentsOnly: true, cancel: cancel,
                                    category: Part.cache) {
                    items.append(i)
                }
            }
        }

        for profile in FileUtils.children(of: FileUtils.homePath(b.support)) {
            if cancel.isCancelled { break }
            guard FileUtils.isDirectory(profile) else { continue }
            let label = " · \(profile.lastPathComponent)"

            for e in Self.firefoxEntries {
                if let i = makeItem(profile.appendingPathComponent(e.file),
                                    name: e.name + label,
                                    detail: e.detail,
                                    selected: e.selected,
                                    emptyContentsOnly: e.emptyOnly,
                                    cancel: cancel,
                                    category: e.part,
                                    safety: e.safety) {
                    items.append(i)
                }
            }
        }
        return items
    }

    // MARK: - Safari

    /// Đường dẫn tính từ thư mục nhà. Cần Full Disk Access mới đọc được phần lớn trong số này.
    private static let safariEntries: [Entry] = [
        .init(file: "Library/Safari/History.db", name: "Địa chỉ đã truy cập",
              detail: "Toàn bộ lịch sử. Không ảnh hưởng dấu trang.", part: Part.history),
        .init(file: "Library/Safari/History.db-wal", name: "Lịch sử (nhật ký ghi)", detail: "",
              part: Part.history),
        .init(file: "Library/Safari/History.db-shm", name: "Lịch sử (bộ nhớ chia sẻ)", detail: "",
              part: Part.history),
        .init(file: "Library/Safari/TopSites.plist", name: "Trang hay vào",
              detail: "Lưới gợi ý ở trang đầu", part: Part.history),
        .init(file: "Library/Safari/Favicon Cache", name: "Biểu tượng trang",
              detail: "Hình nhỏ cạnh tên trang", part: Part.history, emptyOnly: true),
        .init(file: "Library/Safari/Touch Icons Cache", name: "Biểu tượng cảm ứng", detail: "",
              part: Part.history, emptyOnly: true),
        .init(file: "Library/Safari/Template Icons", name: "Biểu tượng mẫu", detail: "",
              part: Part.history, emptyOnly: true),

        .init(file: "Library/Safari/Downloads.plist", name: "Danh sách tải về",
              detail: "Chỉ xoá danh sách, tệp đã tải vẫn còn nguyên", part: Part.downloads),

        .init(file: "Library/Cookies/Cookies.binarycookies", name: "Cookie",
              detail: "Xoá là đăng xuất khỏi mọi trang đang đăng nhập",
              part: Part.cookies, selected: false, safety: .review),
        .init(file: "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
              name: "Cookie (container)",
              detail: "Xoá là đăng xuất khỏi mọi trang đang đăng nhập",
              part: Part.cookies, selected: false, safety: .review),

        .init(file: "Library/Safari/Form Values", name: "Giá trị biểu mẫu đã lưu",
              detail: "Những gì Safari tự điền lại vào biểu mẫu",
              part: Part.autofill, selected: false, safety: .sensitive),
        .init(file: "Library/Safari/AutoFillCorrections.db", name: "Sửa lỗi tự động điền",
              detail: "Ghi nhận bạn hay sửa lại gợi ý nào",
              part: Part.autofill, selected: false, safety: .sensitive),
        .init(file: "Library/Safari/AutoFillCorrections.db-wal", name: "Tự động điền (nhật ký)",
              detail: "", part: Part.autofill, selected: false, safety: .sensitive),

        .init(file: "Library/Safari/RecentlyClosedTabs.plist", name: "Thẻ vừa đóng",
              detail: "Danh sách để mở lại thẻ vừa đóng",
              part: Part.sessions, selected: false, safety: .review),
        .init(file: "Library/Safari/LastSession.plist", name: "Phiên lần trước",
              detail: "Các thẻ sẽ mở lại khi khởi động Safari",
              part: Part.sessions, selected: false, safety: .review),
        .init(file: "Library/Safari/CloudTabs.db", name: "Thẻ từ thiết bị khác",
              detail: "Danh sách thẻ iCloud của iPhone, iPad",
              part: Part.sessions, selected: false, safety: .review),

        .init(file: "Library/Containers/com.apple.Safari/Data/Library/Caches/WebKit",
              name: "Bộ nhớ đệm WebKit", detail: "Tệp trang web đã tải",
              part: Part.cache, emptyOnly: true),

        .init(file: "Library/Safari/Databases", name: "Cơ sở dữ liệu trang",
              detail: "Dữ liệu các trang lưu trên máy",
              part: Part.siteData, selected: false, safety: .review),
        .init(file: "Library/Safari/LocalStorage", name: "Local Storage",
              detail: "Trang lưu thiết lập và có khi cả phiên đăng nhập ở đây",
              part: Part.siteData, selected: false, safety: .review)
    ]

    private func safariItems(_ b: Browser, cancel: CancelToken) -> [CleanItem] {
        var items: [CleanItem] = []

        for cache in b.caches {
            if let i = makeItem(FileUtils.homePath(cache), name: "Bộ nhớ đệm ứng dụng",
                                detail: "Tệp trang web đã tải về máy",
                                emptyContentsOnly: true, cancel: cancel,
                                category: Part.cache) {
                items.append(i)
            }
        }

        for e in Self.safariEntries {
            if cancel.isCancelled { break }
            if let i = makeItem(FileUtils.homePath(e.file),
                                name: e.name, detail: e.detail,
                                selected: e.selected,
                                emptyContentsOnly: e.emptyOnly,
                                cancel: cancel,
                                category: e.part,
                                safety: e.safety) {
                items.append(i)
            }
        }

        if items.isEmpty && FileUtils.exists(FileUtils.homePath("Library/Safari")) {
            NSLog("[xCleaner] Không đọc được dữ liệu Safari — có thể thiếu Full Disk Access.")
        }
        return items
    }
}
