import Foundation

/// Thực hiện việc xoá. Tách hẳn khỏi phần quét để chỉ có đúng một chỗ chạm vào đĩa.
enum Remover {

    struct Request {
        var items: [CleanItem]
        /// Chuyển vào Thùng rác thay vì xoá vĩnh viễn (chỉ áp dụng cho tệp không cần quyền root).
        var moveToTrash: Bool
        /// Câu hiển thị trong hộp thoại xin mật khẩu.
        var adminPrompt: String
        /// Cho phép dừng giữa chừng. Phần đã xoá vẫn là đã xoá.
        var cancel: CancelToken? = nil
    }

    /// - Parameters:
    ///   - progress: gọi trên hàng đợi nền, đã được tiết chế bởi lớp gọi.
    ///   - itemFinished: mỗi mục vừa xử lý xong, để màn hình tick dần từng dòng.
    static func perform(_ request: Request,
                        progress: @escaping (Double, String) -> Void,
                        itemFinished: @escaping (CleanItem, Bool) -> Void = { _, _ in }) -> CleanOutcome {
        var outcome = CleanOutcome()
        let fm = FileManager.default

        var userItems: [CleanItem] = []
        var adminItems: [CleanItem] = []

        for item in request.items {
            if let reason = SafetyGuard.validate(item.url) {
                // Mục đã biến mất từ lúc quét thì coi như xong, không báo lỗi.
                if case .notExist = reason { continue }
                outcome.failures.append((item.url, reason.localizedDescription))
                NSLog("[xCleaner] SafetyGuard chặn: %@ — %@", item.url.path, reason.localizedDescription)
                continue
            }
            if item.requiresAdmin || PrivilegedRunner.needsAdmin(for: item.url) {
                adminItems.append(item)
            } else {
                userItems.append(item)
            }
        }

        let total = max(1, userItems.count + (adminItems.isEmpty ? 0 : 1))
        var done = 0
        /// Những mục xoá trực tiếp không nổi, đã đẩy sang đợt chạy bằng root.
        var escalatedIDs: Set<UUID> = []
        var trashed = 0

        // ---- Phần không cần quyền: xoá trực tiếp ----
        for item in userItems {
            if request.cancel?.isCancelled == true {
                outcome.wasCancelled = true
                break
            }
            done += 1
            progress(Double(done) / Double(total), item.name)

            let targets: [URL] = item.emptyContentsOnly ? FileUtils.children(of: item.url) : [item.url]
            var itemFailed = false

            for t in targets {
                do {
                    if request.moveToTrash {
                        var resulting: NSURL?
                        try fm.trashItem(at: t, resultingItemURL: &resulting)
                        if resulting != nil { trashed += 1 }
                    } else {
                        try fm.removeItem(at: t)
                    }
                } catch {
                    let ns = error as NSError
                    // Không đủ quyền → chuyển sang đợt chạy bằng root thay vì báo lỗi.
                    if ns.domain == NSCocoaErrorDomain &&
                        (ns.code == NSFileWriteNoPermissionError || ns.code == NSFileReadNoPermissionError) {
                        var escalated = item
                        escalated.requiresAdmin = true
                        adminItems.append(escalated)
                        escalatedIDs.insert(item.id)
                        itemFailed = true
                        break
                    }
                    if fm.fileExists(atPath: t.path) {
                        outcome.failures.append((t, ns.localizedDescription))
                        itemFailed = true
                    }
                }
            }

            if !itemFailed {
                outcome.removedCount += 1
                outcome.freedBytes += item.size
                if trashed > 0 { outcome.trashedCount += 1; trashed = 0 }
            }
            trashed = 0
            // Mục vừa chuyển sang đợt chạy bằng root thì chưa xong — đợt sau sẽ báo kết quả
            // thật của nó. Báo ngay ở đây là màn hình đếm mục đó hai lần.
            if !escalatedIDs.contains(item.id) { itemFinished(item, !itemFailed) }
        }

        // ---- Phần cần quyền root: gom một lần hỏi mật khẩu ----
        if !adminItems.isEmpty && !outcome.wasCancelled {
            progress(Double(done) / Double(total), "Đang chờ quyền quản trị…")
            outcome.usedAdmin = true

            let direct = adminItems.filter { !$0.emptyContentsOnly }.map(\.url)
            let toEmpty = adminItems.filter(\.emptyContentsOnly).map(\.url)

            do {
                var report = PrivilegedRunner.Report()
                if !direct.isEmpty {
                    report = try PrivilegedRunner.remove(paths: direct, prompt: request.adminPrompt)
                }
                // Thư mục cần dọn ruột giao hẳn cho root: tự liệt kê bằng quyền người dùng
                // thì thư mục root-only trả về danh sách rỗng và app tưởng đã dọn xong.
                if !toEmpty.isEmpty {
                    let r = try PrivilegedRunner.emptyContents(of: toEmpty, prompt: request.adminPrompt)
                    report.errorLines.append(contentsOf: r.errorLines)
                }
                for line in report.errorLines.prefix(20) {
                    NSLog("[xCleaner] rm(root): %@", line)
                }
                // Xác nhận từng mục thay vì tin vào mã thoát của rm.
                for item in adminItems {
                    let gone: Bool
                    if item.emptyContentsOnly {
                        // Thư mục mình không được phép đọc thì "rỗng" chẳng chứng minh điều gì —
                        // lúc đó dựa vào việc lệnh chạy dưới quyền root có kêu ca gì không.
                        gone = FileUtils.directoryState(item.url) == .blocked
                            ? report.errorLines.isEmpty
                            : FileUtils.children(of: item.url).isEmpty
                    } else {
                        gone = !FileUtils.exists(item.url)
                    }
                    if gone {
                        outcome.removedCount += 1
                        outcome.freedBytes += item.size
                    } else {
                        outcome.failures.append((item.url, "Không xoá được dù đã có quyền quản trị."))
                    }
                    itemFinished(item, gone)
                }
            } catch PrivilegedRunner.Failure.cancelledByUser {
                outcome.wasCancelled = true
            } catch {
                for item in adminItems {
                    outcome.failures.append((item.url, error.localizedDescription))
                }
            }
            done += 1
            progress(1.0, "Hoàn tất")
        }

        progress(1.0, "Hoàn tất")
        return outcome
    }

    /// Dọn Thùng rác (mọi ổ đĩa) — dùng API riêng vì Thùng rác ở ổ ngoài nằm ở `/Volumes/X/.Trashes/<uid>`.
    static func emptyTrash(items: [CleanItem]) -> CleanOutcome {
        var outcome = CleanOutcome()
        let fm = FileManager.default
        for item in items {
            do {
                try fm.removeItem(at: item.url)
                outcome.removedCount += 1
                outcome.freedBytes += item.size
            } catch {
                outcome.failures.append((item.url, error.localizedDescription))
            }
        }
        return outcome
    }
}
