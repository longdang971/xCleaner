import Foundation
import CoreServices

/// Một ứng dụng vừa rơi vào Thùng rác.
struct TrashedApp: Equatable {
    let url: URL
    let bundleID: String
    let name: String
    let version: String
}

/// Nghe ngóng `~/.Trash` và báo khi có `.app` mới xuất hiện.
///
/// Cần quyền Toàn quyền truy cập đĩa mới đọc được thư mục này. Chưa cấp thì luồng sự kiện vẫn
/// chạy nhưng danh sách con luôn rỗng — không phải lỗi, và app đã có chấm than đỏ nhắc quyền ở
/// sidebar rồi, không dựng thêm hộp thoại nào nữa.
final class TrashWatcher {

    private let directory: URL
    private let onNew: ([TrashedApp]) -> Void
    private var stream: FSEventStreamRef?
    /// Đường dẫn đã nhìn thấy ở lần chụp trước. Mỗi lần sự kiện bắn thì so với danh sách mới.
    private var seen: Set<String> = []
    private let queue = DispatchQueue(label: "xCleaner.trashwatcher")

    init(directory: URL = FileUtils.homePath(".Trash"),
         onNew: @escaping ([TrashedApp]) -> Void) {
        self.directory = directory
        self.onNew = onNew
    }

    func start() {
        guard stream == nil else { return }
        // Ảnh chụp đầu tiên KHÔNG được báo lên: những gì đang nằm sẵn trong Thùng rác là chuyện
        // cũ. Báo hết thì người dùng vừa đăng nhập đã ăn một loạt cửa sổ.
        //
        // Chụp trên chính hàng đợi của luồng sự kiện: `rescan()` chạy ở đó, nên nếu chụp ở luồng
        // gọi `start()` thì hai luồng cùng đụng vào `seen`.
        queue.sync { seen = Set(Self.entries(in: directory).map(\.path)) }

        var ctx = FSEventStreamContext(version: 0,
                                       info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<TrashWatcher>.fromOpaque(info).takeUnretainedValue().rescan()
        }
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &ctx,
            [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,                            // gộp sự kiện nửa giây: kéo một app vào Thùng rác
                                            // sinh ra cả chùm sự kiện chứ không phải một cái.
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)) else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }

    private func rescan() {
        let fresh = Self.trashedApps(in: directory, ignoring: seen)
        seen = Set(Self.entries(in: directory).map(\.path))
        guard !fresh.isEmpty else { return }
        DispatchQueue.main.async { [onNew] in onNew(fresh) }
    }

    // MARK: - Phần thuần, kiểm tra được

    /// Chỉ mục **cấp 1** của thư mục. `.app` nằm trong một thư mục cũng vừa bị xoá nghĩa là người
    /// dùng đang xoá cả thư mục ấy, không phải gỡ riêng app đó.
    static func entries(in dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants])) ?? []
    }

    static func trashedApps(in dir: URL, ignoring seen: Set<String>) -> [TrashedApp] {
        entries(in: dir)
            .filter { $0.pathExtension == "app" && !seen.contains($0.path) }
            .compactMap(readBundle)
    }

    /// Không đọc được bundle id thì không quét được tàn dư — bỏ qua chứ đừng đoán theo tên.
    static func readBundle(_ url: URL) -> TrashedApp? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let d = NSDictionary(contentsOf: plist) as? [String: Any],
              let id = d["CFBundleIdentifier"] as? String, !id.isEmpty else { return nil }
        let name = (d["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (d["CFBundleShortVersionString"] as? String)
            ?? (d["CFBundleVersion"] as? String) ?? ""
        return TrashedApp(url: url, bundleID: id, name: name, version: version)
    }
}
