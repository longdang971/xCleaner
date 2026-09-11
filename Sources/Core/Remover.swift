import Foundation

/// Thực hiện việc xoá. Tách hẳn khỏi phần quét để chỉ có đúng một chỗ chạm vào đĩa.
enum Remover {

    struct Request {
        var items: [CleanItem]
        /// Chuyển vào Thùng rác thay vì xoá vĩnh viễn (chỉ áp dụng cho tệp không cần quyền root).
        var moveToTrash: Bool
        /// Câu hiển thị trong hộp thoại xin mật khẩu.
        var adminPrompt: String
    }

    /// - Parameter progress: gọi trên hàng đợi nền, đã được tiết chế bởi lớp gọi.
    static func perform(_ request: Request,
                        progress: @escaping (Double, String) -> Void) -> CleanOutcome {
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

        // ---- Phần không cần quyền: xoá trực tiếp ----
        for item in userItems {
            done += 1
            progress(Double(done) / Double(total), item.name)

            let targets: [URL] = item.emptyContentsOnly ? FileUtils.children(of: item.url) : [item.url]
            var itemFailed = false

            for t in targets {
                do {
                    if request.moveToTrash && !item.emptyContentsOnly {
                        var resulting: NSURL?
                        try fm.trashItem(at: t, resultingItemURL: &resulting)
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
            }
        }

        // ---- Phần cần quyền root: gom một lần hỏi mật khẩu ----
        if !adminItems.isEmpty {
            progress(Double(done) / Double(total), "Đang chờ quyền quản trị…")
            outcome.usedAdmin = true

            let direct = adminItems.filter { !$0.emptyContentsOnly }.map(\.url)
            let toEmpty = adminItems.filter(\.emptyContentsOnly).map(\.url)

            var paths = direct
            for d in toEmpty { paths.append(contentsOf: FileUtils.children(of: d)) }

            do {
                let report = try PrivilegedRunner.remove(paths: paths, prompt: request.adminPrompt)
                for line in report.errorLines.prefix(20) {
                    NSLog("[xCleaner] rm(root): %@", line)
                }
                // Xác nhận từng mục thay vì tin vào mã thoát của rm.
                for item in adminItems {
                    let gone = item.emptyContentsOnly
                        ? FileUtils.children(of: item.url).isEmpty
                        : !FileUtils.exists(item.url)
                    if gone {
                        outcome.removedCount += 1
                        outcome.freedBytes += item.size
                    } else {
                        outcome.failures.append((item.url, "Không xoá được dù đã có quyền quản trị."))
                    }
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
