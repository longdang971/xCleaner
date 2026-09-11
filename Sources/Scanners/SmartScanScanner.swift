import Foundation

/// "Quét thông minh": nhìn khắp nơi như các mục chuyên biệt, nhưng **chỉ chọn sẵn**
/// những gì dọn được mà không phải suy nghĩ.
///
/// Kết quả được gom lại cho gọn — mọi trình duyệt vào chung một thẻ, nhật ký người dùng và
/// nhật ký hệ thống vào chung một thẻ — vì ở đây người dùng muốn thấy bức tranh lớn,
/// còn chi tiết thì bấm "Xem" là có.
struct SmartScanScanner: ModuleScanner {

    /// Một chặng của lần quét. Chặng nào chắc chắn không có gì thì không hiện ô,
    /// nếu không người dùng sẽ thấy sáu ô lúc quét rồi chỉ còn năm thẻ lúc xong.
    private enum Kind: CaseIterable {
        case cache, logs, crash, trash, browsers

        var stage: ScanStage {
            switch self {
            case .cache:    return .init(id: "cache", title: "Bộ nhớ đệm", icon: "shippingbox.fill")
            case .logs:     return .init(id: "logs", title: "Nhật ký", icon: "doc.text.fill")
            case .crash:    return .init(id: "crash", title: "Báo cáo sự cố",
                                         icon: "exclamationmark.triangle.fill")
            case .trash:    return .init(id: "trash", title: "Thùng rác", icon: "trash.fill")
            case .browsers: return .init(id: "browsers", title: "Trình duyệt", icon: "globe")
            }
        }
    }

    /// Chỉ đếm xem thư mục có gì không — không đo dung lượng, nên rất nhanh.
    private static func hasContent(_ url: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return items.contains { !$0.hasPrefix(".") }
    }

    /// Bị macOS chặn đọc cũng tính là "có thể có gì đó" — phải hiện ô để còn mời cấp quyền.
    private static func trashHasContent() -> Bool {
        let state = FileUtils.directoryState(FileUtils.homePath(".Trash"))
        if state == .hasItems || state == .blocked { return true }
        let uid = getuid()
        for vol in FileUtils.mountedVolumes() where vol.path != "/" {
            if hasContent(vol.appendingPathComponent(".Trashes/\(uid)")) { return true }
        }
        return false
    }

    private static func availableKinds() -> [Kind] {
        var kinds: [Kind] = []
        if hasContent(FileUtils.homePath("Library/Caches"))
            || hasContent(URL(fileURLWithPath: "/Library/Caches")) { kinds.append(.cache) }
        if hasContent(FileUtils.homePath("Library/Logs"))
            || hasContent(URL(fileURLWithPath: "/Library/Logs")) { kinds.append(.logs) }
        if hasContent(FileUtils.homePath("Library/Logs/DiagnosticReports"))
            || hasContent(URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")) {
            kinds.append(.crash)
        }
        if trashHasContent() { kinds.append(.trash) }
        if !BrowserPrivacyScanner.installedBrowsers().isEmpty { kinds.append(.browsers) }
        return kinds
    }

    var stages: [ScanStage] { Self.availableKinds().map(\.stage) }

    /// Chặng nội bộ của bộ quét rác hệ thống ứng với loại nào ở đây.
    /// Hai loại nhật ký gộp về một ô, phần công cụ lập trình bị lọc nên không có ô riêng.
    private static let junkKindMap: [Int: Kind] = [0: .cache, 1: .cache, 2: .logs,
                                                   3: .logs, 4: .crash]

    func scan(cancel: CancelToken, progress: @escaping (ScanProgress) -> Void) -> [CleanGroup] {
        var bytes: Int64 = 0
        let kinds = Self.availableKinds()
        let stage = StageReporter(total: kinds.count, emit: progress)
        func index(_ k: Kind) -> Int? { kinds.firstIndex(of: k) }

        if let i = index(.cache) ?? index(.logs) { stage.begin(i) }
        let junk = SystemJunkScanner()
            .scan(cancel: cancel) { p in
                if let i = p.stageIndex, let kind = Self.junkKindMap[i],
                   let mapped = index(kind) { stage.jump(to: mapped) }
                let sb = p.stageBytes
                if let i = index(.cache), let a = sb[0], let b = sb[1] { stage.mark(i, a + b) }
                if let i = index(.logs), let a = sb[2], let b = sb[3] { stage.mark(i, a + b) }
                if let i = index(.crash), let v = sb[4] { stage.mark(i, v) }
                stage.working(p.message)
            }
            .filter { $0.safety == .safe }
        bytes += junk.reduce(0) { $0 + $1.totalSize }
        if cancel.isCancelled { return junk }

        var trash: [CleanGroup] = []
        if let ti = index(.trash) {
            stage.begin(ti)
            trash = TrashDownloadsScanner()
                .scan(cancel: cancel) { stage.working($0.message) }
                .filter { $0.id == "trash" }
            let trashBytes = trash.reduce(0) { $0 + $1.totalSize }
            bytes += trashBytes
            stage.finish(ti, bytes: trashBytes)
        }
        if cancel.isCancelled { return junk + trash }

        if let bi = index(.browsers) { stage.begin(bi) }
        let browsers = BrowserPrivacyScanner().scan(cancel: cancel) { stage.working($0.message) }

        var result: [CleanGroup] = []
        result += junk.filter {
            !["user-logs", "sys-logs", "user-cache", "sys-cache"].contains($0.id)
        }
        if let caches = mergedCaches(from: junk) { result.append(caches) }
        if let logs = mergedLogs(from: junk) { result.append(logs) }
        result += trash
        if let web = mergedBrowsers(from: browsers) {
            bytes += web.totalSize
            if let bi = index(.browsers) { stage.finish(bi, bytes: web.totalSize) }
            result.append(web)
        } else if let bi = index(.browsers) {
            stage.finish(bi, bytes: 0)
        }

        // Thẻ nào nhiều dung lượng nhất lên trước, để hàng đầu luôn là thứ đáng nhìn nhất.
        result.sort { $0.totalSize > $1.totalSize }

        stage.done()
        // Nhóm rỗng thì bỏ, trừ khi nó rỗng chỉ vì macOS chặn đọc — cái đó phải cho người dùng thấy.
        return result.filter { !$0.items.isEmpty || $0.needsFullDiskAccess }
    }

    // MARK: - Gộp bộ nhớ đệm

    private func mergedCaches(from groups: [CleanGroup]) -> CleanGroup? {
        let user = groups.first { $0.id == "user-cache" }
        let system = groups.first { $0.id == "sys-cache" }
        guard user != nil || system != nil else { return nil }

        var items: [CleanItem] = []
        items += (user?.items ?? []).map { $0.inCategory("Bộ nhớ đệm ứng dụng") }
        items += (system?.items ?? []).map { $0.inCategory("Bộ nhớ đệm hệ thống") }
        guard !items.isEmpty else { return nil }

        let needsAdmin = items.contains(where: \.requiresAdmin)
        return CleanGroup(id: "cache",
                          title: "Bộ nhớ đệm",
                          subtitle: needsAdmin
                            ? "Tệp tạm của ứng dụng và của macOS — phần hệ thống cần mật khẩu"
                            : "Tệp tạm do ứng dụng và macOS tạo ra, sẽ được dựng lại khi cần",
                          icon: "shippingbox.fill",
                          safety: .safe,
                          items: items)
    }

    // MARK: - Gộp nhật ký

    private func mergedLogs(from groups: [CleanGroup]) -> CleanGroup? {
        let user = groups.first { $0.id == "user-logs" }
        let system = groups.first { $0.id == "sys-logs" }
        guard user != nil || system != nil else { return nil }

        var items: [CleanItem] = []
        items += (user?.items ?? []).map { $0.inCategory("Nhật ký người dùng") }
        items += (system?.items ?? []).map { $0.inCategory("Nhật ký hệ thống") }
        guard !items.isEmpty else { return nil }

        let needsAdmin = items.contains(where: \.requiresAdmin)
        return CleanGroup(id: "logs",
                          title: "Nhật ký",
                          subtitle: "Log của ứng dụng và của macOS",
                          icon: "doc.text.fill",
                          safety: .safe,
                          items: items)
    }

    // MARK: - Gộp trình duyệt

    private func mergedBrowsers(from groups: [CleanGroup]) -> CleanGroup? {
        guard !groups.isEmpty else { return nil }

        var items: [CleanItem] = []
        var appIDs: [String: String] = [:]
        var running: [String] = []
        var blocked = false

        for g in groups {
            // Mỗi trình duyệt thành một phần riêng; tên mục vốn đã nói rõ nó là dữ liệu gì.
            for item in g.items {
                let safeByDefault = item.category == BrowserPrivacyScanner.Part.cache
                let wanted = item.isSelected == safeByDefault
                    ? item : item.reselected(safeByDefault)
                items.append(wanted.inCategory(g.title))
            }
            if let bid = g.appBundleID { appIDs[g.title] = bid }
            if g.runningBundleID != nil { running.append(g.title) }
            if g.needsFullDiskAccess { blocked = true }
        }
        guard !items.isEmpty else { return nil }

        let cacheSize = items
            .filter { $0.isSelected }
            .reduce(0) { $0 + $1.size }

        // Phụ đề phải ngắn: thẻ chỉ có hai dòng, còn cảnh báo đã có nhãn và nút riêng lo.
        var subtitle = groups.count == 1 ? groups[0].title : "\(groups.count) trình duyệt"
        if !running.isEmpty { subtitle += " · \(running.count) đang mở" }
        _ = cacheSize

        return CleanGroup(id: "browsers",
                          title: "Trình duyệt",
                          subtitle: subtitle,
                          icon: "globe",
                          safety: .safe,
                          items: items,
                          needsFullDiskAccess: blocked,
                          categoryAppIDs: appIDs)
    }
}

private extension CleanItem {
    /// Bản sao thuộc về một phần khác. Giữ nguyên `defaultSelected` để bộ nhớ lựa chọn
    /// vẫn so đúng với đề xuất ban đầu.
    func inCategory(_ newCategory: String) -> CleanItem {
        var copy = self
        copy.category = newCategory
        return copy
    }
}
