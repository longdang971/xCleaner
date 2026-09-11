import Foundation

/// Rác hệ thống: bộ nhớ đệm, nhật ký, báo cáo sự cố, rác của công cụ lập trình.
///
/// Những gì nằm trong `/Library` thuộc sở hữu của root nên sẽ được đánh dấu `requiresAdmin`
/// và chỉ bị xoá sau khi người dùng nhập mật khẩu.
struct SystemJunkScanner: ModuleScanner {

    var stages: [ScanStage] {
        [.init(id: "user-cache", title: "Bộ nhớ đệm ứng dụng", icon: "shippingbox.fill"),
         .init(id: "user-logs", title: "Nhật ký người dùng", icon: "doc.text.fill"),
         .init(id: "sys-logs", title: "Nhật ký hệ thống", icon: "server.rack"),
         .init(id: "crash", title: "Báo cáo sự cố", icon: "exclamationmark.triangle.fill"),
         .init(id: "sys-cache", title: "Bộ nhớ đệm hệ thống", icon: "lock.shield.fill"),
         .init(id: "dev-junk", title: "Công cụ lập trình", icon: "hammer.fill"),
         .init(id: "misc", title: "Trạng thái cửa sổ", icon: "macwindow")]
    }

    func scan(cancel: CancelToken, progress: @escaping (ScanProgress) -> Void) -> [CleanGroup] {
        var groups: [CleanGroup] = []
        var found: Int64 = 0
        let stage = StageReporter(total: 7, emit: progress)

        func report(_ step: Int, _ of: Int, _ msg: String) {
            if msg.isEmpty { stage.begin(step) } else { stage.working(msg) }
        }

        let steps = 7

        // 1. Bộ nhớ đệm người dùng
        report(0, steps, "Bộ nhớ đệm ứng dụng…")
        var userCache = itemsFromChildren(
            of: FileUtils.homePath("Library/Caches"),
            skip: ["CloudKit", "com.apple.containermanagerd", "com.apple.nsurlsessiond"],
            cancel: cancel,
            progress: { report(0, steps, "Bộ nhớ đệm: \($0)") })
        userCache.append(contentsOf: itemsFromChildren(
            of: FileUtils.homePath("Library/Containers"),
            cancel: cancel).compactMap { item -> CleanItem? in
                // Chỉ lấy thư mục Caches bên trong container, không đụng dữ liệu app.
                let c = item.url.appendingPathComponent("Data/Library/Caches")
                return makeItem(c, name: item.name + " (container)", cancel: cancel)
            })
        found += userCache.reduce(0) { $0 + $1.size }
        if !userCache.isEmpty {
            groups.append(CleanGroup(id: "user-cache", title: "Bộ nhớ đệm ứng dụng",
                                     subtitle: "Tệp tạm do app tạo ra, sẽ được dựng lại khi cần",
                                     icon: "shippingbox.fill", safety: .safe, items: userCache))
        }
        stage.finish(0, bytes: userCache.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 2. Nhật ký người dùng
        report(1, steps, "Nhật ký người dùng…")
        var userLogs = itemsFromChildren(of: FileUtils.homePath("Library/Logs"), cancel: cancel)
        userLogs.append(contentsOf: [
            FileUtils.homePath("Library/Application Support/CrashReporter")
        ].compactMap { makeItem($0, name: "CrashReporter", cancel: cancel) })
        found += userLogs.reduce(0) { $0 + $1.size }
        if !userLogs.isEmpty {
            groups.append(CleanGroup(id: "user-logs", title: "Nhật ký người dùng",
                                     subtitle: "Log do ứng dụng ghi ra trong lúc chạy",
                                     icon: "doc.text.fill", safety: .safe, items: userLogs))
        }
        stage.finish(1, bytes: userLogs.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 3. Nhật ký hệ thống (cần quyền quản trị)
        report(2, steps, "Nhật ký hệ thống…")
        var sysLogs = itemsFromChildren(of: URL(fileURLWithPath: "/Library/Logs"), cancel: cancel)
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
        stage.finish(2, bytes: sysLogs.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 4. Báo cáo sự cố
        report(3, steps, "Báo cáo sự cố…")
        var crash: [CleanItem] = []
        for dir in [FileUtils.homePath("Library/Logs/DiagnosticReports"),
                    URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")] {
            for f in FileUtils.children(of: dir) where !f.lastPathComponent.hasPrefix(".") {
                if cancel.isCancelled { break }
                if let i = makeItem(f, detail: Fmt.relativeAge(FileUtils.modificationDate(of: f)),
                                    cancel: cancel) { crash.append(i) }
            }
        }
        crash.sort { $0.size > $1.size }
        found += crash.reduce(0) { $0 + $1.size }
        if !crash.isEmpty {
            groups.append(CleanGroup(id: "crash", title: "Báo cáo sự cố",
                                     subtitle: "Biên bản khi app hoặc hệ thống gặp lỗi",
                                     icon: "exclamationmark.triangle.fill", safety: .safe, items: crash))
        }
        stage.finish(3, bytes: crash.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 5. Bộ nhớ đệm hệ thống (cần quyền quản trị)
        report(4, steps, "Bộ nhớ đệm hệ thống…")
        let systemCache = itemsFromChildren(
            of: URL(fileURLWithPath: "/Library/Caches"),
            cancel: cancel,
            progress: { report(4, steps, "Hệ thống: \($0)") })
        found += systemCache.reduce(0) { $0 + $1.size }
        if !systemCache.isEmpty {
            groups.append(CleanGroup(id: "sys-cache", title: "Bộ nhớ đệm hệ thống",
                                     subtitle: "Nằm trong /Library — cần mật khẩu quản trị",
                                     icon: "lock.shield.fill", safety: .safe, items: systemCache))
        }
        stage.finish(4, bytes: systemCache.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 6. Rác của công cụ lập trình
        report(5, steps, "Công cụ lập trình…")
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
        for (url, name, detail, selected) in devTargets {
            if cancel.isCancelled { break }
            report(5, steps, "Công cụ lập trình: \(name)")
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
        stage.finish(5, bytes: dev.reduce(0) { $0 + $1.size })
        if cancel.isCancelled { return groups }

        // 7. Trạng thái ứng dụng đã lưu + gói cài đặt cũ
        report(6, steps, "Mục khác…")
        var misc = itemsFromChildren(of: FileUtils.homePath("Library/Saved Application State"),
                                     selected: false, cancel: cancel)
        for f in FileUtils.children(of: URL(fileURLWithPath: "/Library/Updates")) {
            if let i = makeItem(f, detail: "Gói cập nhật đã tải", selected: false, cancel: cancel) {
                misc.append(i)
            }
        }
        found += misc.reduce(0) { $0 + $1.size }
        if !misc.isEmpty {
            groups.append(CleanGroup(id: "misc", title: "Trạng thái cửa sổ đã lưu",
                                     subtitle: "Xoá sẽ mất vị trí cửa sổ và tab đang mở của app",
                                     icon: "macwindow", safety: .review, items: misc))
        }
        stage.finish(6, bytes: misc.reduce(0) { $0 + $1.size })

        stage.done()
        return groups
    }
}
