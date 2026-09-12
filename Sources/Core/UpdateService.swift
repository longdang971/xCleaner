import Foundation
import AppKit

// MARK: - Phiên bản

/// So sánh phiên bản kiểu `1.2.10` — so từng số một, không so chuỗi
/// (so chuỗi thì "1.2.10" hoá ra nhỏ hơn "1.2.9").
struct SemanticVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        parts = trimmed.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (l: SemanticVersion, r: SemanticVersion) -> Bool {
        for i in 0..<max(l.parts.count, r.parts.count) {
            let a = i < l.parts.count ? l.parts[i] : 0
            let b = i < r.parts.count ? r.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    static func == (l: SemanticVersion, r: SemanticVersion) -> Bool {
        !(l < r) && !(r < l)
    }

    static var current: SemanticVersion {
        SemanticVersion(
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0")
    }
}

// MARK: - Bản phát hành

struct ReleaseInfo {
    let version: SemanticVersion
    let tag: String
    let title: String
    let notes: String
    let archiveURL: URL
    let archiveName: String
    let sizeBytes: Int64
    let publishedAt: Date?

    var isNewerThanCurrent: Bool { SemanticVersion.current < version }
}

// MARK: - Dịch vụ cập nhật

/// Kiểm tra và cài bản mới lấy thẳng từ trang Releases của kho mã.
///
/// Không có máy chủ riêng, không có chữ ký số: kho mã là công khai nên chỉ cần gọi API của
/// GitHub. Bù lại, trước khi thay app thì gói tải về phải tự chứng minh nó đúng là xCleaner
/// (kiểm `CFBundleIdentifier` bên trong), nếu không thì dừng.
enum UpdateService {

    static let repository = "longdang971/xCleaner"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    enum Failure: LocalizedError {
        case network(String)
        case noRelease
        case noArchive(String)
        case badArchive(String)
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .network(let m):     return "Không kết nối được tới GitHub: \(m)"
            case .noRelease:          return "Kho mã chưa có bản phát hành nào."
            case .noArchive(let tag): return "Bản \(tag) không kèm tệp .zip nào để tải."
            case .badArchive(let m):  return "Gói tải về không dùng được: \(m)"
            case .installFailed(let m): return "Không thay được ứng dụng: \(m)"
            }
        }
    }

    // MARK: Kiểm tra

    /// Hỏi GitHub bản mới nhất. `/releases/latest` cố tình bỏ qua bản nháp và bản thử nghiệm,
    /// nên thứ trả về luôn là bản đã phát hành thật.
    static func latestRelease() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("xCleaner", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw Failure.noRelease }
            guard (200..<300).contains(http.statusCode) else {
                throw Failure.network("máy chủ trả về mã \(http.statusCode)")
            }
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String else {
            throw Failure.noRelease
        }

        let assets = (root["assets"] as? [[String: Any]]) ?? []
        // Ưu tiên .zip: đó là thứ `ditto` giải nén được mà không phải gắn ổ đĩa như .dmg.
        let asset = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
            ?? assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
        guard let asset,
              let urlString = asset["browser_download_url"] as? String,
              let archiveURL = URL(string: urlString) else {
            throw Failure.noArchive(tag)
        }

        var published: Date?
        if let iso = root["published_at"] as? String {
            published = ISO8601DateFormatter().date(from: iso)
        }

        return ReleaseInfo(
            version: SemanticVersion(tag),
            tag: tag,
            title: (root["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag,
            notes: (root["body"] as? String) ?? "",
            archiveURL: archiveURL,
            archiveName: (asset["name"] as? String) ?? "xCleaner.zip",
            sizeBytes: Int64((asset["size"] as? Int) ?? 0),
            publishedAt: published)
    }

    // MARK: Tải về

    static func download(_ release: ReleaseInfo,
                         progress: @escaping (Double) -> Void) async throws -> URL {
        let (tempFile, response) = try await withCheckedThrowingContinuation {
            (c: CheckedContinuation<(URL, URLResponse), Error>) in
            let task = URLSession.shared.downloadTask(with: release.archiveURL) { url, resp, error in
                if let error { c.resume(throwing: Failure.network(error.localizedDescription)); return }
                guard let url, let resp else {
                    c.resume(throwing: Failure.network("không nhận được tệp"))
                    return
                }
                c.resume(returning: (url, resp))
            }
            // Báo tiến độ để người dùng biết nó đang tải chứ không phải treo.
            let observation = task.progress.observe(\.fractionCompleted) { p, _ in
                DispatchQueue.main.async { progress(p.fractionCompleted) }
            }
            task.resume()
            _ = observation
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.network("máy chủ trả về mã \(http.statusCode)")
        }

        // URLSession xoá tệp tạm ngay khi callback kết thúc, nên phải dời nó đi chỗ của mình.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xCleaner-update-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(release.archiveName)
        do {
            try FileManager.default.moveItem(at: tempFile, to: destination)
        } catch {
            throw Failure.badArchive(error.localizedDescription)
        }
        return destination
    }

    // MARK: Cài đặt

    /// Giải nén, kiểm tra gói, rồi thay chính mình và mở lại.
    ///
    /// App đang chạy không tự xoá được bundle của mình, nên phần thay thế giao cho một đoạn
    /// script: nó chờ tiến trình này thoát hẳn rồi mới đổi thư mục và mở lại app.
    static func install(archive: URL) throws {
        let fm = FileManager.default
        let workDir = archive.deletingLastPathComponent()
        let unpacked = workDir.appendingPathComponent("unpacked", isDirectory: true)
        try? fm.createDirectory(at: unpacked, withIntermediateDirectories: true)

        let extract = Process()
        extract.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extract.arguments = ["-x", "-k", archive.path, unpacked.path]
        let pipe = Pipe()
        extract.standardError = pipe
        do { try extract.run() } catch {
            throw Failure.badArchive(error.localizedDescription)
        }
        let errData = pipe.fileHandleForReading.readDataToEndOfFile()
        extract.waitUntilExit()
        guard extract.terminationStatus == 0 else {
            throw Failure.badArchive(String(data: errData, encoding: .utf8) ?? "giải nén thất bại")
        }

        guard let newApp = FileUtils.children(of: unpacked).first(where: { $0.pathExtension == "app" })
        else { throw Failure.badArchive("trong gói không có ứng dụng nào") }

        // Gói phải tự nhận là xCleaner. Không có bước này thì bất cứ thứ gì tải về cũng được
        // chép đè lên app đang cài.
        let expected = Bundle.main.bundleIdentifier ?? "com.pikalong.xCleaner"
        guard let newBundle = Bundle(url: newApp),
              newBundle.bundleIdentifier == expected else {
            throw Failure.badArchive("đây không phải xCleaner (định danh gói không khớp)")
        }

        let target = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw Failure.installFailed("không có quyền ghi vào \(FileUtils.prettyPath(target.deletingLastPathComponent()))")
        }

        let script = """
        #!/bin/sh
        # Chờ xCleaner thoát hẳn rồi mới đụng vào bundle của nó.
        for i in $(seq 1 100); do
            /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null || break
            /bin/sleep 0.2
        done
        /bin/rm -rf \(PrivilegedRunner.shellQuote(target.path))
        /usr/bin/ditto \(PrivilegedRunner.shellQuote(newApp.path)) \(PrivilegedRunner.shellQuote(target.path))
        # App tự ký mà tải từ mạng thì Gatekeeper giữ cờ cách ly — gỡ đi, nếu không mở lên là báo hỏng.
        /usr/bin/xattr -cr \(PrivilegedRunner.shellQuote(target.path))
        /usr/bin/open \(PrivilegedRunner.shellQuote(target.path))
        /bin/rm -rf \(PrivilegedRunner.shellQuote(workDir.path))
        """
        let scriptURL = workDir.appendingPathComponent("swap.sh")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/sh")
        swap.arguments = [scriptURL.path]
        do { try swap.run() } catch {
            throw Failure.installFailed(error.localizedDescription)
        }
    }
}
