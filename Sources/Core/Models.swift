import Foundation

// MARK: - Module

enum CleanModule: String, CaseIterable, Identifiable {
    case smartScan
    case systemJunk
    case uninstaller
    case largeOld
    case duplicates
    case trashDownloads
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan:      return "Quét thông minh"
        case .systemJunk:     return "Rác hệ thống"
        case .uninstaller:    return "Gỡ ứng dụng"
        case .largeOld:       return "Tệp lớn & cũ"
        case .duplicates:     return "Tệp trùng lặp"
        case .trashDownloads: return "Thùng rác & Tải về"
        case .privacy:        return "Riêng tư"
        }
    }

    var subtitle: String {
        switch self {
        case .smartScan:      return "Một nút, dọn mọi thứ an toàn"
        case .systemJunk:     return "Bộ nhớ đệm, nhật ký, báo cáo sự cố"
        case .uninstaller:    return "Xoá app cùng mọi tệp còn sót"
        case .largeOld:       return "Tìm những gì đang chiếm chỗ"
        case .duplicates:     return "So khớp nội dung từng byte"
        case .trashDownloads: return "Thùng rác mọi ổ đĩa, tệp tải cũ"
        case .privacy:        return "Cookie, lịch sử, bộ nhớ đệm trình duyệt"
        }
    }

    var icon: String {
        switch self {
        case .smartScan:      return "sparkles"
        case .systemJunk:     return "internaldrive.fill"
        case .uninstaller:    return "shippingbox"
        case .largeOld:       return "chart.pie"
        case .duplicates:     return "square.on.square"
        case .trashDownloads: return "trash.fill"
        case .privacy:        return "hand.raised"
        }
    }

    /// Ba việc chính mà mục này làm, hiện ở màn khởi đầu.
    var highlights: [(icon: String, title: String)] {
        switch self {
        case .smartScan:
            return [("shippingbox.fill", "Bộ nhớ đệm & nhật ký"),
                    ("trash.fill", "Thùng rác"),
                    ("globe", "Bộ nhớ đệm trình duyệt")]
        case .systemJunk:
            return [("shippingbox.fill", "Bộ nhớ đệm ứng dụng & hệ thống"),
                    ("doc.text.fill", "Nhật ký và báo cáo sự cố"),
                    ("hammer.fill", "Rác của công cụ lập trình")]
        case .trashDownloads:
            return [("trash.fill", "Thùng rác trên mọi ổ đĩa"),
                    ("opticaldiscdrive.fill", "Bộ cài đã dùng xong"),
                    ("clock.arrow.circlepath", "Tệp tải về lâu ngày")]
        case .privacy:
            return [("clock.arrow.circlepath", "Lịch sử duyệt web"),
                    ("person.badge.key.fill", "Cookie và phiên đăng nhập"),
                    ("shippingbox.fill", "Bộ nhớ đệm trình duyệt")]
        case .uninstaller:
            return [("shippingbox", "Gỡ app cùng mọi tệp còn sót"),
                    ("folder.fill", "Dữ liệu, tuỳ chọn, container"),
                    ("bolt.horizontal.fill", "Tác vụ nền và biên nhận cài đặt")]
        case .largeOld:
            return [("chart.pie.fill", "Tệp chiếm nhiều chỗ nhất"),
                    ("clock.fill", "Thứ lâu rồi không đụng tới"),
                    ("folder.fill", "Quét thư mục bất kỳ")]
        case .duplicates:
            return [("square.on.square", "So khớp từng byte"),
                    ("wand.and.stars", "Tự chọn bản cần xoá"),
                    ("checkmark.shield.fill", "Luôn giữ lại một bản")]
        }
    }

    /// Các module dùng chung màn hình kết quả dạng nhóm.
    var usesGroupedResults: Bool {
        switch self {
        case .smartScan, .systemJunk, .trashDownloads, .privacy: return true
        case .uninstaller, .largeOld, .duplicates: return false
        }
    }
}

// MARK: - Mức an toàn

enum SafetyLevel: Int, Comparable {
    case safe = 0       // Dọn thoải mái, hệ thống tự tạo lại
    case review = 1     // Nên xem qua trước khi xoá
    case sensitive = 2  // Mất là mất luôn, không tự chọn sẵn

    static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .safe:      return "An toàn"
        case .review:    return "Nên xem lại"
        case .sensitive: return "Cẩn trọng"
        }
    }
}

// MARK: - Item

struct CleanItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var name: String
    var detail: String
    var size: Int64
    var isSelected: Bool
    /// Trạng thái mà scanner đề xuất. So với `isSelected` để biết người dùng đã đổi ý ở đâu.
    let defaultSelected: Bool
    var requiresAdmin: Bool
    var isDirectory: Bool
    /// Xoá nội dung bên trong nhưng giữ lại chính thư mục (dùng cho ~/Library/Caches/<bundle>).
    var emptyContentsOnly: Bool
    /// Tên phần mà mục này thuộc về, ví dụ "Lịch sử" hay "Tự động điền".
    /// Rỗng nghĩa là nhóm không chia phần.
    var category: String
    /// Mức rủi ro của riêng mục này (nhóm có mức riêng, nhưng trong một nhóm vẫn có mục nặng nhẹ khác nhau).
    var safety: SafetyLevel

    init(url: URL,
         name: String? = nil,
         detail: String = "",
         size: Int64,
         isSelected: Bool = true,
         requiresAdmin: Bool = false,
         isDirectory: Bool = true,
         emptyContentsOnly: Bool = false,
         category: String = "",
         safety: SafetyLevel = .safe) {
        self.id = UUID()
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.detail = detail
        self.size = size
        self.isSelected = isSelected
        self.defaultSelected = isSelected
        self.requiresAdmin = requiresAdmin
        self.isDirectory = isDirectory
        self.emptyContentsOnly = emptyContentsOnly
        self.category = category
        self.safety = safety
    }

    /// Bản sao với đề xuất mặc định khác. Phải tạo mục mới chứ không sửa `isSelected`,
    /// vì `defaultSelected` là cái mốc để biết người dùng có tự tay đổi ý hay không.
    func reselected(_ value: Bool, name newName: String? = nil) -> CleanItem {
        CleanItem(url: url, name: newName ?? name, detail: detail, size: size,
                  isSelected: value, requiresAdmin: requiresAdmin, isDirectory: isDirectory,
                  emptyContentsOnly: emptyContentsOnly, category: category, safety: safety)
    }

    static func == (lhs: CleanItem, rhs: CleanItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Group

struct CleanGroup: Identifiable {
    let id: String
    var title: String
    var subtitle: String
    var icon: String
    var safety: SafetyLevel
    var items: [CleanItem]
    var isExpanded: Bool = false
    /// Bundle id của ứng dụng đang mở giữ dữ liệu này (nếu có) — dùng để mời người dùng thoát app.
    var runningBundleID: String? = nil
    /// macOS đang chặn đọc thư mục của nhóm này; danh sách vì thế chưa đầy đủ.
    var needsFullDiskAccess: Bool = false
    /// Ứng dụng mà nhóm này thuộc về — dùng biểu tượng thật của nó thay cho ký hiệu chung.
    var appBundleID: String? = nil
    /// Với nhóm gộp nhiều ứng dụng: phần nào thuộc bundle id nào.
    var categoryAppIDs: [String: String] = [:]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.isSelected).count }
    var needsAdmin: Bool { items.contains { $0.isSelected && $0.requiresAdmin } }

    /// Các phần trong nhóm, theo đúng thứ tự scanner sinh ra.
    var categories: [String] {
        var seen = Set<String>()
        var order: [String] = []
        for i in items where !i.category.isEmpty {
            if seen.insert(i.category).inserted { order.append(i.category) }
        }
        return order
    }

    func items(in category: String) -> [CleanItem] {
        items.filter { $0.category == category }
    }

    func selection(in category: String) -> Selection {
        let list = items(in: category)
        let n = list.filter(\.isSelected).count
        if n == 0 { return .none }
        return n == list.count ? .all : .partial
    }

    enum Selection { case none, partial, all }

    var selection: Selection {
        let n = selectedCount
        if n == 0 { return .none }
        return n == items.count ? .all : .partial
    }
}

// MARK: - Tiến trình quét

/// Một chặng trong lúc quét. Người dùng nhìn thấy chúng như các ô: ô đang chạy phình to,
/// ô đã xong thu lại và hiện kết quả.
struct ScanStage: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    /// Bundle id để lấy biểu tượng thật (trình duyệt), nếu có.
    var appBundleID: String? = nil

    static func == (l: ScanStage, r: ScanStage) -> Bool { l.id == r.id }
}

struct ScanProgress {
    var fraction: Double = 0
    /// Thứ đang được xử lý — tên tệp hoặc thư mục, để người dùng thấy máy đang thật sự làm việc.
    var message: String = ""
    var bytesFound: Int64 = 0
    /// Chặng đang chạy, tính theo chỉ số trong `ModuleScanner.stages`.
    var stageIndex: Int? = nil
    /// Dung lượng đã chốt của các chặng đã xong.
    var stageBytes: [Int: Int64] = [:]
}

// MARK: - Tiến trình dọn

/// Một mục vừa được xử lý xong, để danh sách tick dần trong lúc dọn.
struct CleanedEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let bytes: Int64
    let failed: Bool
    /// Ô (nhóm) mà mục này thuộc về, để danh sách chỉ hiện phần của ô đang dọn.
    let stageIndex: Int

    init(name: String, bytes: Int64, failed: Bool = false, stageIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.bytes = bytes
        self.failed = failed
        self.stageIndex = stageIndex
    }

    static func == (l: CleanedEntry, r: CleanedEntry) -> Bool { l.id == r.id }
}

// MARK: - Kết quả dọn

struct CleanOutcome {
    var removedCount: Int = 0
    var freedBytes: Int64 = 0
    var failures: [(url: URL, reason: String)] = []
    var wasCancelled: Bool = false
    var usedAdmin: Bool = false
}

// MARK: - Định dạng

enum Fmt {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func size(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 KB" }
        return byteFormatter.string(fromByteCount: bytes)
    }

    /// Tách phần số và phần đơn vị để hiển thị cỡ chữ khác nhau.
    static func sizeParts(_ bytes: Int64) -> (value: String, unit: String) {
        let s = size(bytes)
        let parts = s.split(separator: " ")
        guard parts.count == 2 else { return (s, "") }
        return (String(parts[0]), String(parts[1]))
    }

    static func date(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: d)
    }

    static func relativeAge(_ d: Date?) -> String {
        guard let d else { return "" }
        let days = Int(Date().timeIntervalSince(d) / 86_400)
        switch days {
        case ..<1:    return "hôm nay"
        case 1..<30:  return "\(days) ngày trước"
        case 30..<365: return "\(days / 30) tháng trước"
        default:      return "\(days / 365) năm trước"
        }
    }
}
