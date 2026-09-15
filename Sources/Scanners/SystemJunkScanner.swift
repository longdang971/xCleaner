import Foundation

/// Rác hệ thống: bộ nhớ đệm, nhật ký, báo cáo sự cố, rác của công cụ lập trình.
///
/// Những gì nằm trong `/Library` thuộc sở hữu của root nên sẽ được đánh dấu `requiresAdmin`
/// và chỉ bị xoá sau khi người dùng nhập mật khẩu.
struct SystemJunkScanner: ModuleScanner {

    var stages: [ScanStage] {
        [.init(id: "user-cache", title: "Bộ nhớ đệm ứng dụng", icon: "shippingbox.fill"),
         .init(id: "sys-cache", title: "Bộ nhớ đệm hệ thống", icon: "lock.shield.fill"),
         .init(id: "dev-junk", title: "Công cụ lập trình", icon: "hammer.fill"),
         .init(id: "user-logs", title: "Nhật ký người dùng", icon: "doc.text.fill"),
         .init(id: "sys-logs", title: "Nhật ký hệ thống", icon: "server.rack"),
         .init(id: "crash", title: "Báo cáo sự cố", icon: "exclamationmark.triangle.fill"),
         .init(id: "misc", title: "Trạng thái cửa sổ", icon: "macwindow")]
    }

    /// Tên những thư mục con trong Application Support mà app dùng làm bộ nhớ đệm.
    /// Ứng dụng dựng trên Electron (VS Code, Slack, Discord, Spotify…) để cache ở đây chứ
    /// không phải ~/Library/Caches, nên chỉ quét Caches là bỏ sót hẳn một mảng lớn.
    static let appSupportCacheNames: Set<String> = [
        "Cache", "Caches", "caches", "Code Cache", "GPUCache", "CachedData",
        "CachedProfilesData", "CachedConfigurations", "CachedExtensions", "CachedExtensionVSIXs",
        "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "ShaderCache", "GrShaderCache",
        "Service Worker", "component_crx_cache", "blob_storage", "Crashpad"
    ]

    /// Bộ nhớ đệm nằm rải trong Application Support và Group Containers.
    /// Chỉ lấy đúng thư mục đệm, tuyệt đối không đụng thư mục dữ liệu của app.
    func scatteredCaches(cancel: CancelToken,
                         found: ((String, Int64) -> Void)? = nil) -> [CleanItem] {
        var result: [CleanItem] = []

        for appDir in FileUtils.children(of: FileUtils.homePath("Library/Application Support")) {
            if cancel.isCancelled { break }
            guard FileUtils.isDirectory(appDir) else { continue }
            let appName = appDir.lastPathComponent
            for child in FileUtils.children(of: appDir) {
                guard Self.appSupportCacheNames.contains(child.lastPathComponent) else { continue }
                if let item = makeItem(child,
                                       name: "\(prettyName(appName)) · \(child.lastPathComponent)",
                                       detail: FileUtils.prettyPath(child),
                                       emptyContentsOnly: true,
                                       cancel: cancel) {
                    found?(item.name, item.size)
                    result.append(item)
                }
            }
        }

        for group in FileUtils.children(of: FileUtils.homePath("Library/Group Containers")) {
            if cancel.isCancelled { break }
            let caches = group.appendingPathComponent("Library/Caches")
            if let item = makeItem(caches,
                                   name: "\(prettyName(group.lastPathComponent)) · Caches",
                                   detail: FileUtils.prettyPath(caches),
                                   emptyContentsOnly: true,
                                   cancel: cancel) {
                found?(item.name, item.size)
                result.append(item)
            }
        }

        return result
    }

    /// Danh sách "Mở gần đây" của từng ứng dụng và của hệ thống.
    ///
    /// macOS giữ chúng ở `~/Library/Application Support/com.apple.sharedfilelist`: mỗi app một
    /// tệp `.sfl3` đặt theo bundle id trong `ApplicationRecentDocuments`, cộng vài danh sách
    /// dùng chung. Thư mục này nằm sau hàng rào TCC nên chưa cấp Toàn quyền truy cập đĩa thì
    /// đọc ra rỗng.
    ///
    /// Tuyệt đối không đụng `FavoriteItems` và `FavoriteVolumes` — đó là mục yêu thích trong
    /// thanh bên Finder, xoá là người dùng mất hết lối tắt của mình.
    func recentLists(root: URL? = nil, cancel: CancelToken,
                     found: ((String, Int64) -> Void)? = nil) -> [CleanItem] {
        let base = root ?? FileUtils.homePath("Library/Application Support/com.apple.sharedfilelist")
        guard FileUtils.isDirectory(base) else { return [] }

        var result: [CleanItem] = []

        func add(_ url: URL, name: String, detail: String) {
            guard !url.lastPathComponent.contains("Favorite") else { return }
            if let item = makeItem(url, name: name, detail: detail,
                                   selected: false, cancel: cancel,
                                   category: "Danh sách mở gần đây") {
                found?(item.name, item.size)
                result.append(item)
            }
        }

        // Danh sách dùng chung của hệ thống. Khớp theo TÊN và bỏ qua đuôi: macOS 26 đã đổi
        // `.sfl3` thành `.sfl4`, gắn cứng đuôi là mất trắng cả bốn danh sách. Vẫn là danh
        // sách trắng — tệp nào không có tên trong bảng dưới thì không đụng đến.
        let shared: [String: String] = [
            "com.apple.LSSharedFileList.RecentDocuments": "Tài liệu mở gần đây",
            "com.apple.LSSharedFileList.RecentApplications": "Ứng dụng mở gần đây",
            "com.apple.LSSharedFileList.RecentServers": "Máy chủ đã kết nối",
            "com.apple.LSSharedFileList.RecentHosts": "Máy đã kết nối"
        ]
        for file in FileUtils.children(of: base) {
            if cancel.isCancelled { break }
            guard let label = shared[file.deletingPathExtension().lastPathComponent] else { continue }
            add(file, name: label, detail: "Danh sách của Finder")
        }

        // "Mở gần đây" của từng ứng dụng
        let perApp = base.appendingPathComponent("com.apple.LSSharedFileList.ApplicationRecentDocuments")
        for file in FileUtils.children(of: perApp) {
            if cancel.isCancelled { break }
            let id = file.deletingPathExtension().lastPathComponent
            let app = AppCatalog.shared.name(forBundleID: id) ?? id
            add(file, name: "Mở gần đây · \(app)", detail: "Menu Tệp ▸ Mở gần đây của \(app)")
        }

        return result.sorted { $0.size > $1.size }
    }

    /// Thư mục danh sách gần đây có bị macOS chặn đọc không.
    func recentListsBlocked() -> Bool {
        FileUtils.directoryState(
            FileUtils.homePath("Library/Application Support/com.apple.sharedfilelist")) == .blocked
    }

    func scan(cancel: CancelToken, progress: @escaping (ScanProgress) -> Void) -> [CleanGroup] {
        var groups: [CleanGroup] = []
        var found: Int64 = 0
        let stage = StageReporter(total: 7, emit: progress)

        /// `within` là phần đã xong của riêng chặng đó, để vòng tròn đi đều trong chặng.
        func report(_ step: Int, _ msg: String, _ within: Double? = nil) {
            if msg.isEmpty { stage.begin(step) } else { stage.working(msg, within: within) }
        }

        // 1. Bộ nhớ đệm người dùng
        report(0, "Bộ nhớ đệm ứng dụng…")
        var userCache = itemsFromChildren(
            of: FileUtils.homePath("Library/Caches"),
            skip: ["CloudKit", "com.apple.containermanagerd", "com.apple.nsurlsessiond"],
            cancel: cancel,
            progress: { report(0, "Bộ nhớ đệm: \($0)", $1) },
            found: { stage.found($0, $1) })
        userCache.append(contentsOf: itemsFromChildren(
            of: FileUtils.homePath("Library/Containers"),
            cancel: cancel).compactMap { item -> CleanItem? in
                // Chỉ lấy thư mục Caches bên trong container, không đụng dữ liệu app.
                let c = item.url.appendingPathComponent("Data/Library/Caches")
                return makeItem(c, name: item.name + " (container)", cancel: cancel)
            })
        userCache += scatteredCaches(cancel: cancel, found: { stage.found($0, $1) })
        userCache.sort { $0.size > $1.size }
        found += userCache.reduce(0) { $0 + $1.size }
        if !userCache.isEmpty {
            groups.append(CleanGroup(id: "user-cache", title: "Bộ nhớ đệm ứng dụng",
                                     subtitle: "Tệp tạm do app tạo ra, sẽ được dựng lại khi cần",
                                     icon: "shippingbox.fill", safety: .safe, items: userCache))
        }
        stage.finish(0, bytes: userCache.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 2. Bộ nhớ đệm hệ thống (cần quyền quản trị)
        report(1, "Bộ nhớ đệm hệ thống…")
        let systemCache = itemsFromChildren(
            of: URL(fileURLWithPath: "/Library/Caches"),
            cancel: cancel,
            progress: { report(1, "Hệ thống: \($0)", $1) },
            found: { stage.found($0, $1) })
        found += systemCache.reduce(0) { $0 + $1.size }
        if !systemCache.isEmpty {
            groups.append(CleanGroup(id: "sys-cache", title: "Bộ nhớ đệm hệ thống",
                                     subtitle: "Nằm trong /Library — cần mật khẩu quản trị",
                                     icon: "lock.shield.fill", safety: .safe, items: systemCache))
        }
        stage.finish(1, bytes: systemCache.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 3. Rác của công cụ lập trình
        report(2, "Công cụ lập trình…")
        var dev: [CleanItem] = []
        let devTargets: [(URL, String, String, Bool)] = [
            (FileUtils.homePath("Library/Developer/Xcode/DerivedData"), "Xcode DerivedData",
             "Kết quả build trung gian, Xcode tự dựng lại", true),
            (FileUtils.homePath("Library/Developer/Xcode/iOS DeviceSupport"), "iOS DeviceSupport",
             "Ký hiệu gỡ lỗi của các thiết bị đã kết nối", false),
            (FileUtils.homePath("Library/Developer/Xcode/watchOS DeviceSupport"), "watchOS DeviceSupport",
             "Ký hiệu gỡ lỗi", false),
            (FileUtils.homePath("Library/Developer/CoreSimulator/Caches"), "Simulator Caches",
             "Bộ nhớ đệm của trình giả lập", true),
            (FileUtils.homePath("Library/Caches/Homebrew"), "Homebrew", "Gói tải về của brew", true),
            (FileUtils.homePath("Library/Caches/pip"), "pip", "Gói Python đã tải", true),
            (FileUtils.homePath("Library/Caches/go-build"), "Go build", "Bộ nhớ đệm biên dịch Go", true),
            (FileUtils.homePath(".npm/_cacache"), "npm", "Bộ nhớ đệm gói npm", true),
            (FileUtils.homePath(".cache/yarn"), "Yarn", "Bộ nhớ đệm gói Yarn", true),
            (FileUtils.homePath(".gradle/caches"), "Gradle", "Bộ nhớ đệm Gradle", true),
            (FileUtils.homePath(".cocoapods/repos"), "CocoaPods repos",
             "Bản sao kho spec, `pod repo update` sẽ tải lại", false),
            (FileUtils.homePath("Library/Caches/CocoaPods"), "CocoaPods", "Bộ nhớ đệm CocoaPods", true),
            (FileUtils.homePath("Library/Caches/org.swift.swiftpm"), "Swift Package Manager",
             "Bản sao gói SwiftPM", true)
        ]
        for (i, (url, name, detail, selected)) in devTargets.enumerated() {
            if cancel.isCancelled { break }
            report(2, "Công cụ lập trình: \(name)", Double(i) / Double(devTargets.count))
            if let i = makeItem(url, name: name, detail: detail, selected: selected, cancel: cancel) {
                dev.append(i)
            }
        }
        dev.sort { $0.size > $1.size }
        found += dev.reduce(0) { $0 + $1.size }
        if !dev.isEmpty {
            groups.append(CleanGroup(id: "dev-junk", title: "Rác công cụ lập trình",
                                     subtitle: "Xoá xong lần build kế tiếp sẽ lâu hơn một chút",
                                     icon: "hammer.fill", safety: .review, items: dev))
        }
        stage.finish(2, bytes: dev.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 4. Nhật ký người dùng
        report(3, "Nhật ký người dùng…")
        var userLogs = itemsFromChildren(of: FileUtils.homePath("Library/Logs"), cancel: cancel,
                                         progress: { report(3, "Nhật ký: \($0)", $1) },
                                         found: { stage.found($0, $1) })
        userLogs.append(contentsOf: [
            FileUtils.homePath("Library/Application Support/CrashReporter")
        ].compactMap { makeItem($0, name: "CrashReporter", cancel: cancel) })
        found += userLogs.reduce(0) { $0 + $1.size }
        if !userLogs.isEmpty {
            groups.append(CleanGroup(id: "user-logs", title: "Nhật ký người dùng",
                                     subtitle: "Log do ứng dụng ghi ra trong lúc chạy",
                                     icon: "doc.text.fill", safety: .safe, items: userLogs))
        }
        stage.finish(3, bytes: userLogs.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 5. Nhật ký hệ thống (cần quyền quản trị)
        report(4, "Nhật ký hệ thống…")
        var sysLogs = itemsFromChildren(of: URL(fileURLWithPath: "/Library/Logs"), cancel: cancel,
                                        progress: { report(4, "Nhật ký hệ thống: \($0)", $1 * 0.6) },
                                        found: { stage.found($0, $1) })
        // Trong /var/log chỉ đụng tới log đã xoay vòng, tuyệt đối không xoá log đang mở.
        for f in FileUtils.children(of: URL(fileURLWithPath: "/private/var/log")) {
            if cancel.isCancelled { break }
            let n = f.lastPathComponent
            let isRotated = n.hasSuffix(".gz") || n.hasSuffix(".bz2") || n.hasSuffix(".old")
                || n.range(of: #"\.\d+$"#, options: .regularExpression) != nil
            guard isRotated else { continue }
            if let i = makeItem(f, detail: "Nhật ký đã xoay vòng", cancel: cancel) { sysLogs.append(i) }
        }
        if let asl = makeItem(URL(fileURLWithPath: "/private/var/log/asl"),
                              name: "asl", detail: "Nhật ký hệ thống cũ",
                              emptyContentsOnly: true, cancel: cancel) {
            sysLogs.append(asl)
        }
        sysLogs.sort { $0.size > $1.size }
        found += sysLogs.reduce(0) { $0 + $1.size }
        if !sysLogs.isEmpty {
            groups.append(CleanGroup(id: "sys-logs", title: "Nhật ký hệ thống",
                                     subtitle: "Log của macOS — cần mật khẩu quản trị",
                                     icon: "server.rack", safety: .safe, items: sysLogs))
        }
        stage.finish(4, bytes: sysLogs.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 6. Báo cáo sự cố
        report(5, "Báo cáo sự cố…")
        var crash: [CleanItem] = []
        for dir in [FileUtils.homePath("Library/Logs/DiagnosticReports"),
                    URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")] {
            for f in FileUtils.children(of: dir) where !f.lastPathComponent.hasPrefix(".") {
                if cancel.isCancelled { break }
                if let i = makeItem(f, detail: Fmt.relativeAge(FileUtils.modificationDate(of: f)),
                                    cancel: cancel) {
                    stage.found(i.name, i.size)
                    crash.append(i)
                }
            }
        }
        crash.sort { $0.size > $1.size }
        found += crash.reduce(0) { $0 + $1.size }
        if !crash.isEmpty {
            groups.append(CleanGroup(id: "crash", title: "Báo cáo sự cố",
                                     subtitle: "Biên bản khi app hoặc hệ thống gặp lỗi",
                                     icon: "exclamationmark.triangle.fill", safety: .safe, items: crash))
        }
        stage.finish(5, bytes: crash.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 7. Trạng thái ứng dụng đã lưu + gói cài đặt cũ
        report(6, "Mục khác…")
        var misc = itemsFromChildren(of: FileUtils.homePath("Library/Saved Application State"),
                                     selected: false, cancel: cancel,
                                     progress: { report(6, "Trạng thái cửa sổ: \($0)", $1 * 0.7) })
            .map { item -> CleanItem in
                var copy = item
                copy.category = "Trạng thái cửa sổ"
                return copy
            }
        misc += recentLists(cancel: cancel, found: { stage.found($0, $1) })
        let recentBlocked = recentListsBlocked()
        for f in FileUtils.children(of: URL(fileURLWithPath: "/Library/Updates")) {
            if let i = makeItem(f, detail: "Gói cập nhật đã tải", selected: false, cancel: cancel) {
                misc.append(i)
            }
        }
        found += misc.reduce(0) { $0 + $1.size }
        if !misc.isEmpty || recentBlocked {
            groups.append(CleanGroup(id: "misc", title: "Trạng thái cửa sổ đã lưu",
                                     subtitle: recentBlocked
                                        ? "Danh sách mở gần đây bị macOS chặn — cần Toàn quyền truy cập đĩa"
                                        : "Vị trí cửa sổ đang mở và danh sách mở gần đây của các app",
                                     icon: "macwindow", safety: .review, items: misc,
                                     needsFullDiskAccess: recentBlocked))
        }
        stage.finish(6, bytes: misc.reduce(0) { $0 + $1.size })

        stage.done()
        return groups
    }
}
