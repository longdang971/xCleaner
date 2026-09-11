import Foundation

/// Hàng rào cuối cùng trước khi bất cứ thứ gì bị xoá.
///
/// Mọi đường dẫn — dù do scanner sinh ra hay do người dùng tự chọn — đều phải đi qua
/// `validate(_:)`. Quy tắc cố tình khắt khe: thà bỏ sót một thư mục rác còn hơn chạm vào
/// thứ không được phép, nhất là khi lệnh xoá có thể chạy dưới quyền root.
enum SafetyGuard {

    enum Rejection: LocalizedError {
        case emptyPath
        case rootOrTopLevel(String)
        case protectedPrefix(String)
        case outsideHomeAndAllowlist(String)
        case traversal(String)
        case symlinkEscape(String, String)
        case notExist(String)
        case volumeRoot(String)

        var errorDescription: String? {
            switch self {
            case .emptyPath:                    return "Đường dẫn rỗng."
            case .rootOrTopLevel(let p):        return "Từ chối xoá thư mục gốc: \(p)"
            case .protectedPrefix(let p):       return "Đường dẫn nằm trong vùng được bảo vệ: \(p)"
            case .outsideHomeAndAllowlist(let p): return "Đường dẫn ngoài phạm vi cho phép: \(p)"
            case .traversal(let p):             return "Đường dẫn chứa thành phần không hợp lệ: \(p)"
            case .symlinkEscape(let p, let r):  return "Liên kết tượng trưng trỏ ra ngoài phạm vi: \(p) → \(r)"
            case .notExist(let p):              return "Không còn tồn tại: \(p)"
            case .volumeRoot(let p):            return "Từ chối xoá gốc ổ đĩa: \(p)"
            }
        }
    }

    /// Không bao giờ được đụng tới, kể cả khi người dùng tự chọn.
    private static let protectedPrefixes: [String] = [
        "/System",
        "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/libexec", "/usr/share",
        "/cores",
        "/private/var/db/dslocal",
        "/private/var/db/sudo",
        "/private/etc",
        "/Library/Keychains",
        "/Library/Security",
        "/Library/Extensions",
        "/Library/StagedExtensions",
        "/Library/Frameworks",
        "/Library/CoreAnalytics",
        "/private/var/vm",
        "/dev",
        "/Volumes/Macintosh HD - Data/System"
    ]

    /// Thư mục người dùng không được xoá nguyên cục.
    private static let protectedExactPaths: Set<String> = {
        let h = NSHomeDirectory()
        var s: Set<String> = [
            "/", "/Applications", "/Library", "/Users", "/Volumes", "/private", "/private/var",
            "/private/var/log", "/private/var/folders", "/opt", "/usr", "/tmp", "/private/tmp",
            "/Library/Caches", "/Library/Logs", "/Library/Application Support",
            "/Library/Preferences", "/Library/LaunchAgents", "/Library/LaunchDaemons",
            "/Library/Containers", "/Library/Group Containers"
        ]
        for sub in ["", "/Library", "/Library/Caches", "/Library/Logs", "/Library/Preferences",
                    "/Library/Application Support", "/Library/Containers", "/Library/Group Containers",
                    "/Library/Safari", "/Library/Mail", "/Library/Messages", "/Library/Keychains",
                    "/Desktop", "/Documents", "/Downloads", "/Movies", "/Music", "/Pictures",
                    "/Library/Mobile Documents", "/Library/CloudStorage",
                    "/Library/Developer", "/Library/Developer/Xcode", "/.Trash"] {
            s.insert(h + sub)
        }
        return s
    }()

    /// Gốc được phép thao tác. Ngoài home của người dùng, chỉ vài nhánh hệ thống chứa rác thật sự.
    private static let allowedRoots: [String] = {
        var r = [
            NSHomeDirectory(),
            "/Library/Caches",
            "/Library/Logs",
            "/Library/Application Support/CrashReporter",
            "/Library/Updates",
            "/private/var/log",
            "/private/var/folders",
            "/private/var/db/receipts",
            "/Applications",
            "/Volumes"
        ]
        r.append(contentsOf: ["/Library/LaunchAgents", "/Library/LaunchDaemons",
                              "/Library/Application Support", "/Library/Preferences",
                              "/Library/PrivilegedHelperTools"])
        return r
    }()

    /// Chuẩn hoá đường dẫn: bỏ `//`, `.`, `..` và ký tự `/` thừa ở cuối.
    static func standardized(_ url: URL) -> URL {
        URL(fileURLWithPath: (url.path as NSString).standardizingPath)
    }

    static func validate(_ url: URL, requireExists: Bool = true) -> Rejection? {
        let std = standardized(url)
        let path = std.path

        guard !path.isEmpty, path != "" else { return .emptyPath }
        guard path.hasPrefix("/") else { return .traversal(path) }
        guard !path.contains("/../"), !path.hasSuffix("/..") else { return .traversal(path) }
        guard path != "/" else { return .rootOrTopLevel(path) }

        // Gốc ổ đĩa gắn ngoài: /Volumes/Tên — chỉ cho phép từ cấp con trở xuống.
        let comps = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if comps.first == "Volumes" && comps.count <= 2 { return .volumeRoot(path) }
        if comps.count == 1 { return .rootOrTopLevel(path) }

        if protectedExactPaths.contains(path) { return .rootOrTopLevel(path) }

        for p in protectedPrefixes where path == p || path.hasPrefix(p + "/") {
            return .protectedPrefix(path)
        }

        // Bundle của chính xCleaner.
        let selfPath = Bundle.main.bundlePath
        if !selfPath.isEmpty, path == selfPath || path.hasPrefix(selfPath + "/") {
            return .protectedPrefix(path)
        }

        var inAllowed = false
        for root in allowedRoots where path.hasPrefix(root + "/") || path == root {
            inAllowed = true
            break
        }
        guard inAllowed else { return .outsideHomeAndAllowlist(path) }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        // fileExists đi theo symlink; kiểm tra thêm bằng lstat cho liên kết hỏng.
        let isSymlink = (try? fm.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeSymbolicLink
        if requireExists && !exists && !isSymlink { return .notExist(path) }

        // Symlink thì chỉ xoá chính liên kết, nhưng nếu nó trỏ vào vùng cấm thì bỏ hẳn cho chắc.
        if isSymlink {
            let resolved = (path as NSString).resolvingSymlinksInPath
            for p in protectedPrefixes where resolved == p || resolved.hasPrefix(p + "/") {
                return .symlinkEscape(path, resolved)
            }
        }
        return nil
    }

    static func isValid(_ url: URL, requireExists: Bool = true) -> Bool {
        validate(url, requireExists: requireExists) == nil
    }

    /// Lọc danh sách, trả về (hợp lệ, bị từ chối kèm lý do).
    static func partition(_ urls: [URL]) -> (accepted: [URL], rejected: [(URL, Rejection)]) {
        var ok: [URL] = []
        var bad: [(URL, Rejection)] = []
        for u in urls {
            if let r = validate(u) { bad.append((u, r)) } else { ok.append(standardized(u)) }
        }
        return (ok, bad)
    }
}
