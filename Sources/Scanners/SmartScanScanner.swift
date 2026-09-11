import Foundation

/// "Quét thông minh": nhìn khắp nơi như các mục chuyên biệt, nhưng **chỉ chọn sẵn**
/// những gì dọn được mà không phải suy nghĩ.
///
/// Trình duyệt được quét sâu đúng bằng mục Riêng tư — đủ cả lịch sử, cookie, tự động điền,
/// thẻ và phiên — nhưng mặc định chỉ tick phần bộ nhớ đệm. Bấm "Xem" là thấy hết và tự
/// tick thêm nếu muốn; không bấm gì thì nút "Dọn" vẫn tuyệt đối an toàn.
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

        let junk = SystemJunkScanner().scan(cancel: cancel, progress: forward(0, 0.5))
            .filter { $0.safety == .safe }
        all += junk
        bytes += junk.reduce(0) { $0 + $1.totalSize }
        if cancel.isCancelled { return all }

        let trash = TrashDownloadsScanner().scan(cancel: cancel, progress: forward(0.5, 0.2))
            .filter { $0.id == "trash" }
        all += trash
        bytes += trash.reduce(0) { $0 + $1.totalSize }
        if cancel.isCancelled { return all }

        // Trình duyệt: giữ nguyên chiều sâu của mục Riêng tư, chỉ đổi phần được tick sẵn.
        let browsers = BrowserPrivacyScanner().scan(cancel: cancel, progress: forward(0.7, 0.3))
        for var g in browsers {
            g.items = g.items.map { item in
                let safeByDefault = item.category == BrowserPrivacyScanner.Part.cache
                return item.isSelected == safeByDefault ? item : item.reselected(safeByDefault)
            }
            let cacheSize = g.items
                .filter { $0.category == BrowserPrivacyScanner.Part.cache }
                .reduce(0) { $0 + $1.size }
            g.subtitle = g.needsFullDiskAccess
                ? "Danh sách chưa đầy đủ — macOS đang chặn đọc thư mục này"
                : "Tick sẵn \(Fmt.size(cacheSize)) bộ nhớ đệm · bấm Xem để chọn thêm"
            g.safety = .safe   // phần được tick sẵn là an toàn; phần còn lại do người dùng quyết
            bytes += g.totalSize
            all.append(g)
        }

        progress(ScanProgress(fraction: 1, message: "Xong", bytesFound: bytes))
        return all.filter { !$0.items.isEmpty }
    }
}
