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
        case .systemJunk:     return "trash.slash"
        case .uninstaller:    return "shippingbox"
        case .largeOld:       return "chart.pie"
        case .duplicates:     return "square.on.square"
        case .trashDownloads: return "arrow.down.circle"
        case .privacy:        return "hand.raised"
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
    var requiresAdmin: Bool
    var isDirectory: Bool
    /// Xoá nội dung bên trong nhưng giữ lại chính thư mục (dùng cho ~/Library/Caches/<bundle>).
    var emptyContentsOnly: Bool

    init(url: URL,
         name: String? = nil,
         detail: String = "",
         size: Int64,
         isSelected: Bool = true,
         requiresAdmin: Bool = false,
         isDirectory: Bool = true,
         emptyContentsOnly: Bool = false) {
        self.id = UUID()
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.detail = detail
        self.size = size
        self.isSelected = isSelected
        self.requiresAdmin = requiresAdmin
        self.isDirectory = isDirectory
        self.emptyContentsOnly = emptyContentsOnly
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

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.isSelected).count }
    var needsAdmin: Bool { items.contains { $0.isSelected && $0.requiresAdmin } }

    enum Selection { case none, partial, all }

    var selection: Selection {
        let n = selectedCount
        if n == 0 { return .none }
        return n == items.count ? .all : .partial
    }
}

// MARK: - Tiến trình quét

struct ScanProgress {
    var fraction: Double = 0
    var message: String = ""
    var bytesFound: Int64 = 0
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
