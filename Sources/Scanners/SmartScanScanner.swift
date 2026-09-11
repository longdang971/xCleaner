import Foundation

/// "Quét thông minh": nhìn khắp nơi như các mục chuyên biệt, nhưng **chỉ chọn sẵn**
/// những gì dọn được mà không phải suy nghĩ.
///
/// Kết quả được gom lại cho gọn — mọi trình duyệt vào chung một thẻ, nhật ký người dùng và
/// nhật ký hệ thống vào chung một thẻ — vì ở đây người dùng muốn thấy bức tranh lớn,
/// còn chi tiết thì bấm "Xem" là có.
struct SmartScanScanner: ModuleScanner {

    var stages: [ScanStage] {
        [.init(id: "junk", title: "Rác hệ thống", icon: "trash.slash.fill"),
         .init(id: "trash", title: "Thùng rác", icon: "trash.fill"),
         .init(id: "web", title: "Trình duyệt", icon: "globe")]
    }

    func scan(cancel: CancelToken, progress: @escaping (ScanProgress) -> Void) -> [CleanGroup] {
        var bytes: Int64 = 0
        let stage = StageReporter(total: 3, emit: progress)

        stage.begin(0)
        let junk = SystemJunkScanner()
            .scan(cancel: cancel) { stage.working($0.message) }
            .filter { $0.safety == .safe }
        let junkBytes = junk.reduce(0) { $0 + $1.totalSize }
        bytes += junkBytes
        stage.finish(0, bytes: junkBytes)
        if cancel.isCancelled { return junk }

        stage.begin(1)
        let trash = TrashDownloadsScanner()
            .scan(cancel: cancel) { stage.working($0.message) }
            .filter { $0.id == "trash" }
        let trashBytes = trash.reduce(0) { $0 + $1.totalSize }
        bytes += trashBytes
        stage.finish(1, bytes: trashBytes)
        if cancel.isCancelled { return junk + trash }

        stage.begin(2)
        let browsers = BrowserPrivacyScanner().scan(cancel: cancel) { stage.working($0.message) }

        var result: [CleanGroup] = []
        result += junk.filter { $0.id != "user-logs" && $0.id != "sys-logs" }
        if let logs = mergedLogs(from: junk) { result.append(logs) }
        result += trash
        if let web = mergedBrowsers(from: browsers) {
            bytes += web.totalSize
            stage.finish(2, bytes: web.totalSize)
            result.append(web)
        } else {
            stage.finish(2, bytes: 0)
        }

        // Thẻ nào nhiều dung lượng nhất lên trước, để hàng đầu luôn là thứ đáng nhìn nhất.
        result.sort { $0.totalSize > $1.totalSize }

        stage.done()
        return result.filter { !$0.items.isEmpty }
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
