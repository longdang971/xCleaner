import SwiftUI

/// Trạng thái của việc kiểm tra và cài bản mới.
///
/// Không tự kiểm lúc khởi động hay theo giờ: người dùng bấm thì mới hỏi GitHub. Một app dọn
/// rác không cần đi ra mạng sau lưng ai.
@MainActor
final class UpdateController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(tag: String)
        case downloading(Double)
        case readyToRestart
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var release: ReleaseInfo?
    /// Lần kiểm gần nhất, để người dùng biết con số "đã mới nhất" cũ tới đâu.
    @Published private(set) var lastChecked: Date?

    var currentVersion: String { SemanticVersion.current.description }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading: return true
        default: return false
        }
    }

    #if DEBUG
    /// Chỉ dùng để chạy thử toàn bộ đường tải-và-thay mà không phải bấm tay.
    /// Đọc ngay lúc dựng: đặt muộn hơn (trong `onChange` của view) thì lần kiểm đầu tiên
    /// đã chạy xong trước khi cờ kịp bật.
    private(set) var autoInstallWhenAvailable =
        ProcessInfo.processInfo.environment["XCLEANER_UPDATE"] == "install"
    #endif

    func check() {
        guard !isBusy else { return }
        phase = .checking
        Task {
            do {
                let found = try await UpdateService.latestRelease()
                self.release = found
                self.lastChecked = Date()
                self.phase = found.isNewerThanCurrent ? .available(tag: found.tag) : .upToDate
                #if DEBUG
                NSLog("[xCleaner] update: thấy %@, mới hơn=%d, tự cài=%d",
                      found.tag, found.isNewerThanCurrent ? 1 : 0,
                      self.autoInstallWhenAvailable ? 1 : 0)
                if self.autoInstallWhenAvailable, found.isNewerThanCurrent {
                    self.downloadAndInstall()
                }
                #endif
            } catch {
                self.release = nil
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func downloadAndInstall() {
        guard let release, !isBusy else { return }
        phase = .downloading(0)
        Task {
            do {
                NSLog("[xCleaner] update: bắt đầu tải %@", release.archiveURL.absoluteString)
                let archive = try await UpdateService.download(release) { fraction in
                    Task { @MainActor in
                        if case .downloading = self.phase { self.phase = .downloading(fraction) }
                    }
                }
                NSLog("[xCleaner] update: tải xong %@", archive.path)
                self.phase = .readyToRestart
                try UpdateService.install(archive: archive)
                NSLog("[xCleaner] update: script thay thế đã chạy")
                // Script thay thế đang chờ tiến trình này chết; nhường chỗ cho nó.
                try? await Task.sleep(nanoseconds: 400_000_000)
                NSApp.terminate(nil)
            } catch {
                NSLog("[xCleaner] update: hỏng — %@", error.localizedDescription)
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(UpdateService.releasesPage)
    }
}
