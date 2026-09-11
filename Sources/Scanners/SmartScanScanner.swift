import Foundation

/// "Quét thông minh": chỉ gom những thứ dọn được mà không phải suy nghĩ.
///
/// Lấy toàn bộ rác hệ thống, Thùng rác, và **chỉ riêng bộ nhớ đệm** của trình duyệt —
/// cookie, lịch sử hay phiên đăng nhập không bao giờ nằm trong đây.
struct SmartScanScanner: ModuleScanner {

    func scan(cancel: CancelToken, progress: @escaping (ScanProgress) -> Void) -> [CleanGroup] {
        var all: [CleanGroup] = []
        var bytes: Int64 = 0

        func forward(_ base: Double, _ span: Double) -> (ScanProgress) -> Void {
            { p in
                progress(ScanProgress(fraction: base + p.fraction * span,
                                      message: p.message,
                                      bytesFound: bytes + p.bytesFound))
            }
        }

        let junk = SystemJunkScanner().scan(cancel: cancel, progress: forward(0, 0.55))
            .filter { $0.safety == .safe }
        all += junk
        bytes += junk.reduce(0) { $0 + $1.totalSize }
        if cancel.isCancelled { return all }

        let trash = TrashDownloadsScanner().scan(cancel: cancel, progress: forward(0.55, 0.25))
            .filter { $0.id == "trash" }
        all += trash
        bytes += trash.reduce(0) { $0 + $1.totalSize }
        if cancel.isCancelled { return all }

        // Chỉ giữ các mục bộ nhớ đệm của trình duyệt.
        let browsers = BrowserPrivacyScanner().scan(cancel: cancel, progress: forward(0.8, 0.2))
        var cacheItems: [CleanItem] = []
        for g in browsers {
            for var item in g.items where item.category == BrowserPrivacyScanner.Part.cache {
                item.name = "\(g.title) · \(item.name)"
                item.isSelected = true
                cacheItems.append(item)
            }
        }
        if !cacheItems.isEmpty {
            cacheItems.sort { $0.size > $1.size }
            bytes += cacheItems.reduce(0) { $0 + $1.size }
            all.append(CleanGroup(id: "smart-browser-cache",
                                  title: "Bộ nhớ đệm trình duyệt",
                                  subtitle: "Không đụng tới cookie, lịch sử hay phiên đăng nhập",
                                  icon: "globe", safety: .safe, items: cacheItems))
        }

        progress(ScanProgress(fraction: 1, message: "Xong", bytesFound: bytes))
        return all.filter { !$0.items.isEmpty }
    }
}
