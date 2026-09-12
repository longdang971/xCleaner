import Foundation
import AppKit

/// Cờ huỷ dùng chung cho mọi scanner. Đọc/ghi qua khoá nên an toàn giữa các luồng.
final class CancelToken {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock(); flag = true; lock.unlock()
    }

    func reset() {
        lock.lock(); flag = false; lock.unlock()
    }
}

protocol ModuleScanner {
    /// Các chặng mà màn hình quét sẽ vẽ thành ô. Rỗng nghĩa là chỉ hiện vòng tiến trình.
    var stages: [ScanStage] { get }

    /// Chạy trên luồng nền. Trả về các nhóm đã sẵn sàng hiển thị.
    func scan(cancel: CancelToken, progress: @escaping (ScanProgress) -> Void) -> [CleanGroup]
}

extension ModuleScanner {
    var stages: [ScanStage] { [] }
}

/// Giữ trạng thái các chặng giúp scanner, để mỗi lần báo tiến trình không phải tự dựng lại.
final class StageReporter {
    private let total: Int
    /// Mỗi chặng chiếm bao nhiêu phần của vòng tròn. Chia đều thì chặng quét bộ nhớ đệm —
    /// vốn lâu gấp mấy lần mọi chặng khác — cũng chỉ được đúng một suất, và người dùng thấy
    /// vòng tròn đứng im rất lâu rồi nhảy một phát. Trọng số cho mỗi chặng một suất đúng
    /// với thời gian nó thường ngốn.
    private let weights: [Double]
    /// Tổng dồn của `weights`: `starts[i]` là vạch xuất phát của chặng i.
    private let starts: [Double]
    private let emit: (ScanProgress) -> Void
    private var bytes: [Int: Int64] = [:]
    private var current: Int = 0
    private var found: Int64 = 0
    /// Chặng hiện tại đã đi được bao nhiêu phần của chính nó, nếu bộ quét biết mà nói.
    private var inner: Double = 0
    /// Phần trăm đã báo cao nhất. Vòng tròn tiến trình chạy lùi trông như app đếm nhầm,
    /// nên dù chặng có nhảy lung tung thì con số vẫn chỉ được đi tới.
    private var highWater: Double = 0

    convenience init(total: Int, emit: @escaping (ScanProgress) -> Void) {
        self.init(weights: Array(repeating: 1, count: max(1, total)), emit: emit)
    }

    init(weights: [Double], emit: @escaping (ScanProgress) -> Void) {
        let w = weights.isEmpty ? [1] : weights.map { max(0.0001, $0) }
        let sum = w.reduce(0, +)
        self.weights = w.map { $0 / sum }
        var acc: [Double] = []
        var running: Double = 0
        for v in self.weights { acc.append(running); running += v }
        self.starts = acc
        self.total = w.count
        self.emit = emit
    }

    private var stageStartedAt: CFAbsoluteTime = 0
    /// Thời gian tối thiểu một chặng hiện trên màn hình. Máy nhanh quét xong trong chớp mắt,
    /// không giữ lại một nhịp thì người dùng chỉ thấy màn hình nhấp nháy rồi xong.
    private let minimumStageDuration: CFAbsoluteTime = 0.5

    /// Bắt đầu một chặng.
    func begin(_ index: Int) {
        current = index
        inner = 0
        stageStartedAt = CFAbsoluteTimeGetCurrent()
        send(message: "")
    }

    /// Đang xử lý thứ gì đó trong chặng hiện tại.
    ///
    /// `within` là phần đã xong của riêng chặng này (0…1) nếu bộ quét đếm được — nhờ nó
    /// phần trăm bò đều trong suốt chặng thay vì đứng im rồi nhảy một phát khi chặng xong.
    func working(_ what: String, within: Double? = nil) {
        if let within { inner = max(inner, min(1, max(0, within))) }
        send(message: what)
    }

    /// Vừa tìm được một mục đáng kể trong chặng hiện tại.
    func found(_ name: String, _ size: Int64) {
        guard size > 0 else { return }
        emit(ScanProgress(fraction: fraction(at: current),
                          message: name, bytesFound: found + size,
                          stageIndex: current, stageBytes: bytes,
                          foundName: name, foundBytes: size,
                          ceiling: ceiling(at: current)))
    }

    /// Chặng đã xong với ngần này dung lượng.
    func finish(_ index: Int, bytes size: Int64) {
        let elapsed = CFAbsoluteTimeGetCurrent() - stageStartedAt
        if stageStartedAt > 0 && elapsed < minimumStageDuration {
            Thread.sleep(forTimeInterval: minimumStageDuration - elapsed)
        }
        bytes[index] = size
        found += size
        inner = 0
        // Xong chặng cuối thì `current` được phép bằng `total`: không còn ô nào sáng lên
        // và phần trăm lên gần trọn vòng. Kẹp lại ở `total - 1` thì vòng tròn đứng im ở
        // mốc của chặng cuối suốt cả quãng dài nhất rồi mới nhảy phắt lên 100%.
        current = min(index + 1, total)
        send(message: "")
    }

    /// Chuyển sang chặng khác nếu đang ở chặng khác; gọi được liên tục mà không reset đồng hồ.
    func jump(to index: Int) {
        guard current != index else { return }
        begin(index)
    }

    /// Ghi nhận dung lượng của một chặng đã xong mà không chờ thêm.
    func mark(_ index: Int, _ size: Int64) {
        guard bytes[index] == nil else { return }
        bytes[index] = size
        found += size
        send(message: "")
    }

    /// Báo xong toàn bộ.
    func done() {
        emit(ScanProgress(fraction: 1, message: "", bytesFound: found,
                          stageIndex: nil, stageBytes: bytes))
    }

    private func send(message: String) {
        emit(ScanProgress(fraction: fraction(at: current), message: message,
                          bytesFound: found, stageIndex: current, stageBytes: bytes,
                          ceiling: ceiling(at: current)))
    }

    /// Chặng vừa bắt đầu đã được tính một chút, phần còn lại chạy theo `inner`.
    private func fraction(at index: Int) -> Double {
        guard index < weights.count else {
            highWater = max(highWater, 0.99)
            return highWater
        }
        let raw = min(0.99, starts[index] + weights[index] * (0.12 + 0.8 * inner))
        highWater = max(highWater, raw)
        return highWater
    }

    /// Bò được tới gần hết phần của chặng đang chạy, chừa lại một mẩu để lúc chặng sau bắt
    /// đầu con số vẫn còn chỗ mà nhích lên.
    private func ceiling(at index: Int) -> Double {
        guard index < weights.count else { return 0.99 }
        return min(0.985, starts[index] + weights[index] * 0.94)
    }
}

extension ModuleScanner {
    /// Tạo item từ một đường dẫn, tự đo dung lượng và tự nhận biết có cần quyền root không.
    func makeItem(_ url: URL,
                  name: String? = nil,
                  detail: String = "",
                  selected: Bool = true,
                  emptyContentsOnly: Bool = false,
                  cancel: CancelToken,
                  category: String = "",
                  safety: SafetyLevel = .safe) -> CleanItem? {
        guard FileUtils.exists(url) else { return nil }
        guard SafetyGuard.isValid(url) else { return nil }
        let size = FileUtils.size(of: url, isCancelled: { cancel.isCancelled })
        guard size > 0 else { return nil }
        return CleanItem(url: url,
                         name: name,
                         detail: detail.isEmpty ? FileUtils.prettyPath(url) : detail,
                         size: size,
                         isSelected: selected,
                         requiresAdmin: PrivilegedRunner.needsAdmin(for: url),
                         isDirectory: FileUtils.isDirectory(url),
                         emptyContentsOnly: emptyContentsOnly,
                         category: category,
                         safety: safety)
    }

    /// Duyệt từng thư mục con của `parent` và biến mỗi con thành một item.
    func itemsFromChildren(of parent: URL,
                           selected: Bool = true,
                           skip: Set<String> = [],
                           cancel: CancelToken,
                           progress: ((String, Double) -> Void)? = nil,
                           found: ((String, Int64) -> Void)? = nil) -> [CleanItem] {
        guard FileUtils.isDirectory(parent) else { return [] }
        var result: [CleanItem] = []
        // Đếm trước tổng số con để còn báo được "đã đi tới đâu" chứ không chỉ "đang ở tệp nào".
        let children = FileUtils.children(of: parent)
        for (i, child) in children.enumerated() {
            if cancel.isCancelled { break }
            let n = child.lastPathComponent
            if n.hasPrefix(".") { continue }
            if skip.contains(n) { continue }
            progress?(n, Double(i) / Double(max(1, children.count)))
            if let item = makeItem(child, name: prettyName(n), selected: selected, cancel: cancel) {
                found?(item.name, item.size)
                result.append(item)
            }
        }
        return result.sorted { $0.size > $1.size }
    }

    /// `com.apple.Safari` → `Safari` khi tra được tên app, ngược lại giữ nguyên.
    func prettyName(_ raw: String) -> String {
        if raw.contains("."), raw.split(separator: ".").count >= 3,
           let app = AppCatalog.shared.name(forBundleID: raw) {
            return app
        }
        return raw
    }
}

/// Bảng tra bundle id → tên hiển thị, dựng một lần rồi dùng lại.
final class AppCatalog {
    static let shared = AppCatalog()

    private var map: [String: String] = [:]
    private var built = false
    private let lock = NSLock()

    struct AppEntry {
        let url: URL
        let name: String
        let bundleID: String
        let version: String
        let isSystem: Bool
    }

    private(set) var apps: [AppEntry] = []

    func build() {
        lock.lock(); defer { lock.unlock() }
        guard !built else { return }
        built = true

        var dirs: [URL] = [URL(fileURLWithPath: "/Applications"),
                           FileUtils.homePath("Applications")]
        // Ứng dụng nằm trong thư mục con, ví dụ /Applications/Utilities
        for d in dirs {
            for sub in FileUtils.children(of: d) where FileUtils.isDirectory(sub)
                && sub.pathExtension != "app" {
                dirs.append(sub)
            }
        }

        var seen = Set<String>()
        for dir in dirs {
            for url in FileUtils.children(of: dir) where url.pathExtension == "app" {
                guard let b = Bundle(url: url), let bid = b.bundleIdentifier else { continue }
                guard !seen.contains(url.path) else { continue }
                seen.insert(url.path)
                let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
                map[bid] = name
                apps.append(AppEntry(url: url, name: name, bundleID: bid, version: version,
                                     isSystem: url.path.hasPrefix("/System")))
            }
        }
        apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func name(forBundleID id: String) -> String? {
        if !built { build() }
        lock.lock()
        if let cached = map[id] { lock.unlock(); return cached }
        lock.unlock()

        // Không có trong /Applications thì hỏi LaunchServices — bắt được cả app hệ thống
        // và các tiến trình nền có bundle riêng.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
              let bundle = Bundle(url: url) else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        lock.lock(); map[id] = name; lock.unlock()
        return name
    }

    func allApps() -> [AppEntry] {
        if !built { build() }
        lock.lock(); defer { lock.unlock() }
        return apps
    }

    func refresh() {
        lock.lock()
        built = false
        map.removeAll()
        apps.removeAll()
        lock.unlock()
        build()
    }
}
